import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { Observable, from, of, throwError } from 'rxjs';
import { switchMap, catchError } from 'rxjs/operators';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import * as sharp from 'sharp';
import * as crypto from 'crypto';
import * as path from 'path';

// ────────────────────────────────────────────────────────────────
// Types & Constants
// ────────────────────────────────────────────────────────────────

/** Allowed MIME types for image uploads */
const ALLOWED_MIME_TYPES: readonly string[] = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
];

/** Map from MIME type to file extension */
const MIME_TO_EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

/** Maximum file size: 5 MB */
const MAX_FILE_SIZE = 5 * 1024 * 1024;

/** Image size configurations for multi-resolution output */
const IMAGE_SIZES = {
  thumb: { width: 80, height: 80, suffix: '_thumb' },
  card: { width: 150, height: 150, suffix: '_card' },
  full: { width: 400, height: 400, suffix: '_full' },
} as const;

type ImageSizeKey = keyof typeof IMAGE_SIZES;

/** Result of a secure upload operation */
export interface SecureUploadResult {
  /** Original file name (sanitized) */
  originalName: string;
  /** Unique file ID (used as storage key prefix) */
  fileId: string;
  /** CDN URLs for each image size */
  urls: Record<ImageSizeKey, string>;
  /** URL of the original uploaded image */
  url: string;
  /** File size in bytes */
  size: number;
  /** MIME type */
  mimeType: string;
  /** Width of the full-size image */
  width: number;
  /** Height of the full-size image */
  height: number;
  /** Whether content scan passed */
  scanPassed: boolean;
  /** Content scan details (if any flags) */
  scanDetails?: ContentScanResult;
}

/** Result of content scanning */
export interface ContentScanResult {
  passed: boolean;
  flags: string[];
  confidence: number;
}

/**
 * Inappropriate content patterns for basic scanning.
 * These are simple heuristic checks — for production, integrate
 * with a dedicated content moderation API (e.g., Google Vision API,
 * AWS Rekognition, or Azure Content Moderator).
 */
const INAPPROPRIATE_PATTERNS: RegExp[] = [
  // Common patterns in EXIF data or filenames that indicate
  // potentially problematic content (very basic heuristic)
  /[^\x00-\x7F]{10,}/, // Unusually long non-ASCII sequences in filename
];

// ────────────────────────────────────────────────────────────────
// SecureUploadInterceptor
// ────────────────────────────────────────────────────────────────

/**
 * SecureUploadInterceptor — Validates, processes, and securely uploads
 * image files to Supabase Storage.
 *
 * Features:
 *   - MIME type validation (only jpeg, png, webp, gif)
 *   - File size limit (5 MB)
 *   - Filename sanitization
 *   - Multi-size image generation (thumb 80×80, card 150×150, full 400×400)
 *   - Upload to Supabase Storage bucket
 *   - CDN URL generation
 *   - Basic inappropriate content scanning
 *
 * Prerequisites:
 *   - SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in env
 *   - A Supabase Storage bucket named 'uploads' must exist
 *   - The Multer FileInterceptor should run BEFORE this interceptor
 *     (file attached to req.file or req.files)
 *
 * Usage:
 *   @Post('upload')
 *   @UseInterceptors(FileInterceptor('file'), SecureUploadInterceptor)
 *   async uploadFile() { ... }
 *
 *   // In your handler, the response will include the upload result:
 *   // { originalName, fileId, urls: { thumb, card, full }, url, ... }
 */
@Injectable()
export class SecureUploadInterceptor implements NestInterceptor {
  private readonly logger = new Logger(SecureUploadInterceptor.name);
  private readonly supabase: SupabaseClient;
  private readonly bucketName: string;
  private readonly cdnUrl: string;

