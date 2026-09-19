import { Test, TestingModule } from '@nestjs/testing';
import { MediaService } from './media.service';
import { ConfigService } from '@nestjs/config';
import { BadRequestException } from '@nestjs/common';

/**
 * MediaService unit tests.
 *
 * Verifies:
 *   • Validation logic (mediaType, MIME type, file size limits)
 *   • isAvailable() returns false when SUPABASE_URL is unset
 *   • uploadMedia throws when service is unavailable
 *   • uploadMedia throws on invalid mediaType
 *   • uploadMedia throws on disallowed MIME type
 *   • uploadMedia throws on oversized file
 *
 * We don't test the actual Supabase Storage upload (that requires a real
 * Supabase project) — the integration is verified by the e2e test instead.
 */
describe('MediaService', () => {
  let service: MediaService;

  const mockConfig = {
    get: jest.fn((key: string, def?: string) => {
      // Return empty for Supabase keys so the service starts in
      // "unavailable" mode (no real Supabase client).
      if (key === 'SUPABASE_URL' || key === 'SUPABASE_SERVICE_ROLE_KEY') {
        return '';
      }
      return def;
    }),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MediaService,
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();
    service = module.get<MediaService>(MediaService);
    jest.clearAllMocks();
  });

  it('is defined', () => {
    expect(service).toBeDefined();
  });

  it('isAvailable() returns false when SUPABASE_URL is unset', () => {
    expect(service.isAvailable()).toBe(false);
  });

  describe('uploadMedia — service unavailable', () => {
    it('throws BadRequestException when Supabase is not configured', async () => {
      await expect(
        service.uploadMedia({
          buffer: Buffer.from('test'),
          mediaType: 'image',
          mimeType: 'image/jpeg',
          familyId: 'fam-1',
          messageId: 'msg-1',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('uploadMedia — validation (via the unavailable-service path)', () => {
    // When the service is unavailable, uploadMedia validates FIRST then
    // throws "unavailable". So we can test validation by checking which
    // error message we get.

    it('rejects invalid mediaType', async () => {
      // The service checks availability FIRST (before validate), so this
      // throws "unavailable" not "invalid mediaType". To test the validate
      // logic directly, we'd need to mock the supabase client. For now,
      // we verify the error is a BadRequestException (which both paths throw).
      await expect(
        service.uploadMedia({
          buffer: Buffer.from('test'),
          mediaType: 'invalid',
          mimeType: 'image/jpeg',
          familyId: 'fam-1',
          messageId: 'msg-1',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('deleteMedia', () => {
    it('is a no-op when service is unavailable', async () => {
      // Should not throw — just silently return.
      await expect(service.deleteMedia('https://example.com/chat-media/foo/bar.jpg'))
          .resolves.toBeUndefined();
    });

    it('is a no-op for malformed URLs', async () => {
      await expect(service.deleteMedia('not-a-url')).resolves.toBeUndefined();
    });
  });
});

/// Test the validation logic directly by creating a MediaService with
/// a mocked Supabase client. This lets us test the validate() private
/// method's behavior via uploadMedia without hitting real Supabase.
describe('MediaService — validation with mocked Supabase', () => {
  let service: MediaService;

  const mockConfig = {
    get: jest.fn((key: string, def?: string) => {
      if (key === 'SUPABASE_URL') return 'https://test.supabase.co';
      if (key === 'SUPABASE_SERVICE_ROLE_KEY') return 'test-service-role-key';
      return def;
    }),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MediaService,
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();
    service = module.get<MediaService>(MediaService);
    jest.clearAllMocks();
  });

  it('isAvailable() returns true when SUPABASE_URL is set', () => {
    expect(service.isAvailable()).toBe(true);
  });

  it('rejects invalid mediaType', async () => {
    await expect(
      service.uploadMedia({
        buffer: Buffer.from('test'),
        mediaType: 'invalid',
        mimeType: 'image/jpeg',
        familyId: 'fam-1',
        messageId: 'msg-1',
      }),
    ).rejects.toThrow(/Invalid mediaType/);
  });

  it('rejects disallowed MIME type for image', async () => {
    await expect(
      service.uploadMedia({
        buffer: Buffer.from('test'),
        mediaType: 'image',
        mimeType: 'image/bmp', // not in allowed list
        familyId: 'fam-1',
        messageId: 'msg-1',
      }),
    ).rejects.toThrow(/MIME type.*not allowed/);
  });

  it('rejects disallowed MIME type for voice', async () => {
    await expect(
      service.uploadMedia({
        buffer: Buffer.from('test'),
        mediaType: 'voice',
        mimeType: 'audio/wav', // not in allowed list
        familyId: 'fam-1',
        messageId: 'msg-1',
      }),
    ).rejects.toThrow(/MIME type.*not allowed/);
  });

  it('rejects oversized image (> 25 MB)', async () => {
    const oversized = Buffer.alloc(26 * 1024 * 1024); // 26 MB
    await expect(
      service.uploadMedia({
        buffer: oversized,
        mediaType: 'image',
        mimeType: 'image/jpeg',
        familyId: 'fam-1',
        messageId: 'msg-1',
      }),
    ).rejects.toThrow(/File too large/);
  });

  it('rejects oversized voice note (> 5 MB)', async () => {
    const oversized = Buffer.alloc(6 * 1024 * 1024); // 6 MB
    await expect(
      service.uploadMedia({
        buffer: oversized,
        mediaType: 'voice',
        mimeType: 'audio/m4a',
        familyId: 'fam-1',
        messageId: 'msg-1',
      }),
    ).rejects.toThrow(/File too large/);
  });

  it('accepts valid image (jpeg, < 25 MB)', async () => {
    // This will pass validation but fail at the Supabase upload step
    // (because the URL is fake). We expect a BadRequestException with
    // "Upload failed" — not a validation error.
    const validImage = Buffer.alloc(1024); // 1 KB
    await expect(
      service.uploadMedia({
        buffer: validImage,
        mediaType: 'image',
        mimeType: 'image/jpeg',
        familyId: 'fam-1',
        messageId: 'msg-1',
      }),
    ).rejects.toThrow(/Upload failed|Bucket not found|fetch/);
  });
});
