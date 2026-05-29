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
exports.RelationshipsController = void 0;
const common_1 = require("@nestjs/common");
const relationships_service_1 = require("./relationships.service");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
const create_relationship_dto_1 = require("./dto/create-relationship.dto");
let RelationshipsController = class RelationshipsController {
    constructor(relationshipsService) {
        this.relationshipsService = relationshipsService;
    }
    async findAll(userId, familyId, personId) {
        return this.relationshipsService.findAll(familyId, userId, { personId });
    }
    async create(userId, familyId, dto) {
        return this.relationshipsService.create(userId, familyId, dto);
    }
    async remove(userId, familyId, id) {
        return this.relationshipsService.remove(userId, familyId, id);
    }
};
exports.RelationshipsController = RelationshipsController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Query)('personId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], RelationshipsController.prototype, "findAll", null);
__decorate([
    (0, common_1.Post)(),
    (0, common_1.HttpCode)(common_1.HttpStatus.CREATED),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, create_relationship_dto_1.CreateRelationshipDto]),
    __metadata("design:returntype", Promise)
], RelationshipsController.prototype, "create", null);
__decorate([
    (0, common_1.Delete)(':id'),
    (0, common_1.HttpCode)(common_1.HttpStatus.OK),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], RelationshipsController.prototype, "remove", null);
exports.RelationshipsController = RelationshipsController = __decorate([
    (0, common_1.Controller)('families/:familyId/relationships'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [relationships_service_1.RelationshipsService])
], RelationshipsController);
//# sourceMappingURL=relationships.controller.js.map