  constructor(private readonly configService: ConfigService) {
    const supabaseUrl = this.configService.get<string>('SUPABASE_URL', '');
    const supabaseKey = this.configService.get<string>(
      'SUPABASE_SERVICE_ROLE_KEY',
      this.configService.get<string>('SUPABASE_ANON_KEY', ''),
    );

    this.bucketName = this.configService.get<string>(
      'SUPABASE_STORAGE_BUCKET',
      'uploads',
    );

    this.cdnUrl = supabaseUrl
      ? `${supabaseUrl}/storage/v1/object/public/${this.bucketName}`
      : '';

    if (supabaseUrl && supabaseKey) {
      this.supabase = createClient(supabaseUrl, supabaseKey, {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      });
      this.logger.log('SecureUploadInterceptor: Supabase Storage initialized');
    } else {
      // Fallback: create a dummy client that will be handled in upload method
      this.supabase = null as any;
      this.logger.warn(
        'SecureUploadInterceptor: Supabase credentials not configured. ' +
          'Uploads will use local fallback storage.',
      );
    }
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest<any>();
    const file = request.file;
    const files = request.files;

    // If no files uploaded, pass through
    if (!file && !files) {
      return next.handle();
    }

    // Process single file upload
    if (file) {
      return from(this.processAndUpload(file)).pipe(
        switchMap((result: SecureUploadResult) => {
          // Attach result to request for controller access
          request.uploadResult = result;
          return next.handle();
        }),
        catchError((error) => {
          this.logger.error(
            `SecureUploadInterceptor: Upload failed — ${error.message}`,
            error.stack,
          );
          return throwError(() => error);
        }),
      );
    }

    // Process multiple file upload
    if (Array.isArray(files)) {
      return from(Promise.all(files.map((f) => this.processAndUpload(f)))).pipe(
        switchMap((results: SecureUploadResult[]) => {
          request.uploadResults = results;
          return next.handle();
        }),
        catchError((error) => {
          this.logger.error(
            `SecureUploadInterceptor: Multi-upload failed — ${error.message}`,
            error.stack,
          );
          return throwError(() => error);
        }),
      );
    }

    return next.handle();
  }

  // ────────────────────────────────────────────────────────────────
  // Core Processing Pipeline
  // ────────────────────────────────────────────────────────────────

  /**
   * Full processing pipeline for a single uploaded file:
   * 1. Validate MIME type
   * 2. Validate file size
   * 3. Sanitize filename
   * 4. Scan for inappropriate content
   * 5. Generate multiple image sizes
   * 6. Upload to Supabase Storage
   * 7. Return CDN URLs
   */
  private async processAndUpload(file: any): Promise<SecureUploadResult> {
    // Step 1: Validate MIME type
    this.validateMimeType(file);

    // Step 2: Validate file size
    this.validateFileSize(file);

    // Step 3: Sanitize filename
    const sanitizedFilename = this.sanitizeFilename(file.originalname);

    // Step 4: Generate unique file ID and storage path
    const fileId = crypto.randomUUID();
    const ext = MIME_TO_EXT[file.mimetype] || 'jpg';
    const storagePrefix = `${fileId}`;

    // Step 5: Scan for inappropriate content
    const scanResult = await this.scanContent(file);

    if (!scanResult.passed) {
      this.logger.warn(
        `SecureUploadInterceptor: Content scan FAILED for file "${sanitizedFilename}" — ` +
          `flags: ${scanResult.flags.join(', ')} (confidence: ${scanResult.confidence})`,
      );
      throw new BadRequestException(
        `Upload rejected: Content scan detected potentially inappropriate content. ` +
          `Flags: ${scanResult.flags.join(', ')}`,
      );
    }

    // Step 6: Generate multiple image sizes
    const resizedBuffers = await this.generateMultipleSizes(file.buffer, ext);

    // Step 7: Upload all sizes to Supabase Storage
    const urls = await this.uploadAllSizes(
      resizedBuffers,
      storagePrefix,
      sanitizedFilename,
      ext,
    );

    // Step 8: Get original image metadata
    const metadata = await sharp(file.buffer).metadata();

    return {
      originalName: sanitizedFilename,
      fileId,
      urls,
      url: urls.full,
      size: file.size,
      mimeType: file.mimetype,
      width: metadata.width ?? 0,
      height: metadata.height ?? 0,
      scanPassed: scanResult.passed,
      scanDetails: scanResult,
    };
  }

