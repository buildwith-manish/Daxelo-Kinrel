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
var SyncController_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SyncController = void 0;
const common_1 = require("@nestjs/common");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
const sync_service_1 = require("./sync.service");
const sync_query_dto_1 = require("./dto/sync-query.dto");
let SyncController = SyncController_1 = class SyncController {
    constructor(syncService) {
        this.syncService = syncService;
        this.logger = new common_1.Logger(SyncController_1.name);
    }
    async sync(authenticatedUserId, dto) {
        if (dto.userId && dto.userId !== authenticatedUserId) {
            dto.userId = authenticatedUserId;
        }
        this.logger.debug(`Sync requested by user ${authenticatedUserId} since ${dto.since ?? 'epoch'}`);
        return this.syncService.sync(dto.since, authenticatedUserId);
    }
};
exports.SyncController = SyncController;
__decorate([
    (0, common_1.Post)(),
    (0, common_1.HttpCode)(common_1.HttpStatus.OK),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, sync_query_dto_1.SyncQueryDto]),
    __metadata("design:returntype", Promise)
], SyncController.prototype, "sync", null);
exports.SyncController = SyncController = SyncController_1 = __decorate([
    (0, common_1.Controller)('sync'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [sync_service_1.SyncService])
], SyncController);
//# sourceMappingURL=sync.controller.js.map