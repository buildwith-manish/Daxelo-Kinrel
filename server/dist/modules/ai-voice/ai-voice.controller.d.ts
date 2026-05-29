import { AiVoiceService } from './ai-voice.service';
import { TranscribeDto, VoiceLookupDto } from './dto/voice.dto';
export declare class AiVoiceController {
    private readonly aiVoiceService;
    constructor(aiVoiceService: AiVoiceService);
    transcribe(dto: TranscribeDto): Promise<import("./ai-voice.service").TranscriptionResult>;
    lookup(dto: VoiceLookupDto): Promise<import("./ai-voice.service").LookupResult>;
}
