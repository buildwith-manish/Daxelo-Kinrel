"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AiVoiceModule = void 0;
const common_1 = require("@nestjs/common");
const ai_voice_controller_1 = require("./ai-voice.controller");
const ai_voice_service_1 = require("./ai-voice.service");
const kinship_module_1 = require("../kinship/kinship.module");
let AiVoiceModule = class AiVoiceModule {
};
exports.AiVoiceModule = AiVoiceModule;
exports.AiVoiceModule = AiVoiceModule = __decorate([
    (0, common_1.Module)({
        imports: [kinship_module_1.KinshipModule],
        controllers: [ai_voice_controller_1.AiVoiceController],
        providers: [ai_voice_service_1.AiVoiceService],
        exports: [ai_voice_service_1.AiVoiceService],
    })
], AiVoiceModule);
//# sourceMappingURL=ai-voice.module.js.map