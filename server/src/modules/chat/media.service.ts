import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

/**
 * MediaService — handles chat media uploads (images, voice notes, videos)
 * to Supabase Storage.
 *
 * Bucket structure:
 *   chat-media/
 *     images/<familyId>/<messageId>.<ext>
 *     voice/<familyId>/<messageId>.m4a
 *     videos/<familyId>/<messageId>.mp4
 *
 * Validation:
 *   • Max file size: 25 MB (images/videos), 5 MB (voice notes)
 *   • Allowed MIME types: image/jpeg, image/png, image/webp, image/gif,
 *     audio/aac, audio/m4a, audio/mp4, audio/mpeg, video/mp4, video/webm
 *
 * The uploaded file's public URL is returned so the ChatService can store
 * it in ChatMessage.mediaUrl. Voice notes also store voiceMessageDuration
 * + durationSeconds.
 *
 * NOTE: The 'chat-media' bucket must exist in Supabase Storage with public
 * read access. If it doesn't exist, the upload fails with a clear error
 * message telling the operator to create it.
 */
@Injectable()
export class MediaService {
  private readonly logger = new Logger(MediaService.name);
  private supabase: SupabaseClient | null = null;

  /// Max file sizes (in bytes).
  private readonly MAX_IMAGE_SIZE = 25 * 1024 * 1024; // 25 MB
  private readonly MAX_VIDEO_SIZE = 25 * 1024 * 1024; // 25 MB
  private readonly MAX_VOICE_SIZE = 5 * 1024 * 1024; // 5 MB

  /// Allowed MIME types per media type.
  private readonly ALLOWED_MIME: Record<string, string[]> = {
    image: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
    voice: ['audio/aac', 'audio/m4a', 'audio/mp4', 'audio/mpeg', 'audio/x-m4a'],
    video: ['video/mp4', 'video/webm'],
  };

  /// Bucket name in Supabase Storage.
  private readonly BUCKET = 'chat-media';

  constructor(private readonly configService: ConfigService) {
    const supabaseUrl = this.configService.get<string>('SUPABASE_URL');
    const serviceRoleKey = this.configService.get<string>('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      this.logger.verbose(
        'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set — MediaService uploads disabled. ' +
          'Chat media will fall back to base64-inline rendering (not recommended for production).',
      );
      return;
    }

    try {
      this.supabase = createClient(supabaseUrl, serviceRoleKey);
      this.logger.log('✅ MediaService Supabase Storage client initialized');
    } catch (err: any) {
      this.logger.error(`Failed to init Supabase Storage client: ${err?.message}`);
    }
  }

  /// Returns true if the service is ready to accept uploads.
  isAvailable(): boolean {
    return this.supabase !== null;
  }

  /// Validate the upload request before hitting Supabase Storage.
  /// Throws BadRequestException on invalid input.
  private validate(
    mediaType: string,
    mimeType: string,
    fileSize: number,
  ): { maxSize: number; folder: string; ext: string } {
    const allowed = this.ALLOWED_MIME[mediaType];
    if (!allowed) {
      throw new BadRequestException(
        `Invalid mediaType '${mediaType}'. Must be one of: image, voice, video`,
      );
    }
    if (!allowed.includes(mimeType)) {
      throw new BadRequestException(
        `MIME type '${mimeType}' not allowed for ${mediaType}. Allowed: ${allowed.join(', ')}`,
      );
    }

    let maxSize: number;
    let folder: string;
    let ext: string;
    if (mediaType === 'image') {
      maxSize = this.MAX_IMAGE_SIZE;
      folder = 'images';
      ext = mimeType.split('/')[1]; // jpeg, png, webp, gif
    } else if (mediaType === 'voice') {
      maxSize = this.MAX_VOICE_SIZE;
      folder = 'voice';
      ext = mimeType === 'audio/mpeg' ? 'mp3' : 'm4a';
    } else {
      maxSize = this.MAX_VIDEO_SIZE;
      folder = 'videos';
      ext = mimeType.split('/')[1]; // mp4, webm
    }

    if (fileSize > maxSize) {
      const maxMB = Math.round(maxSize / (1024 * 1024));
      const fileMB = (fileSize / (1024 * 1024)).toFixed(2);
      throw new BadRequestException(
        `File too large: ${fileMB} MB (max for ${mediaType}: ${maxMB} MB)`,
      );
    }

    return { maxSize, folder, ext };
  }

  /// Upload a media file to Supabase Storage.
  ///
  /// [buffer] — the file bytes.
  /// [mediaType] — 'image' | 'voice' | 'video'.
  /// [mimeType] — e.g. 'image/jpeg', 'audio/m4a'.
  /// [familyId] — used in the storage path for per-family organization.
  /// [messageId] — used as the filename (unique per message).
  /// [durationSeconds] — required for voice/video (null for images).
  ///
  /// Returns the public URL of the uploaded file, which the caller stores
  /// in ChatMessage.mediaUrl.
  async uploadMedia(params: {
    buffer: Buffer;
    mediaType: string;
    mimeType: string;
    familyId: string;
    messageId: string;
    durationSeconds?: number | null;
  }): Promise<{
    url: string;
    mediaType: string;
    mimeType: string;
    size: number;
    durationSeconds: number | null;
  }> {
    if (!this.supabase) {
      throw new BadRequestException(
        'Media upload unavailable — SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not configured',
      );
    }

    const { buffer, mediaType, mimeType, familyId, messageId } = params;
    const { folder, ext } = this.validate(mediaType, mimeType, buffer.length);

    const path = `${folder}/${familyId}/${messageId}.${ext}`;

    // Upload to Supabase Storage.
    const { data, error } = await this.supabase.storage
      .from(this.BUCKET)
      .upload(path, buffer, {
        contentType: mimeType,
        cacheControl: '3600', // 1 hour CDN cache
        upsert: true, // overwrite if exists (idempotent for retries)
      });

    if (error) {
      this.logger.error(`Supabase Storage upload failed: ${error.message}`);
      if (error.message?.includes('Bucket not found')) {
        throw new BadRequestException(
          `Storage bucket '${this.BUCKET}' does not exist. Create it in Supabase Dashboard → Storage.`,
        );
      }
      throw new BadRequestException(`Upload failed: ${error.message}`);
    }

    // Get the public URL.
    const { data: urlData } = this.supabase.storage
      .from(this.BUCKET)
      .getPublicUrl(path);

    const url = urlData.publicUrl;
    this.logger.debug(
      `Uploaded ${mediaType} (${buffer.length} bytes) → ${url}`,
    );

    return {
      url,
      mediaType,
      mimeType,
      size: buffer.length,
      durationSeconds: params.durationSeconds ?? null,
    };
  }

  /// Delete a media file (e.g. when a message is deleted for everyone).
  /// Best-effort — failure is logged but doesn't fail the message delete.
  async deleteMedia(url: string): Promise<void> {
    if (!this.supabase) return;
    try {
      // Extract the path from the public URL.
      // URL format: https://<project>.supabase.co/storage/v1/object/public/chat-media/<path>
      const match = url.match(/\/chat-media\/(.+)$/);
      if (!match) return;
      const path = match[1];
      await this.supabase.storage.from(this.BUCKET).remove([path]);
      this.logger.debug(`Deleted media at ${path}`);
    } catch (err: any) {
      this.logger.warn(`Failed to delete media ${url}: ${err?.message}`);
    }
  }
}
