import { Module } from '@nestjs/common';
import { AiVoiceController } from './ai-voice.controller';
import { AiVoiceService } from './ai-voice.service';
import { KinshipModule } from '../kinship/kinship.module';

@Module({
  imports: [KinshipModule],
  controllers: [AiVoiceController],
  providers: [AiVoiceService],
  exports: [AiVoiceService],
})
export class AiVoiceModule {}
