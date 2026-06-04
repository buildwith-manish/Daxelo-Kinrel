import * as crypto from 'crypto';

const ALGO = 'aes-256-gcm';

/**
 * Encrypt a plaintext string using AES-256-GCM.
 * Returns a colon-separated string of iv:authTag:ciphertext (all hex-encoded).
 */
export function encrypt(text: string, key: string): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGO, Buffer.from(key, 'hex'), iv);
  const encrypted = Buffer.concat([
    cipher.update(text, 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return `${iv.toString('hex')}:${tag.toString('hex')}:${encrypted.toString('hex')}`;
}

/**
 * Decrypt a payload produced by encrypt().
 * Expects the format iv:authTag:ciphertext (all hex-encoded).
 */
export function decrypt(payload: string, key: string): string {
  const [iv, tag, encrypted] = payload
    .split(':')
    .map((p) => Buffer.from(p, 'hex'));
  const decipher = crypto.createDecipheriv(
    ALGO,
    Buffer.from(key, 'hex'),
    iv,
  );
  decipher.setAuthTag(tag);
  return Buffer.concat([
    decipher.update(encrypted),
    decipher.final(),
  ]).toString('utf8');
}
