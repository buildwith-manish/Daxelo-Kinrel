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
exports.KinshipController = void 0;
const common_1 = require("@nestjs/common");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const kinship_service_1 = require("./kinship.service");
const kinship_query_dto_1 = require("./dto/kinship-query.dto");
let KinshipController = class KinshipController {
    constructor(kinshipService) {
        this.kinshipService = kinshipService;
    }
    async lookup(query) {
        return this.kinshipService.lookup(query);
    }
    async search(term, lang, limit = '20') {
        return this.kinshipService.searchByTermAndLang(term, lang, parseInt(limit));
    }
    async getLanguages() {
        return this.kinshipService.getSupportedLanguages();
    }
};
exports.KinshipController = KinshipController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [kinship_query_dto_1.KinshipQueryDto]),
    __metadata("design:returntype", Promise)
], KinshipController.prototype, "lookup", null);
__decorate([
    (0, common_1.Get)('search'),
    __param(0, (0, common_1.Query)('term')),
    __param(1, (0, common_1.Query)('lang')),
    __param(2, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object]),
    __metadata("design:returntype", Promise)
], KinshipController.prototype, "search", null);
__decorate([
    (0, common_1.Get)('languages'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], KinshipController.prototype, "getLanguages", null);
exports.KinshipController = KinshipController = __decorate([
    (0, common_1.Controller)('v1/kinship'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [kinship_service_1.KinshipService])
], KinshipController);
//# sourceMappingURL=kinship.controller.js.map