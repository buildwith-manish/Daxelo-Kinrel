"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var FcmService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.FcmService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const prisma_service_1 = require("../../prisma/prisma.service");
const firebaseAdmin = __importStar(require("firebase-admin"));
let FcmService = FcmService_1 = class FcmService {
    constructor(prisma, configService) {
        this.prisma = prisma;
        this.configService = configService;
        this.logger = new common_1.Logger(FcmService_1.name);
        this.firebaseApp = null;
        this.isFirebaseInitialized = false;
        this.retryQueue = [];
        this.retryTimer = null;
    }
    async onModuleInit() {
        this.initializeFirebase();
        if (this.isFirebaseInitialized) {
            this.retryTimer = setInterval(() => this.processRetryQueue(), 5 * 60 * 1000);
        }
    }
    initializeFirebase() {
        const projectId = this.configService.get('FIREBASE_PROJECT_ID');
        const clientEmail = this.configService.get('FIREBASE_CLIENT_EMAIL');
        const privateKey = this.configService
            .get('FIREBASE_PRIVATE_KEY')
            ?.replace(/\\n/g, '\n');
        if (!projectId || !clientEmail || !privateKey) {
            this.logger.warn('Firebase credentials not configured (FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY). ' +
                'FCM push notifications will be disabled. In-app notifications still work.');
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
        }
        catch (error) {
            if (error?.code === 'app/duplicate-app') {
                this.firebaseApp = firebaseAdmin.app();
                this.isFirebaseInitialized = true;
                this.logger.log('🔥 Firebase Admin SDK reattached (existing app)');
            }
            else {
                this.logger.error(`Failed to initialize Firebase Admin SDK: ${error?.message}`, error?.stack);
            }
        }
    }
    async sendToUser(userId, notification) {
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
    async sendToUsers(userIds, notification) {
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
    async sendMulticast(tokens, notification) {
        if (!this.isFirebaseInitialized || tokens.length === 0) {
            return false;
        }
        const BATCH_SIZE = 500;
        let allSuccess = true;
        for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
            const batch = tokens.slice(i, i + BATCH_SIZE);
            try {
                const message = {
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
                const response = await firebaseAdmin.messaging(this.firebaseApp).sendEachForMulticast(message);
                this.logger.debug(`FCM multicast sent: ${response.successCount} success, ${response.failureCount} failed out of ${batch.length} tokens`);
                if (response.failureCount > 0) {
                    const failedTokens = [];
                    response.responses.forEach((resp, idx) => {
                        if (!resp.success) {
                            const failedToken = batch[idx];
                            const errorCode = resp.error?.code;
                            if (errorCode === 'messaging/invalid-registration-token' ||
                                errorCode === 'messaging/registration-token-not-registered') {
                                failedTokens.push(failedToken);
                                this.logger.warn(`Removing invalid FCM token: ${failedToken.substring(0, 20)}...`);
                            }
                            else {
                                this.queueForRetry(failedToken, notification);
                            }
                        }
                    });
                    if (failedTokens.length > 0) {
                        await this.removeTokens(failedTokens);
                    }
                    allSuccess = false;
                }
                const successfulTokens = [];
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
            }
            catch (error) {
                this.logger.error(`FCM multicast error: ${error?.message}`, error?.stack);
                allSuccess = false;
                batch.forEach((token) => this.queueForRetry(token, notification));
            }
        }
        return allSuccess;
    }
    async registerToken(userId, token, deviceType = 'unknown') {
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
    async removeToken(token) {
        const result = await this.prisma.fcmToken.deleteMany({
            where: { token },
        });
        return result.count > 0;
    }
    async removeTokens(tokens) {
        try {
            await this.prisma.fcmToken.deleteMany({
                where: { token: { in: tokens } },
            });
            this.logger.debug(`Removed ${tokens.length} invalid FCM tokens`);
        }
        catch (error) {
            this.logger.error(`Error removing FCM tokens: ${error?.message}`);
        }
    }
    queueForRetry(token, notification) {
        const existing = this.retryQueue.find((item) => item.token === token && item.notification.title === notification.title);
        if (existing) {
            return;
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
    async processRetryQueue() {
        if (this.retryQueue.length === 0)
            return;
        this.logger.debug(`Processing FCM retry queue: ${this.retryQueue.length} items`);
        const toRetry = [...this.retryQueue];
        this.retryQueue = [];
        for (const item of toRetry) {
            item.attemptCount++;
            if (item.attemptCount > item.maxAttempts) {
                this.logger.warn(`Dropping FCM notification after ${item.maxAttempts} failed attempts: token=${item.token.substring(0, 20)}...`);
                continue;
            }
            try {
                const message = {
                    token: item.token,
                    notification: {
                        title: item.notification.title,
                        body: item.notification.body,
                    },
                    data: item.notification.data || {},
                };
                await firebaseAdmin.messaging(this.firebaseApp).send(message);
                this.logger.debug(`FCM retry succeeded for token=${item.token.substring(0, 20)}...`);
            }
            catch (error) {
                const errorCode = error?.errorInfo?.code || error?.code;
                if (errorCode === 'messaging/invalid-registration-token' ||
                    errorCode === 'messaging/registration-token-not-registered') {
                    await this.removeTokens([item.token]);
                    continue;
                }
                if (item.attemptCount < item.maxAttempts) {
                    this.retryQueue.push(item);
                }
                else {
                    this.logger.warn(`FCM retry failed after ${item.attemptCount} attempts: token=${item.token.substring(0, 20)}...`);
                }
            }
        }
    }
    isAvailable() {
        return this.isFirebaseInitialized;
    }
};
exports.FcmService = FcmService;
exports.FcmService = FcmService = FcmService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService])
], FcmService);
//# sourceMappingURL=fcm.service.js.map