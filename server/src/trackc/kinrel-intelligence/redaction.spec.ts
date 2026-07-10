// =============================================================================
// Track C v2.0 — PII Redaction Tests
// =============================================================================
// Section 12.2: AI PII Boundary.
// =============================================================================

import { RedactionService } from './redaction';

describe('RedactionService', () => {
  let service: RedactionService;

  beforeEach(() => {
    service = new RedactionService();
  });

  it('redacts email addresses', () => {
    const input = 'Contact me at john.doe@example.com for details.';
    const result = service.redact(input);
    expect(result.redacted).toContain('[REDACTED_EMAIL]');
    expect(result.redacted).not.toContain('john.doe@example.com');
    expect(result.removedCount).toBe(1);
    expect(result.removedTypes).toContain('email');
  });

  it('redacts multiple emails', () => {
    const input = 'Email alice@foo.com or bob@bar.org.';
    const result = service.redact(input);
    expect(result.removedCount).toBe(2);
  });

  it('redacts US SSN (but not dates)', () => {
    const input = 'SSN: 123-45-6789. Date: 2024-01-15.';
    const result = service.redact(input);
    expect(result.redacted).toContain('[REDACTED_SSN]');
    expect(result.redacted).not.toContain('123-45-6789');
    // Date should NOT be redacted as SSN
    expect(result.redacted).toContain('2024-01-15');
  });

  it('redacts phone numbers with country code', () => {
    const input = 'Call me at +1-555-123-4567.';
    const result = service.redact(input);
    expect(result.redacted).toContain('[REDACTED_PHONE]');
    expect(result.redacted).not.toContain('+1-555-123-4567');
  });

  it('redacts credit card numbers', () => {
    const input = 'Card: 4111 1111 1111 1111.';
    const result = service.redact(input);
    expect(result.redacted).toContain('[REDACTED_CC]');
  });

  it('does not redact normal text', () => {
    const input = 'The decision is about the family vacation.';
    const result = service.redact(input);
    expect(result.redacted).toBe(input);
    expect(result.removedCount).toBe(0);
  });

  it('redacts names when nameToRoleMap is provided', () => {
    const input = 'Alice suggested we go. Bob disagreed. Alice then proposed a vote.';
    const nameMap = new Map([
      ['Alice', 'elder'],
      ['Bob', 'admin'],
    ]);
    const result = service.redactNames(input, nameMap);
    expect(result).toContain('[elder]');
    expect(result).toContain('[admin]');
    expect(result).not.toContain('Alice');
    expect(result).not.toContain('Bob');
  });
});
