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
var GamificationService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.GamificationService = void 0;
const common_1 = require("@nestjs/common");
const kinship_service_1 = require("../kinship/kinship.service");
let GamificationService = GamificationService_1 = class GamificationService {
    constructor(kinshipService) {
        this.kinshipService = kinshipService;
        this.logger = new common_1.Logger(GamificationService_1.name);
        this.quizSessions = new Map();
        this.leaderboard = new Map();
    }
    async createQuiz(dto) {
        const { category = 'kinship_basic', language, count, difficulty = 'medium', } = dto;
        const quizId = `quiz_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
        const questions = this.generateQuestions(category, language, count, difficulty);
        const session = {
            quizId,
            questions,
            totalQuestions: questions.length,
            category,
            difficulty,
            language,
            createdAt: new Date(),
        };
        this.quizSessions.set(quizId, session);
        return session;
    }
    submitQuiz(quizId, answers, userId, userName) {
        const session = this.quizSessions.get(quizId);
        if (!session) {
            throw new common_1.NotFoundException(`Quiz session ${quizId} not found`);
        }
        let correctAnswers = 0;
        const details = session.questions.map((q, i) => {
            const userAnswer = answers[i] ?? -1;
            const correct = userAnswer === q.correctIndex;
            if (correct)
                correctAnswers++;
            return {
                questionId: q.id,
                correct,
                correctIndex: q.correctIndex,
                userAnswer,
            };
        });
        const score = Math.round((correctAnswers / session.totalQuestions) * 100);
        this.updateLeaderboard(userId, userName, score);
        this.quizSessions.delete(quizId);
        return {
            score,
            totalQuestions: session.totalQuestions,
            correctAnswers,
            details,
        };
    }
    getLeaderboard() {
        const entries = [...this.leaderboard.values()].sort((a, b) => b.score - a.score);
        return entries.map((entry, index) => ({
            ...entry,
            rank: index + 1,
        }));
    }
    getDailyChallenge() {
        const today = new Date().toISOString().split('T')[0];
        const seed = this.dateSeed(today);
        const allTerms = this.kinshipService.getAllTerms();
        const termIndex = seed % allTerms.length;
        const term = allTerms[termIndex];
        const question = this.generateQuestionFromTerm(term, 'en', 'medium');
        return {
            date: today,
            type: 'kinship_translation',
            question,
            hint: `This term is in the "${term.relationshipCategory}" category`,
            streakBonus: seed % 3 === 0 ? 10 : 5,
        };
    }
    generateQuestions(category, language, count, difficulty) {
        const questions = [];
        switch (category) {
            case 'kinship_basic':
                return this.generateKinshipBasicQuestions(language, count, difficulty);
            case 'kinship_advanced':
                return this.generateKinshipAdvancedQuestions(language, count, difficulty);
            case 'family_traditions':
                return this.generateFamilyTraditionsQuestions(language, count, difficulty);
            case 'languages':
                return this.generateLanguageQuestions(language, count, difficulty);
            default:
                return this.generateKinshipBasicQuestions(language, count, difficulty);
        }
    }
    generateKinshipBasicQuestions(language, count, difficulty) {
        const terms = this.kinshipService.getRandomTerms(count * 3, 'immediate_family');
        const questions = [];
        for (let i = 0; i < count && i < terms.length; i++) {
            const term = terms[i];
            questions.push(this.generateQuestionFromTerm(term, language, difficulty));
        }
        return questions;
    }
    generateKinshipAdvancedQuestions(language, count, difficulty) {
        const terms = this.kinshipService.getRandomTerms(count * 3, 'extended_paternal');
        const maternalTerms = this.kinshipService.getRandomTerms(count * 3, 'extended_maternal');
        const allTerms = [...terms, ...maternalTerms].sort(() => Math.random() - 0.5);
        const questions = [];
        for (let i = 0; i < count && i < allTerms.length; i++) {
            questions.push(this.generateQuestionFromTerm(allTerms[i], language, difficulty));
        }
        return questions;
    }
    generateFamilyTraditionsQuestions(language, count, difficulty) {
        const traditionQuestions = [
            {
                id: 'ft_1',
                type: 'multiple_choice',
                question: 'During Raksha Bandhan, which relationship is primarily celebrated?',
                options: [
                    'Brother-Sister',
                    'Father-Daughter',
                    'Husband-Wife',
                    'Mother-Son',
                ],
                correctIndex: 0,
                explanation: 'Raksha Bandhan celebrates the bond between brothers and sisters. The sister ties a rakhi (sacred thread) on her brother\'s wrist.',
                kinshipData: {
                    relationships: ['brother', 'sister'],
                },
            },
            {
                id: 'ft_2',
                type: 'multiple_choice',
                question: 'In Indian tradition, "Kanyadaan" refers to the father giving away his daughter at wedding. What does "Kanya" mean?',
                options: ['Daughter', 'Bride', 'Girl', 'All of the above'],
                correctIndex: 3,
                explanation: '"Kanya" means girl/daughter/bride. Kanyadaan is considered one of the most sacred duties of a father in Hindu tradition.',
                kinshipData: {
                    relationships: ['father', 'daughter'],
                },
            },
            {
                id: 'ft_3',
                type: 'multiple_choice',
                question: 'What is "Grihapravesh" in Indian family tradition?',
                options: [
                    'First entry into a new home',
                    'Naming ceremony',
                    'Sacred thread ceremony',
                    'First harvest celebration',
                ],
                correctIndex: 0,
                explanation: 'Grihapravesh is the traditional Hindu ceremony performed when entering a new home for the first time.',
                kinshipData: {},
            },
            {
                id: 'ft_4',
                type: 'multiple_choice',
                question: 'In the "Pag Phera" tradition, the newly married couple visits which relative\'s home?',
                options: [
                    "Bride's parents' home",
                    "Groom's parents' home",
                    'Grandparents\' home',
                    'Uncle\'s home',
                ],
                correctIndex: 0,
                explanation: 'Pag Phera is the tradition where the newly married couple visits the bride\'s parents\' home after the wedding.',
                kinshipData: {
                    relationships: ['daughter_in_law', 'son_in_law'],
                },
            },
            {
                id: 'ft_5',
                type: 'multiple_choice',
                question: 'What is the significance of "Karva Chauth" in Indian tradition?',
                options: [
                    'Wives fast for their husbands\' well-being',
                    'Sisters pray for their brothers',
                    'Mothers bless their children',
                    'Fathers honor their ancestors',
                ],
                correctIndex: 0,
                explanation: 'Karva Chauth is a festival where married women fast from sunrise to moonrise for the safety and longevity of their husbands.',
                kinshipData: {
                    relationships: ['husband', 'wife'],
                },
            },
            {
                id: 'ft_6',
                type: 'multiple_choice',
                question: 'During "Bhai Dooj", which family relationship is celebrated?',
                options: [
                    'Brother-Sister',
                    'Father-Son',
                    'Mother-Daughter',
                    'Husband-Wife',
                ],
                correctIndex: 0,
                explanation: 'Bhai Dooj celebrates the bond between brothers and sisters, similar to Raksha Bandhan but observed during Diwali.',
                kinshipData: {
                    relationships: ['brother', 'sister'],
                },
            },
            {
                id: 'ft_7',
                type: 'multiple_choice',
                question: 'In the "Naamkaran" ceremony, what is determined?',
                options: [
                    'The name of a newborn child',
                    'The marriage date',
                    'The family gotra',
                    'The ancestral property division',
                ],
                correctIndex: 0,
                explanation: 'Naamkaran is the Hindu naming ceremony for a newborn, typically performed on the 12th day after birth.',
                kinshipData: {
                    relationships: ['son', 'daughter', 'father', 'mother'],
                },
            },
            {
                id: 'ft_8',
                type: 'multiple_choice',
                question: '"Mundan" ceremony in Indian tradition involves:',
                options: [
                    'First haircut of a child',
                    'Sacred thread ceremony',
                    'Engagement ceremony',
                    'House warming',
                ],
                correctIndex: 0,
                explanation: 'Mundan is the Hindu tonsure ceremony where a child\'s head is shaved for the first time, believed to cleanse the soul.',
                kinshipData: {},
            },
        ];
        const shuffled = traditionQuestions.sort(() => Math.random() - 0.5);
        return shuffled.slice(0, Math.min(count, shuffled.length));
    }
    generateLanguageQuestions(language, count, difficulty) {
        const terms = this.kinshipService.getRandomTerms(count * 3);
        const questions = [];
        const targetLang = language !== 'en' ? language : 'hi';
        for (let i = 0; i < count && i < terms.length; i++) {
            const term = terms[i];
            const translation = term.translations[targetLang];
            if (!translation)
                continue;
            const otherTerms = this.kinshipService
                .getRandomTerms(4)
                .filter((t) => t.relationshipKey !== term.relationshipKey);
            const wrongOptions = otherTerms
                .slice(0, 3)
                .map((t) => t.translations[targetLang]?.latin || t.englishTerm);
            const correctOption = translation.latin;
            const allOptions = [...wrongOptions, correctOption].sort(() => Math.random() - 0.5);
            const correctIndex = allOptions.indexOf(correctOption);
            questions.push({
                id: `lang_${Date.now()}_${i}`,
                type: 'translation',
                question: `What is the ${targetLang.toUpperCase()} term for "${term.englishTerm}"?`,
                options: allOptions,
                correctIndex,
                explanation: `"${term.englishTerm}" is called "${translation.native}" (${translation.latin}) in ${targetLang.toUpperCase()}.`,
                kinshipData: {
                    relationshipKey: term.relationshipKey,
                    englishTerm: term.englishTerm,
                    translations: { [targetLang]: translation },
                },
            });
        }
        return questions;
    }
    generateQuestionFromTerm(term, language, difficulty) {
        const targetLang = language !== 'en' ? language : 'hi';
        const translation = term.translations[targetLang];
        const otherTerms = this.kinshipService
            .getRandomTerms(5)
            .filter((t) => t.relationshipKey !== term.relationshipKey);
        if (difficulty === 'easy' || !translation) {
            const correctOption = term.englishTerm;
            const wrongOptions = otherTerms.slice(0, 3).map((t) => t.englishTerm);
            const allOptions = [...wrongOptions, correctOption].sort(() => Math.random() - 0.5);
            const correctIndex = allOptions.indexOf(correctOption);
            return {
                id: `q_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
                type: 'kinship_term',
                question: `What is the English term for "${term.relationshipKey.replace(/_/g, ' ')}"?`,
                options: allOptions,
                correctIndex,
                explanation: `"${term.relationshipKey.replace(/_/g, ' ')}" means "${term.englishTerm}" in English.`,
                kinshipData: {
                    relationshipKey: term.relationshipKey,
                    englishTerm: term.englishTerm,
                    gender: term.gender,
                    lineage: term.lineage,
                },
            };
        }
        const correctOption = translation.latin;
        const wrongOptions = otherTerms
            .slice(0, 3)
            .map((t) => t.translations[targetLang]?.latin || t.englishTerm);
        const allOptions = [...wrongOptions, correctOption].sort(() => Math.random() - 0.5);
        const correctIndex = allOptions.indexOf(correctOption);
        const questionText = difficulty === 'hard'
            ? `In ${targetLang.toUpperCase()}, what is "${term.englishTerm}" called?`
            : `What is the ${targetLang.toUpperCase()} word for "${term.englishTerm}"?`;
        return {
            id: `q_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
            type: 'kinship_translation',
            question: questionText,
            options: allOptions,
            correctIndex,
            explanation: `"${term.englishTerm}" is called "${translation.native}" (${translation.latin}) in ${targetLang.toUpperCase()}. Category: ${term.relationshipCategory.replace(/_/g, ' ')}.`,
            kinshipData: {
                relationshipKey: term.relationshipKey,
                englishTerm: term.englishTerm,
                gender: term.gender,
                lineage: term.lineage,
                translations: { [targetLang]: translation },
            },
        };
    }
    updateLeaderboard(userId, name, score) {
        const existing = this.leaderboard.get(userId);
        if (existing) {
            existing.score = Math.max(existing.score, score);
            existing.quizzesCompleted += 1;
        }
        else {
            this.leaderboard.set(userId, {
                userId,
                name,
                score,
                quizzesCompleted: 1,
                rank: 0,
            });
        }
    }
    dateSeed(dateString) {
        let hash = 0;
        for (let i = 0; i < dateString.length; i++) {
            const char = dateString.charCodeAt(i);
            hash = (hash << 5) - hash + char;
            hash = hash & hash;
        }
        return Math.abs(hash);
    }
};
exports.GamificationService = GamificationService;
exports.GamificationService = GamificationService = GamificationService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [kinship_service_1.KinshipService])
], GamificationService);
//# sourceMappingURL=gamification.service.js.map