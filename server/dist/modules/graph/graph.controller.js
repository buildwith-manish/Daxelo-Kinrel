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
exports.GraphController = void 0;
const common_1 = require("@nestjs/common");
const graph_service_1 = require("./graph.service");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
let GraphController = class GraphController {
    constructor(graphService) {
        this.graphService = graphService;
    }
    async getGraph(userId, familyId, root, depth, format, from, to, locale) {
        return this.graphService.getGraph(userId, familyId, {
            root,
            depth: depth ? parseInt(depth, 10) : undefined,
            format: format || 'flat',
            from,
            to,
            locale,
        });
    }
    async getTree(userId, familyId, root, depth, locale) {
        const rootPersonId = await this.graphService.resolveRootPersonId(userId, familyId, root);
        return this.graphService.getTree(familyId, rootPersonId, depth ? parseInt(depth, 10) : 10);
    }
    async getPath(userId, familyId, from, to) {
        if (!from || !to) {
            throw new common_1.BadRequestException('Both "from" and "to" query parameters are required for path finding');
        }
        return this.graphService.getPathWithAuth(userId, familyId, from, to);
    }
};
exports.GraphController = GraphController;
__decorate([
    (0, common_1.Get)(':familyId'),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Query)('root')),
    __param(3, (0, common_1.Query)('depth')),
    __param(4, (0, common_1.Query)('format')),
    __param(5, (0, common_1.Query)('from')),
    __param(6, (0, common_1.Query)('to')),
    __param(7, (0, common_1.Query)('locale')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, String, String, String, String, String]),
    __metadata("design:returntype", Promise)
], GraphController.prototype, "getGraph", null);
__decorate([
    (0, common_1.Get)(':familyId/tree'),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Query)('root')),
    __param(3, (0, common_1.Query)('depth')),
    __param(4, (0, common_1.Query)('locale')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, String, String]),
    __metadata("design:returntype", Promise)
], GraphController.prototype, "getTree", null);
__decorate([
    (0, common_1.Get)(':familyId/path'),
    __param(0, (0, current_user_decorator_1.CurrentUser)('id')),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Query)('from')),
    __param(3, (0, common_1.Query)('to')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, String]),
    __metadata("design:returntype", Promise)
], GraphController.prototype, "getPath", null);
exports.GraphController = GraphController = __decorate([
    (0, common_1.Controller)('graph'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [graph_service_1.GraphService])
], GraphController);
//# sourceMappingURL=graph.controller.js.map