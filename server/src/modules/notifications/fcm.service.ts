import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import * as firebaseAdmin from 'firebase-admin';

/**
 * FcmService — Firebase Cloud Messaging service for sending push notifications.
 *
 * - Uses firebase-admin SDK to send FCM push notifications
 * - Handles missing Firebase credentials gracefully (logs warning, doesn't crash)
 * - Removes invalid/expired tokens from DB
 * - Retries failed notifications up to 3 attempts
 */

interface FcmNotification {
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface QueuedNotification {
  token: string;
  notification: FcmNotification;
  attemptCount: number;
  maxAttempts: number;
}

@Injectable()
export class FcmService implements OnModuleInit {
  private readonly logger = new Logger(FcmService.name);
  private firebaseApp: firebaseAdmin.app.App | null = null;
  private isFirebaseInitialized = false;
  private retryQueue: QueuedNotification[] = [];
  private retryTimer: ReturnType<typeof setInterval> | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  async onModuleInit() {
    this.initializeFirebase();

    // Start retry timer — process retry queue every 5 minutes
    if (this.isFirebaseInitialized) {
      this.retryTimer = setInterval(() => this.processRetryQueue(), 5 * 60 * 1000);
    }
  }

  /**
   * Initialize Firebase Admin SDK.
   * If FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY
   * are not set, logs a warning and continues without FCM support.
   */
  private initializeFirebase() {
    const projectId = this.configService.get<string>('FIREBASE_PROJECT_ID');
    const clientEmail = this.configService.get<string>('FIREBASE_CLIENT_EMAIL');
    const privateKey = this.configService
      .get<string>('FIREBASE_PRIVATE_KEY')
      ?.replace(/\\n/g, '\n'); // Handle escaped newlines in env var

    if (!projectId || !clientEmail || !privateKey) {
      this.logger.warn(
        'Firebase credentials not configured (FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY). ' +
          'FCM push notifications will be disabled. In-app notifications still work.',
      );
      return;
    }

    try {
      this.firebaseApp = firebaseAdmin.initializeApp({
        credential: firebaseAdmin.credential.cert({
          projectId,
          clientEmail,
          privateKey,
        }),
      });
      this.isFirebaseInitialized = true;
      this.logger.log('🔥 Firebase Admin SDK initialized — FCM push notifications enabled');
    } catch (error: any) {
      if (error?.code === 'app/duplicate-app') {
        // App already initialized (can happen with hot reload)
        this.firebaseApp = firebaseAdmin.app();
        this.isFirebaseInitialized = true;
        this.logger.log('🔥 Firebase Admin SDK reattached (existing app)');
      } else {
        this.logger.error(
          `Failed to initialize Firebase Admin SDK: ${error?.message}`,
          error?.stack,
        );
      }
    }
  }

  /**
   * Send a push notification to a specific user (all their FCM tokens).
   */
  async sendToUser(userId: string, notification: FcmNotification): Promise<boolean> {
    if (!this.isFirebaseInitialized) {
      this.logger.debug(`FCM not initialized — skipping push to user ${userId}`);
      return false;
    }

    const tokens = await this.prisma.fcmToken.findMany({
      where: { userId },
      select: { id: true, token: true },
    });

    if (tokens.length === 0) {
      this.logger.debug(`No FCM tokens found for user ${userId}`);
      return false;
    }

    const tokenStrings = tokens.map((t) => t.token);
    return this.sendMulticast(tokenStrings, notification);
  }

  /**
   * Send a push notification to multiple users (all their FCM tokens).
   */
  async sendToUsers(userIds: string[], notification: FcmNotification): Promise<boolean> {
    if (!this.isFirebaseInitialized || userIds.length === 0) {
      return false;
    }

    const tokens = await this.prisma.fcmToken.findMany({
      where: { userId: { in: userIds } },
      select: { id: true, token: true, userId: true },
    });

    if (tokens.length === 0) {
      return false;
    }

    const tokenStrings = tokens.map((t) => t.token);
    return this.sendMulticast(tokenStrings, notification);
  }

  /**
   * Send a push notification to multiple FCM tokens directly.
   * Handles invalid/expired tokens by removing them from DB.
   * Queues failed sends for retry (up to 3 attempts).
   */
  async sendMulticast(tokens: string[], notification: FcmNotification): Promise<boolean> {
    if (!this.isFirebaseInitialized || tokens.length === 0) {
      return false;
    }

    // FCM multicast supports up to 500 tokens per request
    const BATCH_SIZE = 500;
    let allSuccess = true;

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const batch = tokens.slice(i, i + BATCH_SIZE);

      try {
        const message: firebaseAdmin.messaging.MulticastMessage = {
          tokens: batch,
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data: notification.data || {},
          android: {
            priority: 'high',
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: 1,
              },
            },
          },
        };

        const response = await firebaseAdmin.messaging(this.firebaseApp!).sendEachForMulticast(message);

        this.logger.debug(
          `FCM multicast sent: ${response.successCount} success, ${response.failureCount} failed out of ${batch.length} tokens`,
        );

