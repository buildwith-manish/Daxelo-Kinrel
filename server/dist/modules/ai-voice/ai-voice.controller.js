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
exports.AiVoiceController = void 0;
const common_1 = require("@nestjs/common");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const ai_voice_service_1 = require("./ai-voice.service");
const voice_dto_1 = require("./dto/voice.dto");
let AiVoiceController = class AiVoiceController {
    constructor(aiVoiceService) {
        this.aiVoiceService = aiVoiceService;
    }
    async transcribe(dto) {
        return this.aiVoiceService.transcribe(dto.audio, dto.language);
    }
    async lookup(dto) {
        return this.aiVoiceService.lookup(dto.audio, dto.language);
    }
};
exports.AiVoiceController = AiVoiceController;
__decorate([
    (0, common_1.Post)('transcribe'),
    (0, common_1.HttpCode)(common_1.HttpStatus.OK),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [voice_dto_1.TranscribeDto]),
    __metadata("design:returntype", Promise)
], AiVoiceController.prototype, "transcribe", null);
__decorate([
    (0, common_1.Post)('lookup'),
    (0, common_1.HttpCode)(common_1.HttpStatus.OK),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [voice_dto_1.VoiceLookupDto]),
    __metadata("design:returntype", Promise)
], AiVoiceController.prototype, "lookup", null);
exports.AiVoiceController = AiVoiceController = __decorate([
    (0, common_1.Controller)('v1/ai-voice'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [ai_voice_service_1.AiVoiceService])
], AiVoiceController);
//# sourceMappingURL=ai-voice.controller.js.map