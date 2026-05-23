// DAXELO KINREL — WhatsApp Business API Client
// Pack 04: WhatsApp Platform

import CryptoJS from 'crypto-js';

const WHATSAPP_API_URL = process.env.WHATSAPP_API_URL ?? 'https://graph.facebook.com/v18.0';
const WHATSAPP_PHONE_NUMBER_ID = process.env.WHATSAPP_PHONE_NUMBER_ID ?? '';
const WHATSAPP_ACCESS_TOKEN = process.env.WHATSAPP_ACCESS_TOKEN ?? '';
const WHATSAPP_WEBHOOK_VERIFY_TOKEN = process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN ?? '';
const WHATSAPP_APP_SECRET = process.env.WHATSAPP_APP_SECRET ?? '';

export interface WhatsAppMessage {
  from: string;
  messageId: string;
  timestamp: string;
  type: 'text' | 'interactive' | 'button' | 'document' | 'image' | 'location' | 'contacts';
  text?: { body: string };
  interactive?: Record<string, unknown>;
  button?: Record<string, unknown>;
  document?: Record<string, unknown>;
  image?: Record<string, unknown>;
  location?: Record<string, unknown>;
  contacts?: Record<string, unknown>;
}

export interface WhatsAppSendResponse {
  messageId: string;
  status: string;
}

export interface WhatsAppDeliveryStatus {
  messageId: string;
  status: 'sent' | 'delivered' | 'read' | 'failed';
  timestamp: string;
  recipientId: string;
}

export class WhatsAppClient {
  private readonly baseUrl: string;
  private readonly phoneNumberId: string;
  private readonly accessToken: string;

  constructor() {
    this.baseUrl = WHATSAPP_API_URL;
    this.phoneNumberId = WHATSAPP_PHONE_NUMBER_ID;
    this.accessToken = WHATSAPP_ACCESS_TOKEN;
  }

  async sendTextMessage(to: string, text: string): Promise<WhatsAppSendResponse> {
    const response = await fetch(`${this.baseUrl}/${this.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'text',
        text: { body: text, preview_url: false },
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`WhatsApp API error: ${JSON.stringify(error)}`);
    }

    const data = await response.json();
    return {
      messageId: data.messages?.[0]?.id ?? '',
      status: data.messages?.[0]?.message_status ?? 'sent',
    };
  }

  async sendInteractiveMessage(
    to: string,
    header: string,
    body: string,
    buttons: Array<{ id: string; title: string }>,
    footer?: string,
  ): Promise<WhatsAppSendResponse> {
    const response = await fetch(`${this.baseUrl}/${this.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'interactive',
        interactive: {
          type: 'button',
          header: { type: 'text', text: header },
          body: { text: body },
          footer: footer ? { text: footer } : undefined,
          action: {
            buttons: buttons.map(b => ({
              type: 'reply',
              reply: { id: b.id, title: b.title },
            })),
          },
        },
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`WhatsApp API error: ${JSON.stringify(error)}`);
    }

    const data = await response.json();
    return { messageId: data.messages?.[0]?.id ?? '', status: 'sent' };
  }

  async sendListMessage(
    to: string,
    header: string,
    body: string,
    sections: Array<{
      title: string;
      rows: Array<{ id: string; title: string; description?: string }>;
    }>,
    buttonText: string = 'Options',
    footer?: string,
  ): Promise<WhatsAppSendResponse> {
    const response = await fetch(`${this.baseUrl}/${this.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'interactive',
        interactive: {
          type: 'list',
          header: { type: 'text', text: header },
          body: { text: body },
          footer: footer ? { text: footer } : undefined,
          action: {
            button: buttonText,
            sections: sections.map((section) => ({
              title: section.title,
              rows: section.rows.map((row) => ({
                id: row.id,
                title: row.title,
                description: row.description,
              })),
            })),
          },
        },
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`WhatsApp API error: ${JSON.stringify(error)}`);
    }

    const data = await response.json();
    return { messageId: data.messages?.[0]?.id ?? '', status: 'sent' };
  }

  async sendTemplateMessage(
    to: string,
    templateName: string,
    language: string = 'en',
    parameters: string[] = [],
    components?: Record<string, unknown>[],
  ): Promise<WhatsAppSendResponse> {
    const payload: Record<string, unknown> = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to,
      type: 'template',
      template: {
        name: templateName,
        language: { code: language },
      },
    };

    if (parameters.length > 0 || components) {
      (payload.template as Record<string, unknown>).components = components ?? [{
        type: 'body',
        parameters: parameters.map(p => ({ type: 'text', text: p })),
      }];
    }

    const response = await fetch(`${this.baseUrl}/${this.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`WhatsApp API error: ${JSON.stringify(error)}`);
    }

    const data = await response.json();
    return { messageId: data.messages?.[0]?.id ?? '', status: 'sent' };
  }

  async sendImageMessage(
    to: string,
    imageUrl: string,
    caption?: string,
  ): Promise<WhatsAppSendResponse> {
    const response = await fetch(`${this.baseUrl}/${this.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'image',
        image: {
          link: imageUrl,
          caption,
        },
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`WhatsApp API error: ${JSON.stringify(error)}`);
    }

    const data = await response.json();
    return { messageId: data.messages?.[0]?.id ?? '', status: 'sent' };
  }

  async sendDocumentMessage(
    to: string,
    documentUrl: string,
    filename: string,
    caption?: string,
  ): Promise<WhatsAppSendResponse> {
    const response = await fetch(`${this.baseUrl}/${this.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'document',
        document: {
          link: documentUrl,
          filename,
          caption,
        },
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`WhatsApp API error: ${JSON.stringify(error)}`);
    }

    const data = await response.json();
    return { messageId: data.messages?.[0]?.id ?? '', status: 'sent' };
  }

  verifyWebhookSignature(payload: string, signature: string): boolean {
    if (!WHATSAPP_APP_SECRET) return false;
    const expectedSig = CryptoJS
      .HmacSHA256(payload, WHATSAPP_APP_SECRET)
      .toString(CryptoJS.enc.Hex);
    return signature === `sha256=${expectedSig}`;
  }

  verifyWebhookToken(mode: string, token: string): boolean {
    return mode === 'subscribe' && token === WHATSAPP_WEBHOOK_VERIFY_TOKEN;
  }

  isConfigured(): boolean {
    return !!(this.phoneNumberId && this.accessToken);
  }
}

export const whatsappClient = new WhatsAppClient();
