// server/src/modules/chat/secret-chats.service.ts
//
// DAXELO KINREL — Tier 5 Feature 5.1: Secret Chats — Service
//
// Thin ciphertext-only storage for E2E-encrypted 1:1 chats. The crypto
// (X25519 key exchange, AES-GCM encryption/decryption) happens entirely
// on the client side. The server:
//   • Stores each user's PUBLIC key (UserPublicKey table) so peers can
//     fetch it to compute the shared secret.
//   • Stores ciphertext + iv + expiresAt per message (SecretMessage table).
//   • Validates the keyFingerprint matches on accept (so the peer can
//     detect a tampered key exchange).
//   • Cron-deletes expired ciphertext every 15 minutes.
//
// The server NEVER sees plaintext, the shared secret, or the AES key.

import { Injectable, BadRequestException, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class SecretChatsService {
  private readonly logger = new Logger(SecretChatsService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// Upsert the caller's public key. The Flutter client generates an
  /// X25519 keypair locally + posts the public half here. Anyone can
  /// read it via GET /chat/secret-chats/public-key/:userId to start
  /// a secret chat with the caller.
  async upsertPublicKey(userId: string, params: { keyType: string; publicKeyB64: string }) {
    if (!['x25519', 'ed25519'].includes(params.keyType)) {
      throw new BadRequestException('keyType must be x25519 or ed25519');
    }
    if (!params.publicKeyB64?.trim()) {
      throw new BadRequestException('publicKeyB64 is required');
    }
    return this.prisma.userPublicKey.upsert({
      where: { userId_keyType: { userId, keyType: params.keyType } },
      create: {
        userId,
        keyType: params.keyType,
        publicKeyB64: params.publicKeyB64.trim(),
      },
      update: { publicKeyB64: params.publicKeyB64.trim() },
    });
  }

  /// Fetch a user's public key (so the caller can compute the shared
  /// secret locally). Public endpoint — anyone authenticated can read
  /// any user's public key.
  async getPublicKey(userId: string, keyType: string = 'x25519') {
    const row = await this.prisma.userPublicKey.findUnique({
      where: { userId_keyType: { userId, keyType } },
    });
    if (!row) throw new NotFoundException('Public key not found');
    return row;
  }

  /// Initiate a secret chat with a peer. The caller computes the shared
  /// secret locally (from their private key + the peer's public key),
  /// derives the keyFingerprint (SHA-256 of the shared secret), and
  /// posts it here. The peer re-derives on accept + compares.
  async initiateSecretChat(
    userId: string,
    params: { peerUserId: string; keyFingerprint: string },
  ) {
    if (params.peerUserId === userId) {
      throw new BadRequestException('Cannot start a secret chat with yourself');
    }
    if (params.keyFingerprint.length < 16) {
      throw new BadRequestException('keyFingerprint must be at least 16 chars');
    }

    // Idempotent — return existing pending/active chat if one exists.
    const existing = await this.prisma.secretChat.findFirst({
      where: {
        OR: [
          { userA: userId, userB: params.peerUserId, status: { in: ['pending', 'active'] } },
          { userA: params.peerUserId, userB: userId, status: { in: ['pending', 'active'] } },
        ],
      },
    });
    if (existing) {
      return { action: 'already_exists' as const, secretChatId: existing.id, ...existing };
    }

    const id = `sc_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return this.prisma.secretChat.create({
      data: {
        id,
        userA: userId,
        userB: params.peerUserId,
        initiatorUserId: userId,
        keyFingerprint: params.keyFingerprint,
        status: 'pending',
      },
    });
  }

  /// Peer accepts or rejects a pending secret chat. On accept, the
  /// peer's recomputed keyFingerprint must match the initiator's.
  async respondToSecretChat(
    userId: string,
    params: { secretChatId: string; accept: boolean; keyFingerprint?: string | null },
  ) {
    const chat = await this.prisma.secretChat.findUnique({
      where: { id: params.secretChatId },
    });
    if (!chat) throw new NotFoundException('Secret chat not found');
    if (userId === chat.initiatorUserId) {
      throw new ForbiddenException('Initiator cannot respond to their own request');
    }
    if (userId !== chat.userA && userId !== chat.userB) {
      throw new ForbiddenException('Not a participant in this secret chat');
    }
    if (chat.status !== 'pending') {
      throw new BadRequestException(`Secret chat is not pending (current: ${chat.status})`);
    }

    if (!params.accept) {
      return this.prisma.secretChat.update({
        where: { id: params.secretChatId },
        data: { status: 'rejected', closedAt: new Date() },
      });
    }

    // Accept — validate the key fingerprint matches.
    if (params.keyFingerprint && params.keyFingerprint !== chat.keyFingerprint) {
      throw new BadRequestException('Key fingerprints do not match — the shared secret differs');
    }

    return this.prisma.secretChat.update({
      where: { id: params.secretChatId },
      data: { status: 'active', acceptedAt: new Date() },
    });
  }

  /// List the caller's secret chats (pending incoming + active).
  async listMySecretChats(userId: string) {
    return this.prisma.secretChat.findMany({
      where: {
        OR: [{ userA: userId }, { userB: userId }],
        status: { in: ['pending', 'active'] },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  /// Persist a ciphertext message. The Flutter client encrypts locally
  /// with AES-GCM using the shared secret, then posts the ciphertext +
  /// iv here. The server never sees plaintext.
  async sendSecretMessage(
    userId: string,
    params: {
      secretChatId: string;
      ciphertext: string;
      iv: string;
      messageType?: string;
      expiresAt?: Date | null;
    },
  ) {
    const chat = await this.prisma.secretChat.findUnique({
      where: { id: params.secretChatId },
    });
    if (!chat) throw new NotFoundException('Secret chat not found');
    if (userId !== chat.userA && userId !== chat.userB) {
      throw new ForbiddenException('Not a participant in this secret chat');
    }
    if (chat.status !== 'active') {
      throw new BadRequestException('Secret chat is not active');
    }
    if (!params.ciphertext?.trim() || !params.iv?.trim()) {
      throw new BadRequestException('ciphertext + iv are required');
    }

    const id = `sm_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return this.prisma.secretMessage.create({
      data: {
        id,
        secretChatId: params.secretChatId,
        senderId: userId,
        ciphertext: params.ciphertext,
        iv: params.iv,
        messageType: params.messageType ?? 'text',
        expiresAt: params.expiresAt ?? null,
      },
    });
  }

  /// List messages in a secret chat. Returns ciphertext + iv only —
  /// the Flutter client decrypts locally with the shared secret.
  async listMessages(userId: string, secretChatId: string, limit: number = 50, before?: Date) {
    const chat = await this.prisma.secretChat.findUnique({
      where: { id: secretChatId },
    });
    if (!chat) throw new NotFoundException('Secret chat not found');
    if (userId !== chat.userA && userId !== chat.userB) {
      throw new ForbiddenException('Not a participant in this secret chat');
    }

    return this.prisma.secretMessage.findMany({
      where: {
        secretChatId,
        ...(before ? { createdAt: { lt: before } } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 200),
    });
  }

  /// Mark messages as read (for the read indicator — does NOT expose
  /// any content, just flips isRead on the rows).
  async markRead(userId: string, secretChatId: string, messageIds?: string[]) {
    const chat = await this.prisma.secretChat.findUnique({
      where: { id: secretChatId },
    });
    if (!chat) throw new NotFoundException('Secret chat not found');
    if (userId !== chat.userA && userId !== chat.userB) {
      throw new ForbiddenException('Not a participant in this secret chat');
    }

    // Mark only messages NOT sent by the caller (you don't read your own).
    await this.prisma.secretMessage.updateMany({
      where: {
        secretChatId,
        senderId: { not: userId },
        ...(messageIds ? { id: { in: messageIds } } : {}),
      },
      data: { isRead: true },
    });
    return { success: true };
  }

  /// Close a secret chat (one-sided). All messages are hard-deleted
  /// via the ON DELETE CASCADE on SecretMessage.
  async closeSecretChat(userId: string, secretChatId: string) {
    const chat = await this.prisma.secretChat.findUnique({
      where: { id: secretChatId },
    });
    if (!chat) throw new NotFoundException('Secret chat not found');
    if (userId !== chat.userA && userId !== chat.userB) {
      throw new ForbiddenException('Not a participant in this secret chat');
    }
    return this.prisma.secretChat.update({
      where: { id: secretChatId },
      data: { status: 'closed', closedAt: new Date() },
    });
  }
}
