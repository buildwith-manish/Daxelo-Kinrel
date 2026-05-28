import { Injectable, OnModuleInit, Logger } from '@nestjs/common';
import * as admin from 'firebase-admin';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class FcmService implements OnModuleInit {
  private app: admin.app.App | null = null;
  private readonly logger = new Logger(FcmService.name);

  constructor(private prisma: PrismaService) {}

  async onModuleInit() {
    const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!serviceAccountJson) {
      this.logger.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set — FCM push disabled');
      return;
    }
    try {
      const serviceAccount = JSON.parse(serviceAccountJson);
      this.app = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      this.logger.log('Firebase Admin SDK initialized for FCM');
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      this.logger.error('Firebase Admin SDK init failed: ' + msg);
    }
  }

  get isAvailable(): boolean {
    return this.app !== null;
  }

  /** Send a notification to a single user by userId */
  async sendToUser(
    userId: string,
    title: string,
    body: string,
    data: Record<string, string>,
  ): Promise<boolean> {
    if (!this.app) return false;

    try {
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { fcmToken: true },
      });

      if (!user?.fcmToken) return false;

      const message: admin.messaging.Message = {
        token: user.fcmToken,
        notification: { title, body },
        data,
        android: {
          priority: 'high',
          notification: {
            channelId: data['type'] === 'birthday_reminder' ? 'kinrel_birthdays' : 'kinrel_notifications',
          },
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

      await admin.messaging().send(message);
      return true;
    } catch (error: unknown) {
      // If token is invalid, clear it
      const err = error as { code?: string; message?: string };
      if (
        err.code === 'messaging/invalid-registration-token' ||
        err.code === 'messaging/registration-token-not-registered'
      ) {
        await this.prisma.user.update({
          where: { id: userId },
          data: { fcmToken: null },
        });
        this.logger.warn(`Cleared invalid FCM token for user ${userId}`);
      } else {
        this.logger.error(`FCM send failed for user ${userId}: ${err.message ?? String(error)}`);
      }
      return false;
    }
  }

  /** Send a notification to multiple users (batch, max 500 per batch) */
  async sendToMultiple(
    userIds: string[],
    title: string,
    body: string,
    data: Record<string, string>,
  ): Promise<number> {
    if (!this.app || userIds.length === 0) return 0;

    try {
      // Fetch FCM tokens for all users
      const users = await this.prisma.user.findMany({
        where: { id: { in: userIds }, fcmToken: { not: null } },
        select: { id: true, fcmToken: true },
      });

      const tokens = users.map((u) => u.fcmToken!);
      if (tokens.length === 0) return 0;

      let successCount = 0;
      // Batch in groups of 500
      for (let i = 0; i < tokens.length; i += 500) {
        const batch = tokens.slice(i, i + 500);
        const message: admin.messaging.MulticastMessage = {
          tokens: batch,
          notification: { title, body },
          data,
          android: {
            priority: 'high',
            notification: {
              channelId: data['type'] === 'birthday_reminder' ? 'kinrel_birthdays' : 'kinrel_notifications',
            },
          },
          apns: {
            payload: {
              aps: { sound: 'default', badge: 1 },
            },
          },
        };

        const response = await admin.messaging().sendEachForMulticast(message);
        successCount += response.successCount;

        // Clear invalid tokens
        const invalidTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const failedToken = batch[idx];
            if (
              resp.error?.code === 'messaging/invalid-registration-token' ||
              resp.error?.code === 'messaging/registration-token-not-registered'
            ) {
              invalidTokens.push(failedToken);
            }
          }
        });

        if (invalidTokens.length > 0) {
          await this.prisma.user.updateMany({
            where: { fcmToken: { in: invalidTokens } },
            data: { fcmToken: null },
          });
          this.logger.warn(`Cleared ${invalidTokens.length} invalid FCM tokens`);
        }
      }

      return successCount;
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : String(error);
      this.logger.error(`FCM batch send failed: ${msg}`);
      return 0;
    }
  }
}
