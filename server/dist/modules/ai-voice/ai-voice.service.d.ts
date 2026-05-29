import { KinshipService } from '../kinship/kinship.service';
export interface VoiceResultItem {
    term: string;
    englishTerm: string;
    relationshipKey: string;
    confidence: number;
}
export interface TranscriptionResult {
    transcription: string;
    results: {
        results: VoiceResultItem[];
    };
}
export interface LookupResult {
    transcription: string;
    term: {
        relationshipKey: string;
        englishTerm: string;
        translations: Record<string, {
            native: string;
            latin: string;
        }>;
    } | null;
}
export declare class AiVoiceService {
    private readonly kinshipService;
    private readonly logger;
    constructor(kinshipService: KinshipService);
    transcribe(audio: string, language?: string): Promise<TranscriptionResult>;
    lookup(audio: string, language?: string): Promise<LookupResult>;
    private transcribeAudio;
    private fallbackTranscription;
    private looksLikeBase64Audio;
    private findKinshipTerms;
}
