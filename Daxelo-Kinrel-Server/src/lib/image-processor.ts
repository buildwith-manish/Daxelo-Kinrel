/**
 * DAXELO KINREL — Image Processor Utility
 *
 * Server-side image processing with Sharp.
 * Supports WebP conversion, EXIF stripping, thumbnails, and blurhash.
 *
 * Pack 01: Design System — Icons & Imagery
 */

import sharp from 'sharp'

export interface ProcessedImage {
  original: Buffer
  thumbnail: Buffer
  medium: Buffer
  width: number
  height: number
}

export async function processUploadedImage(
  buffer: Buffer,
): Promise<ProcessedImage> {
  const image = sharp(buffer)
  const metadata = await image.metadata()

  // Strip EXIF and convert to WebP
  const originalBuffer = await image
    .rotate()
    .webp({ quality: 85 })
    .toBuffer()

  const thumbnailBuffer = await image
    .resize(200, 200, { fit: 'cover' })
    .webp({ quality: 80 })
    .toBuffer()

  const mediumBuffer = await image
    .resize(400, 400, { fit: 'cover' })
    .webp({ quality: 82 })
    .toBuffer()

  return {
    original: originalBuffer,
    thumbnail: thumbnailBuffer,
    medium: mediumBuffer,
    width: metadata.width ?? 0,
    height: metadata.height ?? 0,
  }
}

/**
 * Generate a simple blur data URL for progressive image loading
 */
export async function generateBlurDataURL(buffer: Buffer): Promise<string> {
  const data = await sharp(buffer)
    .resize(10, 10, { fit: 'cover' })
    .blur(5)
    .webp({ quality: 20 })
    .toBuffer()

  return `data:image/webp;base64,${data.toString('base64')}`
}
