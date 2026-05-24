import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { KinshipService } from '../kinship/kinship.service';
import ZAI from 'z-ai-web-dev-sdk';

@Injectable()
export class AiVoiceService {
  private readonly logger = new Logger(AiVoiceService.name);
  private zai: ZAI | null = null;
  private initializationPromise: Promise<void> | null = null;

  constructor(private readonly kinshipService: KinshipService) {
    this.initializationPromise = this.initializeZai();
  }

  private async initializeZai(): Promise<void> {
    try {
      this.zai = await ZAI.create();
      this.logger.log('ZAI SDK initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize ZAI SDK', error);
      throw error;
    }
  }

  private async ensureInitialized(): Promise<void> {
    if (this.zai) return;
    if (this.initializationPromise) {
      await this.initializationPromise;
      return;
    }
    this.initializationPromise = this.initializeZai();
    await this.initializationPromise;
  }

  /**
   * Transcribe base64 audio to text and search kinship data.
   */
  async transcribeAndSearch(base64Audio: string, language?: string) {
    await this.ensureInitialized();
    // Step 1: Transcribe audio using ASR
    let transcription: string;
    try {
      const asrResult = await this.zai!.audio.asr.create({
        file_base64: base64Audio,
      });
      transcription = asrResult.text;
    } catch (error) {
      this.logger.error('ASR transcription failed', error);
      throw new BadRequestException('Failed to transcribe audio. Please try again.');
    }

    if (!transcription || transcription.trim().length === 0) {
      throw new BadRequestException('No speech detected in the audio. Please try again.');
    }

    this.logger.log(`Transcribed: "${transcription}"`);

    // Step 2: Search kinship data using the transcribed text
    const results = this.kinshipService.searchKinship(transcription.trim());

    return {
      transcription,
      results,
    };
  }

  /**
   * Transcribe base64 audio and perform an exact kinship lookup.
   */
  async quickLookup(base64Audio: string, language: string) {
    await this.ensureInitialized();
    // Step 1: Transcribe audio using ASR
    let transcription: string;
    try {
      const asrResult = await this.zai!.audio.asr.create({
        file_base64: base64Audio,
      });
      transcription = asrResult.text;
    } catch (error) {
      this.logger.error('ASR transcription failed', error);
      throw new BadRequestException('Failed to transcribe audio. Please try again.');
    }

    if (!transcription || transcription.trim().length === 0) {
      throw new BadRequestException('No speech detected in the audio. Please try again.');
    }

    this.logger.log(`Quick lookup transcribed: "${transcription}"`);

    // Step 2: Normalize the transcribed text for kinship lookup
    const normalizedText = transcription
      .trim()
      .toLowerCase()
      .replace(/\s+/g, '_');

    // Step 3: Try exact match using KinshipService
    const term = this.kinshipService.lookupKey(normalizedText, language);

    return {
      transcription,
      term,
    };
  }
}
