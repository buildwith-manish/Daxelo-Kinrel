"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotificationsController = void 0;
const common_1 = require("@nestjs/common");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
const notifications_service_1 = require("./notifications.service");
const fcm_service_1 = require("./fcm.service");
class RegisterFcmTokenDto {
}
class RemoveFcmTokenDto {
}
let NotificationsController = class NotificationsController {
    constructor(notificationsService, fcmService) {
        this.notificationsService = notificationsService;
        this.fcmService = fcmService;
    }
    async list(userId, limit, unread) {
        return this.notificationsService.listForUser(userId, limit ? parseInt(limit, 10) : 30, unread === 'true');
    }
    async unreadCount(userId) {
        const count = await this.notificationsService.getUnreadCount(userId);
        return { count };
    }
    async markRead(id) {
        return this.notificationsService.markRead(id);
    }
    async markAllRead(userId) {
        return this.notificationsService.markAllRead(userId);
    }
    async registerFcmToken(userId, dto) {
        const result = await this.fcmService.registerToken(userId, dto.token, dto.deviceType || 'unknown');
        return {
            success: true,
            message: 'FCM token registered successfully',
            id: result.id,
        };
    }
    async removeFcmToken(dto) {
        const removed = await this.fcmService.removeToken(dto.token);
        return {
            success: true,
            removed,
            message: removed
                ? 'FCM token removed successfully'
                : 'FCM token not found',
        };
    }
};
exports.NotificationsController = NotificationsController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Query)('limit')),
    __param(2, (0, common_1.Query)('unread')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], NotificationsController.prototype, "list", null);
__decorate([
    (0, common_1.Get)('unread-count'),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], NotificationsController.prototype, "unreadCount", null);
__decorate([
    (0, common_1.Patch)(':id/read'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], NotificationsController.prototype, "markRead", null);
__decorate([
    (0, common_1.Post)('mark-all-read'),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], NotificationsController.prototype, "markAllRead", null);
__decorate([
    (0, common_1.Post)('fcm-token'),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, RegisterFcmTokenDto]),
    __metadata("design:returntype", Promise)
], NotificationsController.prototype, "registerFcmToken", null);
__decorate([
    (0, common_1.Delete)('fcm-token'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [RemoveFcmTokenDto]),
    __metadata("design:returntype", Promise)
], NotificationsController.prototype, "removeFcmToken", null);
exports.NotificationsController = NotificationsController = __decorate([
    (0, common_1.Controller)('notifications'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [notifications_service_1.NotificationsService,
        fcm_service_1.FcmService])
], NotificationsController);
//# sourceMappingURL=notifications.controller.js.map