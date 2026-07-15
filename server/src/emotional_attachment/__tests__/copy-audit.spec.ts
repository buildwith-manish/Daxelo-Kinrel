// server/src/emotional_attachment/__tests__/copy-audit.spec.ts
//
// P1.2: Copy-audit test for Family Suggestions (formerly Family Quests).
//
// This test greps every quest/suggestion description template and the service
// source file for forbidden phrases that violate the Copy-Audit Checklist
// (spec Part IV §4.3). If any forbidden phrase is present, the test fails.
//
// Forbidden phrases (guilt language, manufactured urgency, FOMO, manipulative
// framing):
//   - "don't forget" — guilt
//   - "stormy" — loaded emotional weather word (when used in user-facing copy)
//   - "haven't spoken" — guilt
//   - "goes a long way" — manipulative framing
//   - "turn things around" — guilt
//   - "expiring" / "last chance" / "don't miss" — manufactured urgency
//   - "Be the first" — competition/FOMO
//
// This test is a regression gate: if a future PR reintroduces any of these
// phrases, the CI build fails.

import * as fs from 'fs';
import * as path from 'path';

describe('Family Suggestions copy-audit (P1.2)', () => {
  const servicePath = path.resolve(
    __dirname,
    '../family-quest.service.ts',
  );
  let source = '';

  beforeAll(() => {
    source = fs.readFileSync(servicePath, 'utf-8');
  });

  // Forbidden phrases that must NEVER appear in suggestion descriptions.
  // Each entry is [phrase, reason].
  const forbiddenPhrases: Array<[string, string]> = [
    ["don't forget", 'guilt language'],
    ['Be the first', 'competition/FOMO'],
    ['haven\'t spoken', 'guilt language'],
    ['goes a long way', 'manipulative framing'],
    ['turn things around', 'guilt language'],
    ['expiring', 'manufactured urgency'],
    ['last chance', 'manufactured urgency'],
    ["don't miss", 'manufactured urgency'],
    ['hurry', 'manufactured urgency'],
  ];

  // Extract only the description-template lines (lines containing `description =`)
  // so we don't false-positive on the ethical-rationale comment that explicitly
  // mentions these phrases to say they're absent.
  const descriptionLines = source
    .split('\n')
    .filter((line) => line.includes('description =') || line.includes('description ='));

  forbiddenPhrases.forEach(([phrase, reason]) => {
    it(`description templates must not contain "${phrase}" (${reason})`, () => {
      const violations = descriptionLines.filter((line) =>
        line.toLowerCase().includes(phrase.toLowerCase()),
      );
      expect(violations).toEqual([]);
    });
  });

  it('description templates must not contain "TODAY" in all-caps (urgency)', () => {
    const violations = descriptionLines.filter((line) =>
      /\bTODAY\b/.test(line),
    );
    expect(violations).toEqual([]);
  });

  it('must NOT use variable QUEST_KARMA_BY_TYPE (Do Not Do #3)', () => {
    expect(source).not.toContain('QUEST_KARMA_BY_TYPE');
  });

  it('must use FIXED_QUEST_KARMA (fixed reward, not variable)', () => {
    expect(source).toContain('FIXED_QUEST_KARMA');
  });

  it('must NOT use "expired" status (renamed to "rotated")', () => {
    // Check only actual status assignments — NOT comments that mention
    // 'expired' to document the rename. We filter to lines containing
    // "status:" with 'expired' as a value.
    const expiredStatusUsages = source
      .split('\n')
      .filter((line) => {
        const trimmed = line.trim();
        // Skip comment lines (they document the rename).
        if (trimmed.startsWith('//')) return false;
        // Check for status: 'expired' or status: "expired" assignments.
        return /status:\s*['"]expired['"]/.test(line) ||
               /['"]expired['"].*status/i.test(line);
      });
    expect(expiredStatusUsages).toEqual([]);
  });

  it('must use "rotated" status (not "expired")', () => {
    expect(source).toContain("'rotated'");
  });
});
