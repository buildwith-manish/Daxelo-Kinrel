"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var AiVoiceService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AiVoiceService = void 0;
const common_1 = require("@nestjs/common");
const kinship_service_1 = require("../kinship/kinship.service");
let AiVoiceService = AiVoiceService_1 = class AiVoiceService {
    constructor(kinshipService) {
        this.kinshipService = kinshipService;
        this.logger = new common_1.Logger(AiVoiceService_1.name);
    }
    async transcribe(audio, language = 'en') {
        let transcription;
        try {
            transcription = await this.transcribeAudio(audio, language);
        }
        catch (error) {
            this.logger.warn(`ASR transcription failed, using fallback: ${error instanceof Error ? error.message : 'Unknown error'}`);
            transcription = this.fallbackTranscription(audio, language);
        }
        const results = this.findKinshipTerms(transcription);
        return {
            transcription,
            results: { results },
        };
    }
    async lookup(audio, language = 'en') {
        let transcription;
        try {
            transcription = await this.transcribeAudio(audio, language);
        }
        catch (error) {
            this.logger.warn(`ASR transcription failed for lookup, using fallback: ${error instanceof Error ? error.message : 'Unknown error'}`);
            transcription = this.fallbackTranscription(audio, language);
        }
        const matches = this.kinshipService.findByNativeTerm(transcription);
        if (matches.length === 0) {
            return {
                transcription,
                term: null,
            };
        }
        const bestMatch = matches[0];
        return {
            transcription,
            term: {
                relationshipKey: bestMatch.relationshipKey,
                englishTerm: bestMatch.englishTerm,
                translations: bestMatch.translations,
            },
        };
    }
    async transcribeAudio(audio, language) {
        const ZAI = (await Promise.resolve().then(() => __importStar(require('z-ai-web-dev-sdk')))).default;
        const sdk = await ZAI.create();
        const response = await sdk.audio.asr.create({
            file_base64: audio,
        });
        if (response?.text) {
            return response.text;
        }
        throw new Error('No transcription in ASR response');
    }
    fallbackTranscription(audio, language) {
        if (!this.looksLikeBase64Audio(audio)) {
            return audio;
        }
        return '[Transcription unavailable — ASR service not configured]';
    }
    looksLikeBase64Audio(text) {
        return text.length > 100 && !text.includes(' ');
    }
    findKinshipTerms(transcription) {
        const matches = this.kinshipService.findByNativeTerm(transcription);
        return matches.slice(0, 5).map((match) => ({
            term: match.aliases?.[0] || match.englishTerm.toLowerCase(),
            englishTerm: match.englishTerm,
            relationshipKey: match.relationshipKey,
            confidence: match.confidence,
        }));
    }
};
exports.AiVoiceService = AiVoiceService;
exports.AiVoiceService = AiVoiceService = AiVoiceService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [kinship_service_1.KinshipService])
], AiVoiceService);
//# sourceMappingURL=ai-voice.service.js.map