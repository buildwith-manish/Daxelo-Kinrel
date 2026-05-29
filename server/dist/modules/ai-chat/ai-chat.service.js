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
var AiChatService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AiChatService = void 0;
const common_1 = require("@nestjs/common");
const kinship_service_1 = require("../kinship/kinship.service");
const SUGGESTION_TEMPLATES = [
    'What do I call my father\'s elder brother in Hindi?',
    'How is "chacha" related to me?',
    'What is the Tamil word for grandmother?',
    'Explain the difference between bua and mausi',
    'What do I call my wife\'s brother in Bengali?',
    'How do I address my mother\'s sister in Marathi?',
    'What is the Kannada word for father-in-law?',
    'Tell me about the Gujarati term for daughter-in-law',
    'What does "devar" mean in Indian kinship?',
    'How do I refer to my husband\'s sister in Telugu?',
    'What is "nana" in Indian family relationships?',
    'Explain "bhabhi" relationship in Indian culture',
];
let AiChatService = AiChatService_1 = class AiChatService {
    constructor(kinshipService) {
        this.kinshipService = kinshipService;
        this.logger = new common_1.Logger(AiChatService_1.name);
        this.sessions = new Map();
    }
    getSuggestions() {
        const shuffled = [...SUGGESTION_TEMPLATES].sort(() => Math.random() - 0.5);
        return shuffled.slice(0, 6);
    }
    async chat(userId, dto) {
        const { sessionId, message } = dto;
        let session;
        if (sessionId && this.sessions.has(sessionId)) {
            session = this.sessions.get(sessionId);
            session.messages.push({ role: 'user', content: message });
            session.updatedAt = new Date();
        }
        else {
            session = {
                id: sessionId || this.generateSessionId(),
                userId,
                messages: [
                    {
                        role: 'system',
                        content: 'You are a helpful assistant that specializes in Indian kinship relationships and family terminology. ' +
                            'You help users understand how to address family members in different Indian languages and cultures. ' +
                            'Provide clear, respectful, and culturally accurate information about Indian family relationships. ' +
                            'When discussing kinship terms, always include the relationship in English and at least one Indian language translation.',
                    },
                    { role: 'user', content: message },
                ],
                createdAt: new Date(),
                updatedAt: new Date(),
            };
        }
        let aiResponse;
        try {
            aiResponse = await this.generateLlmResponse(session.messages);
        }
        catch (error) {
            this.logger.warn(`LLM generation failed, falling back to built-in responses: ${error instanceof Error ? error.message : 'Unknown error'}`);
            aiResponse = this.generateFallbackResponse(message);
        }
        const kinshipData = this.extractKinshipData(message, aiResponse);
        session.messages.push({ role: 'assistant', content: aiResponse });
        this.sessions.set(session.id, session);
        return {
            response: aiResponse,
            kinshipData,
        };
    }
    deleteSession(sessionId, userId) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            return { success: true };
        }
        if (session.userId !== userId) {
            return { success: false };
        }
        this.sessions.delete(sessionId);
        return { success: true };
    }
    async generateLlmResponse(messages) {
        const ZAI = (await Promise.resolve().then(() => __importStar(require('z-ai-web-dev-sdk')))).default;
        const sdk = await ZAI.create();
        const response = await sdk.chat.completions.create({
            messages: messages.map((m) => ({
                role: m.role,
                content: m.content,
            })),
            model: 'deepseek-chat',
        });
        if (response?.choices?.[0]?.message?.content) {
            return response.choices[0].message.content;
        }
        throw new Error('No content in LLM response');
    }
    generateFallbackResponse(message) {
        const lowerMessage = message.toLowerCase().trim();
        const results = this.kinshipService.search(message);
        if (results.length === 0) {
            return ("I'm not sure about that specific kinship term. Could you try rephrasing your question? " +
                "For example, you could ask 'What do I call my father's brother?' or 'What does chacha mean?'");
        }
        const topResults = results.slice(0, 3);
        const parts = topResults.map((term) => {
            const translations = Object.entries(term.translations)
                .map(([lang, t]) => `${lang.toUpperCase()}: ${t.native} (${t.latin})`)
                .join(', ');
            return (`**${term.englishTerm}** (${term.relationshipKey}):\n` +
                `Gender: ${term.gender}, Lineage: ${term.lineage}, Category: ${term.relationshipCategory}\n` +
                `Translations: ${translations}`);
        });
        let response = `Here's what I found about Indian kinship terms related to your question:\n\n${parts.join('\n\n')}`;
        if (topResults.length > 1) {
            response +=
                '\n\nThese are the most relevant terms. Would you like to know more about any specific one?';
        }
        return response;
    }
    extractKinshipData(message, _response) {
        const results = this.kinshipService.search(message);
        return results.slice(0, 5).map((term) => ({
            relationshipKey: term.relationshipKey,
            englishTerm: term.englishTerm,
            gender: term.gender,
            lineage: term.lineage,
            relationshipCategory: term.relationshipCategory,
            translations: term.translations,
        }));
    }
    generateSessionId() {
        return `chat_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    }
};
exports.AiChatService = AiChatService;
exports.AiChatService = AiChatService = AiChatService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [kinship_service_1.KinshipService])
], AiChatService);
//# sourceMappingURL=ai-chat.service.js.map