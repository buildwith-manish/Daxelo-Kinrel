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
exports.AiCardsController = void 0;
const common_1 = require("@nestjs/common");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const ai_cards_service_1 = require("./ai-cards.service");
const card_dto_1 = require("./dto/card.dto");
let AiCardsController = class AiCardsController {
    constructor(aiCardsService) {
        this.aiCardsService = aiCardsService;
    }
    async getTemplates() {
        return this.aiCardsService.getTemplates();
    }
    async generateFestivalCard(dto) {
        return this.aiCardsService.generateFestivalCard(dto);
    }
    async generateKinshipCard(dto) {
        return this.aiCardsService.generateKinshipCard(dto);
    }
};
exports.AiCardsController = AiCardsController;
__decorate([
    (0, common_1.Get)('templates'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AiCardsController.prototype, "getTemplates", null);
__decorate([
    (0, common_1.Post)('festival'),
    (0, common_1.HttpCode)(common_1.HttpStatus.OK),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [card_dto_1.FestivalCardDto]),
    __metadata("design:returntype", Promise)
], AiCardsController.prototype, "generateFestivalCard", null);
__decorate([
    (0, common_1.Post)('kinship'),
    (0, common_1.HttpCode)(common_1.HttpStatus.OK),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [card_dto_1.KinshipCardDto]),
    __metadata("design:returntype", Promise)
], AiCardsController.prototype, "generateKinshipCard", null);
exports.AiCardsController = AiCardsController = __decorate([
    (0, common_1.Controller)('v1/ai-cards'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [ai_cards_service_1.AiCardsService])
], AiCardsController);
//# sourceMappingURL=ai-cards.controller.js.map