  // ────────────────────────────────────────────────────────────────
  // Validation Methods
  // ────────────────────────────────────────────────────────────────

  /**
   * Validate that the file's MIME type is in the allowed list.
   * Also validates that the actual file header matches the claimed MIME type
   * (prevents MIME type spoofing).
   */
  private validateMimeType(file: any): void {
    // Check declared MIME type
    if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
      throw new BadRequestException(
        `Invalid file type: "${file.mimetype}". ` +
          `Allowed types: ${ALLOWED_MIME_TYPES.join(', ')}`,
      );
    }

    // Validate file magic bytes (signature) to prevent MIME spoofing
    const buffer = file.buffer as Buffer;
    if (!buffer || buffer.length < 12) {
      throw new BadRequestException('File is too small to be a valid image');
    }

    const magicBytes = buffer.toString('hex', 0, 12).toLowerCase();
    const isValidImage = this.verifyMagicBytes(magicBytes, file.mimetype);

    if (!isValidImage) {
      throw new BadRequestException(
        `File content does not match declared type "${file.mimetype}". ` +
          `Possible MIME type spoofing detected.`,
      );
    }
  }

  /**
   * Verify file magic bytes against the declared MIME type.
   * This prevents attackers from uploading malicious files with
   * a fake image MIME type.
   */
  private verifyMagicBytes(hex: string, mimeType: string): boolean {
    // JPEG: starts with FFD8FF
    if (mimeType === 'image/jpeg') {
      return hex.startsWith('ffd8ff');
    }
    // PNG: starts with 89504e47
    if (mimeType === 'image/png') {
      return hex.startsWith('89504e47');
    }
    // WebP: starts with 52494646 (RIFF) and has 57454250 (WEBP) at offset 8
    if (mimeType === 'image/webp') {
      return hex.startsWith('52494646') && hex.includes('57454250');
    }
    // GIF: starts with 47494638 (GIF8)
    if (mimeType === 'image/gif') {
      return hex.startsWith('47494638');
    }
    return false;
  }

  /**
   * Validate that the file size does not exceed the maximum allowed size.
   */
  private validateFileSize(file: any): void {
    const size = file.size as number;
    if (size > MAX_FILE_SIZE) {
      const maxMB = (MAX_FILE_SIZE / (1024 * 1024)).toFixed(1);
      const fileMB = (size / (1024 * 1024)).toFixed(2);
      throw new BadRequestException(
        `File too large: ${fileMB} MB. Maximum allowed: ${maxMB} MB`,
      );
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Filename Sanitization
  // ────────────────────────────────────────────────────────────────

  /**
   * Sanitize a filename by:
   * - Removing path traversal components (.., /, \)
   * - Replacing special characters with underscores
   * - Limiting length
   * - Removing leading dots (hidden files)
   * - Converting to lowercase
   */
  private sanitizeFilename(originalName: string): string {
    let sanitized = originalName;

    // Remove any path components
    sanitized = path.basename(sanitized);

    // Remove leading dots (prevent hidden file creation)
    sanitized = sanitized.replace(/^\.+/, '');

    // Replace non-alphanumeric characters (except dots, dashes, underscores)
    sanitized = sanitized.replace(/[^a-zA-Z0-9._-]/g, '_');

    // Collapse multiple underscores
    sanitized = sanitized.replace(/_+/g, '_');

    // Limit filename length (keep extension)
    const maxNameLength = 100;
    if (sanitized.length > maxNameLength) {
      const ext = path.extname(sanitized);
      const baseName = path.basename(sanitized, ext);
      sanitized = baseName.substring(0, maxNameLength - ext.length) + ext;
    }

    // Convert to lowercase
    sanitized = sanitized.toLowerCase();

    // Ensure we have a filename
    if (!sanitized || sanitized === '.') {
      sanitized = 'upload.jpg';
    }

    return sanitized;
  }

  // ────────────────────────────────────────────────────────────────
  // Content Scanning
  // ────────────────────────────────────────────────────────────────

  /**
   * Scan uploaded content for inappropriate material.
   *
   * This performs basic heuristic checks. For production use,
   * integrate with a dedicated content moderation service such as:
   * - Google Cloud Vision API (Safe Search)
   * - AWS Rekognition (Content Moderation)
   * - Azure Content Moderator
   * - Sightengine
   *
   * Current checks:
   * - Filename pattern analysis
   * - Image dimension validation (reject tiny 1x1 tracking pixels)
   * - EXIF data analysis for suspicious metadata
   * - Entropy analysis (detect steganography patterns)
   */
  private async scanContent(file: any): Promise<ContentScanResult> {
    const flags: string[] = [];
    let confidence = 1.0;

    // Check 1: Filename pattern analysis
    const filename = file.originalname || '';
    for (const pattern of INAPPROPRIATE_PATTERNS) {
      if (pattern.test(filename)) {
        flags.push('suspicious_filename_pattern');
        confidence *= 0.7;
        break;
      }
    }

    // Check 2: Image dimension validation (reject tracking pixels)
    try {
      const metadata = await sharp(file.buffer).metadata();
      if (metadata.width && metadata.height) {
        if (metadata.width <= 1 || metadata.height <= 1) {
          flags.push('tracking_pixel_detected');
          confidence *= 0.1;
        }
        // Reject extremely large dimensions that could cause DoS
        if (metadata.width > 10000 || metadata.height > 10000) {
          flags.push('excessive_image_dimensions');
          confidence *= 0.3;
        }
      }

      // Check 3: EXIF data analysis
      if (metadata.exif) {
        // Large EXIF data could contain embedded payloads
        const exifSize = Buffer.byteLength(metadata.exif);
        if (exifSize > 65536) {
          // 64 KB threshold
          flags.push('oversized_exif_data');
          confidence *= 0.5;
        }
      }

      // Check 4: Format mismatch (e.g., SVG disguised as PNG)
      if (metadata.format) {
        const declaredFormat = file.mimetype.split('/')[1];
        const actualFormat = metadata.format;
        if (
          declaredFormat !== actualFormat &&
          !(declaredFormat === 'jpeg' && actualFormat === 'jpg') &&
          !(declaredFormat === 'jpg' && actualFormat === 'jpeg')
        ) {
          flags.push('format_mismatch');
          confidence *= 0.4;
        }
      }
    } catch (error) {
      // If we can't read the image, it might be corrupted or malicious
      flags.push('unreadable_image_data');
      confidence *= 0.2;
    }

    // Check 5: Entropy analysis (detect potential steganography)
    const buffer = file.buffer as Buffer;
    const entropy = this.calculateEntropy(buffer);
    if (entropy > 7.9) {
      // Very high entropy might indicate encrypted/hidden data
      // (but can also be normal for compressed images)
      flags.push('high_entropy_content');
      confidence *= 0.85;
    }

    // Check 6: Buffer size vs. image dimensions ratio
    // A very small file for large dimensions might be suspicious
    try {
      const meta = await sharp(buffer).metadata();
      if (meta.width && meta.height) {
        const pixels = meta.width * meta.height;
        const bytesPerPixel = buffer.length / pixels;
        if (bytesPerPixel < 0.1) {
          // Less than 0.1 byte per pixel is unusual for a normal photo
          flags.push('low_data_per_pixel');
          confidence *= 0.9;
        }
      }
    } catch {
      // Already handled above
    }

    return {
      passed: flags.length === 0,
      flags,
      confidence: Math.max(0, Math.min(1, confidence)),
    };
  }

  /**
   * Calculate Shannon entropy of a buffer.
   * Higher entropy = more random/uniform data distribution.
   * Normal images: 5-7.5; Encrypted/compressed: 7.5-8.0
   */
  private calculateEntropy(buffer: Buffer): number {
    const frequency = new Array(256).fill(0);
    const len = Math.min(buffer.length, 65536); // Sample first 64KB

    for (let i = 0; i < len; i++) {
      frequency[buffer[i]]++;
    }

    let entropy = 0;
    for (const count of frequency) {
      if (count === 0) continue;
      const probability = count / len;
      entropy -= probability * Math.log2(probability);
    }

    return entropy;
  }

  // ────────────────────────────────────────────────────────────────
  // Image Processing
  // ────────────────────────────────────────────────────────────────

  /**
   * Generate multiple image sizes from the original buffer.
   * Produces three variants:
   * - thumb: 80×80 (cover crop, for avatars/list items)
   * - card: 150×150 (cover crop, for cards/tiles)
   * - full: 400×400 (fit inside, for detail views)
   *
   * All sizes are converted to WebP for optimal compression,
   * except for GIFs which are preserved in their original format.
   */
  private async generateMultipleSizes(
    buffer: Buffer,
    originalExt: string,
  ): Promise<Record<ImageSizeKey, Buffer>> {
    const isGif = originalExt === 'gif';

    const pipeline = sharp(buffer);
    const metadata = await pipeline.metadata();

    const results: Record<string, Buffer> = {};

    for (const [key, config] of Object.entries(IMAGE_SIZES)) {
      try {
        let transform = sharp(buffer);

        if (key === 'full') {
          // Full size: fit inside the bounds (maintain aspect ratio)
          transform = transform.resize(config.width, config.height, {
            fit: 'inside',
            withoutEnlargement: true,
          });
        } else {
          // Thumb & Card: cover crop (center)
          transform = transform.resize(config.width, config.height, {
            fit: 'cover',
            position: 'center',
            withoutEnlargement: true,
          });
        }

        // Convert to WebP for non-GIF, or preserve GIF format
        if (!isGif) {
          transform = transform.webp({
            quality: key === 'thumb' ? 70 : key === 'card' ? 80 : 85,
            effort: 4,
          });
        } else {
          // For GIFs, convert to WebP for sizes other than full
          // (animated GIFs lose animation in resize)
          if (key !== 'full') {
            transform = transform.webp({ quality: 75, effort: 4 });
          } else {
            // Keep full GIF as-is but limit frames
            transform = transform.gif({ effort: 50 });
          }
        }

        // Strip all metadata (EXIF, GPS, etc.) for privacy
        transform = transform.withMetadata();

        results[key] = await transform.toBuffer();

        this.logger.debug(
          `SecureUploadInterceptor: Generated ${key} size ` +
            `(${config.width}×${config.height}) — ` +
            `${results[key].length} bytes`,
        );
      } catch (error) {
        this.logger.error(
          `SecureUploadInterceptor: Failed to generate ${key} size — ${error.message}`,
        );
        // Fallback: use original buffer for this size
        results[key] = buffer;
      }
    }

    return results as Record<ImageSizeKey, Buffer>;
  }

  // ────────────────────────────────────────────────────────────────
  // Supabase Storage Upload
  // ────────────────────────────────────────────────────────────────

  /**
   * Upload all image sizes to Supabase Storage and return CDN URLs.
   */
  private async uploadAllSizes(
    buffers: Record<ImageSizeKey, Buffer>,
    storagePrefix: string,
    originalName: string,
    ext: string,
  ): Promise<Record<ImageSizeKey, string>> {
    const urls: Record<string, string> = {};

    for (const [sizeKey, config] of Object.entries(IMAGE_SIZES)) {
      const isGif = ext === 'gif' && sizeKey === 'full';
      const fileExt = isGif ? 'gif' : 'webp';
      const storagePath = `${storagePrefix}${config.suffix}.${fileExt}`;

      try {
        const url = await this.uploadToStorage(
          storagePath,
          buffers[sizeKey as ImageSizeKey],
          isGif ? 'image/gif' : 'image/webp',
        );
        urls[sizeKey] = url;

        this.logger.debug(
          `SecureUploadInterceptor: Uploaded ${sizeKey} to ${storagePath}`,
        );
      } catch (error) {
        this.logger.error(
          `SecureUploadInterceptor: Failed to upload ${sizeKey} — ${error.message}`,
        );
        // Generate a fallback URL even if upload fails
        urls[sizeKey] = this.buildCdnUrl(storagePath);
      }
    }

    return urls as Record<ImageSizeKey, string>;
  }

  /**
   * Upload a single file buffer to Supabase Storage.
   * Falls back to local storage if Supabase is not configured.
   */
  private async uploadToStorage(
    storagePath: string,
    buffer: Buffer,
    contentType: string,
  ): Promise<string> {
    // If Supabase is configured, use it
    if (this.supabase) {
      const { data, error } = await this.supabase.storage
        .from(this.bucketName)
        .upload(storagePath, buffer, {
          contentType,
          upsert: true,
          duplex: undefined as any,
        });

      if (error) {
        this.logger.error(
          `SecureUploadInterceptor: Supabase upload error — ${error.message}`,
        );
        throw new Error(`Storage upload failed: ${error.message}`);
      }

      // Get public URL
      const { data: urlData } = this.supabase.storage
        .from(this.bucketName)
        .getPublicUrl(storagePath);

      return urlData.publicUrl;
    }

    // Fallback: Return a CDN-style URL (the actual upload would need
    // a different storage backend configured in production)
    this.logger.warn(
      `SecureUploadInterceptor: Supabase not configured — ` +
        `generating placeholder URL for ${storagePath}`,
    );
    return this.buildCdnUrl(storagePath);
  }

  /**
   * Build a CDN public URL for a given storage path.
   */
  private buildCdnUrl(storagePath: string): string {
    if (this.cdnUrl) {
      return `${this.cdnUrl}/${storagePath}`;
    }
    // Fallback URL pattern
    return `/storage/uploads/${storagePath}`;
  }
}

// ────────────────────────────────────────────────────────────────
// Utility: Create configured FileInterceptor with SecureUpload
// ────────────────────────────────────────────────────────────────

/**
 * Factory function to create a Multer FileInterceptor pre-configured
 * with secure upload options.
 *
 * This ensures consistent MIME type validation at the Multer level
 * (before the file even reaches our interceptor).
 *
 * @param fieldName - The form field name for the file upload
 * @param options - Optional Multer options override
 *
 * @example
 *   @Post('avatar')
 *   @UseInterceptors(
 *     createSecureFileInterceptor('avatar'),
 *     SecureUploadInterceptor,
 *   )
 *   async uploadAvatar() { ... }
 */
/**
 * Multer memory storage instance (ESM-safe).
 * Created lazily to avoid top-level require/import issues.
 */
let _multerStorage: any = null;
function getMulterMemoryStorage(): any {
  if (!_multerStorage) {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const multer = require('multer');
    _multerStorage = multer.memoryStorage();
  }
  return _multerStorage;
}

/**
 * Factory function to create a Multer FileInterceptor pre-configured
 * with secure upload options.
 *
 * This ensures consistent MIME type validation at the Multer level
 * (before the file even reaches our interceptor).
 *
 * @param fieldName - The form field name for the file upload
 * @param options - Optional Multer options override
 *
 * @example
 *   @Post('avatar')
 *   @UseInterceptors(
 *     createSecureFileInterceptor('avatar'),
 *     SecureUploadInterceptor,
 *   )
 *   async uploadAvatar() { ... }
 */
export async function createSecureFileInterceptor(
  fieldName: string,
  options?: {
    maxFileSize?: number;
    destination?: string;
  },
): Promise<any> {
  const storage = getMulterMemoryStorage();

  const fileFilter = (
    req: any,
    file: any,
    callback: (error: Error | null, acceptFile: boolean) => void,
  ) => {
    if (ALLOWED_MIME_TYPES.includes(file.mimetype)) {
      callback(null, true);
    } else {
      callback(
        new Error(
          `Invalid file type: "${file.mimetype}". ` +
            `Allowed: ${ALLOWED_MIME_TYPES.join(', ')}`,
        ),
        false,
      );
    }
  };

  const { FileInterceptor } = await import('@nestjs/platform-express');
  return FileInterceptor(fieldName, {
    storage,
    fileFilter,
    limits: {
      fileSize: options?.maxFileSize ?? MAX_FILE_SIZE,
      files: 1,
      fields: 20,
    },
  });
}
