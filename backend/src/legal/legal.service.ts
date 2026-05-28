import { Injectable } from '@nestjs/common';
import { readFileSync } from 'fs';
import { join } from 'path';

@Injectable()
export class LegalService {
  private privacyHtml: string | null = null;
  private termsHtml: string | null = null;

  getPrivacyPolicy(): string {
    if (!this.privacyHtml) {
      this.privacyHtml = this.loadAndConvert('privacy.md');
    }
    return this.privacyHtml;
  }

  getTermsOfService(): string {
    if (!this.termsHtml) {
      this.termsHtml = this.loadAndConvert('terms.md');
    }
    return this.termsHtml;
  }

  private loadAndConvert(filename: string): string {
    try {
      const filePath = join(__dirname, 'content', filename);
      const markdown = readFileSync(filePath, 'utf-8');
      return this.markdownToHtml(markdown);
    } catch {
      return '<p>Content not available. Please contact privacy@daxelo.com.</p>';
    }
  }

  private markdownToHtml(md: string): string {
    return md
      .split('\n')
      .map(line => {
        // Headers
        if (line.startsWith('### ')) return `<h3>${line.slice(4)}</h3>`;
        if (line.startsWith('## ')) return `<h2>${line.slice(3)}</h2>`;
        if (line.startsWith('# ')) return `<h1>${line.slice(2)}</h1>`;
        // Bold
        line = line.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        // Italic
        line = line.replace(/\*(.*?)\*/g, '<em>$1</em>');
        // Links
        line = line.replace(/\[(.*?)\]\((.*?)\)/g, '<a href="$2">$1</a>');
        // Empty lines
        if (line.trim() === '') return '';
        // Regular text
        return `<p>${line}</p>`;
      })
      .join('\n');
  }
}
