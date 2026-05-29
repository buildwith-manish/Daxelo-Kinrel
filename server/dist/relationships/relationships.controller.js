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
exports.RelationshipController = exports.RelationshipsController = void 0;
const common_1 = require("@nestjs/common");
const supabase_auth_guard_1 = require("../auth/supabase-auth.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const relationships_service_1 = require("./relationships.service");
const create_relationship_dto_1 = require("../dto/create-relationship.dto");
let RelationshipsController = class RelationshipsController {
    constructor(relationshipsService) {
        this.relationshipsService = relationshipsService;
    }
    async listRelationships(user, familyId) {
        const relationships = await this.relationshipsService.listRelationships(user.id, familyId);
        return { relationships };
    }
    async createRelationship(user, familyId, body) {
        const relationship = await this.relationshipsService.createRelationship(user.id, familyId, body);
        return { relationship };
    }
};
exports.RelationshipsController = RelationshipsController;
__decorate([
    (0, common_1.Get)(),
    (0, common_1.UseGuards)(supabase_auth_guard_1.SupabaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('familyId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], RelationshipsController.prototype, "listRelationships", null);
__decorate([
    (0, common_1.Post)(),
    (0, common_1.UseGuards)(supabase_auth_guard_1.SupabaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, create_relationship_dto_1.CreateRelationshipDto]),
    __metadata("design:returntype", Promise)
], RelationshipsController.prototype, "createRelationship", null);
exports.RelationshipsController = RelationshipsController = __decorate([
    (0, common_1.Controller)('families/:familyId/relationships'),
    __metadata("design:paramtypes", [relationships_service_1.RelationshipsService])
], RelationshipsController);
let RelationshipController = class RelationshipController {
    constructor(relationshipsService) {
        this.relationshipsService = relationshipsService;
    }
    async deleteRelationship(user, id) {
        return this.relationshipsService.deleteRelationship(user.id, id);
    }
};
exports.RelationshipController = RelationshipController;
__decorate([
    (0, common_1.Delete)(':id'),
    (0, common_1.UseGuards)(supabase_auth_guard_1.SupabaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], RelationshipController.prototype, "deleteRelationship", null);
exports.RelationshipController = RelationshipController = __decorate([
    (0, common_1.Controller)('relationships'),
    __metadata("design:paramtypes", [relationships_service_1.RelationshipsService])
], RelationshipController);
//# sourceMappingURL=relationships.controller.js.map