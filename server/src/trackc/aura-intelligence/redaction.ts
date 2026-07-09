// =============================================================================
// Track C v2.0 — AURA Intelligence
// redaction.ts
// =============================================================================
// PII redaction pass before sending content to the LLM provider.
// Section 12.2: AI PII Boundary.
//
// The LLM provider receives: decision title, description, options, constitution
// excerpt, structured metadata.
// The LLM provider NEVER receives: full names (replaced with roles), phone
// numbers, email addresses, locations beyond what's in the decision text.
//
// A redaction pass strips email/phone patterns BEFORE the LLM call.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';

export interface RedactionResult {
  redacted: string;
  removedCount: number;
  removedTypes: ('email' | 'phone' | 'ssn' | 'credit_card')[];
}

@Injectable()
export class RedactionService {
  private readonly logger = new Logger(RedactionService.name);

  // RFC 5322 simplified email pattern
  private readonly emailRegex = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g;

  // International + US phone patterns
  private readonly phoneRegex =
    /(\+?\d{1,3}[-.\s]?)?(\(?\d{2,4}\)?[-.\s]?){2,4}\d{2,4}/g;

  // US SSN pattern (XXX-XX-XXXX or XXXXXXXXX)
  private readonly ssnRegex = /\b\d{3}-?\d{2}-?\d{4}\b/g;

  // Credit card pattern (groups of 4 digits, 13-19 digits total)
  private readonly ccRegex = /\b(?:\d[ -]*?){13,19}\b/g;

  /**
   * Redact PII from a string. Replaces matches with [REDACTED_<TYPE>].
   */
  redact(input: string): RedactionResult {
    let redacted = input;
    let removedCount = 0;
    const removedTypes = new Set<RedactionResult['removedTypes'][number]>();

    redacted = redacted.replace(this.emailRegex, (m) => {
      removedCount++;
      removedTypes.add('email');
      return '[REDACTED_EMAIL]';
    });

    redacted = redacted.replace(this.ssnRegex, (m) => {
      // Skip if it looks like a date (e.g. 2024-01-15)
      if (/^\d{4}-\d{2}-\d{2}$/.test(m)) return m;
      removedCount++;
      removedTypes.add('ssn');
      return '[REDACTED_SSN]';
    });

    redacted = redacted.replace(this.ccRegex, (m) => {
      const digits = m.replace(/\D/g, '');
      if (digits.length < 13 || digits.length > 19) return m;
      removedCount++;
      removedTypes.add('credit_card');
      return '[REDACTED_CC]';
    });

    // Phone redaction — done last because it's the noisiest and could match
    // parts of SSNs/credit cards already redacted above. We only match patterns
    // that look like phone numbers (have at least one separator or country code).
    redacted = redacted.replace(/(\+?\d{1,3}[-.\s]\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4})/g, (m) => {
      // Skip pure dates
      if (/^\d{4}-\d{2}-\d{2}/.test(m)) return m;
      removedCount++;
      removedTypes.add('phone');
      return '[REDACTED_PHONE]';
    });

    if (removedCount > 0) {
      this.logger.debug(`Redacted ${removedCount} PII matches: ${[...removedTypes].join(', ')}`);
    }

    return {
      redacted,
      removedCount,
      removedTypes: [...removedTypes],
    };
  }

  /**
   * Replace user names with their roles in a family context.
   * The caller provides a map of userId → role label (e.g. "elder", "admin").
   */
  redactNames(input: string, nameToRoleMap: Map<string, string>): string {
    let out = input;
    for (const [name, role] of nameToRoleMap.entries()) {
      if (!name || name.length < 2) continue;
      // Case-insensitive replacement
      const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      out = out.replace(new RegExp(escaped, 'gi'), `[${role}]`);
    }
    return out;
  }
}
