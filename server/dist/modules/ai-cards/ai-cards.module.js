"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AiCardsModule = void 0;
const common_1 = require("@nestjs/common");
const ai_cards_controller_1 = require("./ai-cards.controller");
const ai_cards_service_1 = require("./ai-cards.service");
const kinship_module_1 = require("../kinship/kinship.module");
let AiCardsModule = class AiCardsModule {
};
exports.AiCardsModule = AiCardsModule;
exports.AiCardsModule = AiCardsModule = __decorate([
    (0, common_1.Module)({
        imports: [kinship_module_1.KinshipModule],
        controllers: [ai_cards_controller_1.AiCardsController],
        providers: [ai_cards_service_1.AiCardsService],
        exports: [ai_cards_service_1.AiCardsService],
    })
], AiCardsModule);
//# sourceMappingURL=ai-cards.module.js.map