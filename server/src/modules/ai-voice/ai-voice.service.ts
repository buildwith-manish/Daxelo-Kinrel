import { Injectable, Logger } from '@nestjs/common';
import { KinshipService } from '../kinship/kinship.service';

// ── Types ────────────────────────────────────────────────────────────

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
    translations: Record<string, { native: string; latin: string }>;
  } | null;
}

@Injectable()
export class AiVoiceService {
  private readonly logger = new Logger(AiVoiceService.name);

  constructor(private readonly kinshipService: KinshipService) {}

  /**
   * Transcribe audio and find matching kinship terms.
   */
  async transcribe(
    audio: string,
    language: string = 'en',
  ): Promise<TranscriptionResult> {
    // Try ASR via SDK
    let transcription: string;
    try {
      transcription = await this.transcribeAudio(audio, language);
    } catch (error) {
      this.logger.warn(
        `ASR transcription failed, using fallback: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
      transcription = this.fallbackTranscription(audio, language);
    }

    // Find kinship terms in the transcription
    const results = this.findKinshipTerms(transcription);

    return {
      transcription,
      results: { results },
    };
  }

  /**
   * Lookup a kinship term from audio transcription.
   */
  async lookup(
    audio: string,
    language: string = 'en',
  ): Promise<LookupResult> {
    // Try ASR via SDK
    let transcription: string;
    try {
      transcription = await this.transcribeAudio(audio, language);
    } catch (error) {
      this.logger.warn(
        `ASR transcription failed for lookup, using fallback: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
      transcription = this.fallbackTranscription(audio, language);
    }

    // Find the best matching kinship term
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

  // ── Private Helpers ────────────────────────────────────────────────

  private async transcribeAudio(
    audio: string,
    language: string,
  ): Promise<string> {
    const ZAI = (await import('z-ai-web-dev-sdk')).default;
    const sdk = await ZAI.create();

    const response = await sdk.audio.asr.create({
      file_base64: audio,
    });

    if (response?.text) {
      return response.text;
    }

    throw new Error('No transcription in ASR response');
  }

  /**
   * Fallback transcription — attempts to decode common patterns.
   * In production, the ASR service should handle this.
   */
  private fallbackTranscription(audio: string, language: string): string {
    // If the audio string looks like plain text (for testing), return it
    if (!this.looksLikeBase64Audio(audio)) {
      return audio;
    }

    // For real base64 audio, we can't transcribe without ASR
    return '[Transcription unavailable — ASR service not configured]';
  }

  private looksLikeBase64Audio(text: string): boolean {
    // Simple heuristic: base64 audio strings are long and don't contain spaces
    return text.length > 100 && !text.includes(' ');
  }

  /**
   * Find kinship terms in a transcription string.
   */
  private findKinshipTerms(transcription: string): VoiceResultItem[] {
    const matches = this.kinshipService.findByNativeTerm(transcription);

    return matches.slice(0, 5).map((match) => ({
      term: match.aliases?.[0] || match.englishTerm.toLowerCase(),
      englishTerm: match.englishTerm,
      relationshipKey: match.relationshipKey,
      confidence: match.confidence,
    }));
  }
}