        // Handle failed tokens
        if (response.failureCount > 0) {
          const failedTokens: string[] = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              const failedToken = batch[idx];
              const errorCode = resp.error?.code;

              // Remove invalid/expired tokens
              if (
                errorCode === 'messaging/invalid-registration-token' ||
                errorCode === 'messaging/registration-token-not-registered'
              ) {
                failedTokens.push(failedToken);
                this.logger.warn(`Removing invalid FCM token: ${failedToken.substring(0, 20)}...`);
              } else {
                // Queue for retry on transient failures
                this.queueForRetry(failedToken, notification);
              }
            }
          });

          // Remove invalid tokens from DB
          if (failedTokens.length > 0) {
            await this.removeTokens(failedTokens);
          }

          allSuccess = false;
        }

        // Update lastUsedAt for successful tokens
        const successfulTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (resp.success) {
            successfulTokens.push(batch[idx]);
          }
        });

        if (successfulTokens.length > 0) {
          await this.prisma.fcmToken.updateMany({
            where: { token: { in: successfulTokens } },
            data: { lastUsedAt: new Date() },
          });
        }
      } catch (error: any) {
        this.logger.error(`FCM multicast error: ${error?.message}`, error?.stack);
        allSuccess = false;

        // Queue all tokens in batch for retry
        batch.forEach((token) => this.queueForRetry(token, notification));
      }
    }

    return allSuccess;
  }

  /**
   * Register or update an FCM token for a user.
   * If the token already exists (for any user), reassign it to the current user.
   * This handles the case where a device changes ownership.
   */
  async registerToken(userId: string, token: string, deviceType: string = 'unknown'): Promise<any> {
    // Upsert: if token exists, update it; otherwise create new
    return this.prisma.fcmToken.upsert({
      where: { token },
      update: {
        userId,
        deviceType,
        lastUsedAt: new Date(),
      },
      create: {
        token,
        userId,
        deviceType,
        lastUsedAt: new Date(),
      },
    });
  }

  /**
   * Remove an FCM token (on sign-out).
   */
  async removeToken(token: string): Promise<boolean> {
    const result = await this.prisma.fcmToken.deleteMany({
      where: { token },
    });
    return result.count > 0;
  }

  /**
   * Remove multiple invalid/expired tokens from DB.
   */
  private async removeTokens(tokens: string[]): Promise<void> {
    try {
      await this.prisma.fcmToken.deleteMany({
        where: { token: { in: tokens } },
      });
      this.logger.debug(`Removed ${tokens.length} invalid FCM tokens`);
    } catch (error: any) {
      this.logger.error(`Error removing FCM tokens: ${error?.message}`);
    }
  }

  /**
   * Queue a failed notification for retry.
   */
  private queueForRetry(token: string, notification: FcmNotification): void {
    // Don't queue if already at max attempts
    const existing = this.retryQueue.find(
      (item) => item.token === token && item.notification.title === notification.title,
    );

    if (existing) {
      return; // Already queued
    }

    if (this.retryQueue.length >= 1000) {
      this.logger.warn('Retry queue full — dropping oldest notification');
      this.retryQueue.shift();
    }

    this.retryQueue.push({
      token,
      notification,
      attemptCount: 0,
      maxAttempts: 3,
    });
  }

  /**
   * Process the retry queue — attempt to resend failed notifications.
   */
  private async processRetryQueue(): Promise<void> {
    if (this.retryQueue.length === 0) return;

    this.logger.debug(`Processing FCM retry queue: ${this.retryQueue.length} items`);

    const toRetry = [...this.retryQueue];
    this.retryQueue = [];

    for (const item of toRetry) {
      item.attemptCount++;

      if (item.attemptCount > item.maxAttempts) {
        this.logger.warn(
          `Dropping FCM notification after ${item.maxAttempts} failed attempts: token=${item.token.substring(0, 20)}...`,
        );
        continue;
      }

      try {
        const message: firebaseAdmin.messaging.Message = {
          token: item.token,
          notification: {
            title: item.notification.title,
            body: item.notification.body,
          },
          data: item.notification.data || {},
        };

        await firebaseAdmin.messaging(this.firebaseApp!).send(message);
        this.logger.debug(`FCM retry succeeded for token=${item.token.substring(0, 20)}...`);
      } catch (error: any) {
        const errorCode = error?.errorInfo?.code || error?.code;

        // If token is invalid, remove it
        if (
          errorCode === 'messaging/invalid-registration-token' ||
          errorCode === 'messaging/registration-token-not-registered'
        ) {
          await this.removeTokens([item.token]);
          continue;
        }

        // Re-queue for another retry
        if (item.attemptCount < item.maxAttempts) {
          this.retryQueue.push(item);
        } else {
          this.logger.warn(
            `FCM retry failed after ${item.attemptCount} attempts: token=${item.token.substring(0, 20)}...`,
          );
        }
      }
    }
  }

  /**
   * Check if Firebase is properly initialized and FCM is available.
   */
  isAvailable(): boolean {
    return this.isFirebaseInitialized;
  }
}
