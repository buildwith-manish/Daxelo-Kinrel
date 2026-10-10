// server/src/modules/chat/secret-chats.service.spec.ts
//
// Unit tests for SecretChatsService — Tier 5 Feature 5.1.

import { Test, TestingModule } from '@nestjs/testing';
import { SecretChatsService } from './secret-chats.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';

describe('SecretChatsService', () => {
  let service: SecretChatsService;

  const mockPrisma = {
    userPublicKey: { upsert: jest.fn(), findUnique: jest.fn() },
    secretChat: { findFirst: jest.fn(), findUnique: jest.fn(), create: jest.fn(), update: jest.fn(), findMany: jest.fn() },
    secretMessage: { create: jest.fn(), findMany: jest.fn(), updateMany: jest.fn() },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SecretChatsService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<SecretChatsService>(SecretChatsService);
    jest.clearAllMocks();
  });

  describe('upsertPublicKey — validation', () => {
    it('throws BadRequestException for an invalid keyType', async () => {
      await expect(
        service.upsertPublicKey('user-1', { keyType: 'rsa', publicKeyB64: 'x' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when publicKeyB64 is empty', async () => {
      await expect(
        service.upsertPublicKey('user-1', { keyType: 'x25519', publicKeyB64: '' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('upserts the public key when validation passes', async () => {
      const created = { userId: 'user-1', keyType: 'x25519', publicKeyB64: 'abc' };
      mockPrisma.userPublicKey.upsert.mockResolvedValue(created);
      const result = await service.upsertPublicKey('user-1', { keyType: 'x25519', publicKeyB64: 'abc' });
      expect(result).toBe(created);
    });
  });

  describe('getPublicKey', () => {
    it('throws NotFoundException when the key is missing', async () => {
      mockPrisma.userPublicKey.findUnique.mockResolvedValue(null);
      await expect(
        service.getPublicKey('user-2', 'x25519'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('initiateSecretChat — validation', () => {
    it('throws BadRequestException when starting a chat with yourself', async () => {
      await expect(
        service.initiateSecretChat('user-1', { peerUserId: 'user-1', keyFingerprint: 'fp'.repeat(16) }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when keyFingerprint is too short', async () => {
      await expect(
        service.initiateSecretChat('user-1', { peerUserId: 'user-2', keyFingerprint: 'short' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('returns the existing chat when one is already pending', async () => {
      const existing = { id: 'sc_existing', status: 'pending' };
      mockPrisma.secretChat.findFirst.mockResolvedValue(existing);
      const result = await service.initiateSecretChat('user-1', { peerUserId: 'user-2', keyFingerprint: 'fp'.repeat(16) });
      expect(result).toEqual(expect.objectContaining({ action: 'already_exists', secretChatId: 'sc_existing' }));
      expect(mockPrisma.secretChat.create).not.toHaveBeenCalled();
    });

    it('creates a new pending chat', async () => {
      mockPrisma.secretChat.findFirst.mockResolvedValue(null);
      const created = { id: 'sc_new', status: 'pending' };
      mockPrisma.secretChat.create.mockResolvedValue(created);
      const result = await service.initiateSecretChat('user-1', { peerUserId: 'user-2', keyFingerprint: 'fp'.repeat(16) });
      expect(result).toBe(created);
    });
  });

  describe('respondToSecretChat — validation', () => {
    it('throws NotFoundException when the chat does not exist', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue(null);
      await expect(
        service.respondToSecretChat('user-1', { secretChatId: 'sc_x', accept: true }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the initiator tries to respond', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue({
        id: 'sc_x', userA: 'user-1', userB: 'user-2',
        initiatorUserId: 'user-1', status: 'pending', keyFingerprint: 'fp'.repeat(16),
      });
      await expect(
        service.respondToSecretChat('user-1', { secretChatId: 'sc_x', accept: true }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws BadRequestException when the key fingerprint does not match on accept', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue({
        id: 'sc_x', userA: 'user-1', userB: 'user-2',
        initiatorUserId: 'user-1', status: 'pending', keyFingerprint: 'aaa',
      });
      await expect(
        service.respondToSecretChat('user-2', { secretChatId: 'sc_x', accept: true, keyFingerprint: 'bbb' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects the chat when accept=false', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue({
        id: 'sc_x', userA: 'user-1', userB: 'user-2',
        initiatorUserId: 'user-1', status: 'pending', keyFingerprint: 'fp',
      });
      const updated = { id: 'sc_x', status: 'rejected' };
      mockPrisma.secretChat.update.mockResolvedValue(updated);
      const result = await service.respondToSecretChat('user-2', { secretChatId: 'sc_x', accept: false });
      expect(result).toBe(updated);
    });

    it('accepts the chat when fingerprints match', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue({
        id: 'sc_x', userA: 'user-1', userB: 'user-2',
        initiatorUserId: 'user-1', status: 'pending', keyFingerprint: 'fp',
      });
      const updated = { id: 'sc_x', status: 'active' };
      mockPrisma.secretChat.update.mockResolvedValue(updated);
      const result = await service.respondToSecretChat('user-2', { secretChatId: 'sc_x', accept: true, keyFingerprint: 'fp' });
      expect(result).toBe(updated);
    });
  });

  describe('sendSecretMessage — validation', () => {
    it('throws NotFoundException when the chat does not exist', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue(null);
      await expect(
        service.sendSecretMessage('user-1', { secretChatId: 'sc_x', ciphertext: '', iv: '' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when not a participant', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue({
        id: 'sc_x', userA: 'user-1', userB: 'user-2', status: 'active',
      });
      await expect(
        service.sendSecretMessage('user-3', { secretChatId: 'sc_x', ciphertext: 'c', iv: 'i' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws BadRequestException when the chat is not active', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue({
        id: 'sc_x', userA: 'user-1', userB: 'user-2', status: 'pending',
      });
      await expect(
        service.sendSecretMessage('user-1', { secretChatId: 'sc_x', ciphertext: 'c', iv: 'i' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('persists the ciphertext when validation passes', async () => {
      mockPrisma.secretChat.findUnique.mockResolvedValue({
        id: 'sc_x', userA: 'user-1', userB: 'user-2', status: 'active',
      });
      const created = { id: 'sm_new', ciphertext: 'c' };
      mockPrisma.secretMessage.create.mockResolvedValue(created);
      const result = await service.sendSecretMessage('user-1', {
        secretChatId: 'sc_x', ciphertext: 'c', iv: 'i',
      });
      expect(result).toBe(created);
    });
  });
});
