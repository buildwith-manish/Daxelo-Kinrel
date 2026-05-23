import { Injectable, Logger } from '@nestjs/common';
import { WebSocketGatewayService } from './websocket.gateway';
import type {
  FamilyUpdatedPayload,
  PersonEventPayload,
  RelationshipEventPayload,
  NotificationNewPayload,
  InvitationEventPayload,
} from './dto/socket-event.dto';

/**
 * WebSocketService — Facade for emitting real-time events
 *
 * This service provides a clean API for other modules to emit
 * WebSocket events without needing to reference the gateway directly.
 */
@Injectable()
export class WebSocketService {
  private readonly logger = new Logger(WebSocketService.name);

  constructor(private readonly gateway: WebSocketGatewayService) {}

  // ── Family Events ─────────────────────────────────────────────────

  emitFamilyUpdated(familyId: string, updatedBy: string, changes: Record<string, unknown>) {
    this.gateway.emitFamilyUpdated({ familyId, updatedBy, changes });
  }

  // ── Person Events ─────────────────────────────────────────────────

  emitPersonCreated(familyId: string, personId: string, actionBy: string, personName?: string) {
    this.gateway.emitPersonCreated({
      familyId,
      personId,
      personName,
      actionBy,
    });
  }

  emitPersonUpdated(familyId: string, personId: string, actionBy: string, data?: Record<string, unknown>) {
    this.gateway.emitPersonUpdated({
      familyId,
      personId,
      actionBy,
      data,
    });
  }

  emitPersonDeleted(familyId: string, personId: string, actionBy: string) {
    this.gateway.emitPersonDeleted({
      familyId,
      personId,
      actionBy,
    });
  }

  // ── Relationship Events ───────────────────────────────────────────

  emitRelationshipCreated(
    familyId: string,
    relationshipId: string,
    fromPersonId: string,
    toPersonId: string,
    type: string,
    actionBy: string,
  ) {
    this.gateway.emitRelationshipCreated({
      familyId,
      relationshipId,
      fromPersonId,
      toPersonId,
      type,
      actionBy,
    });
  }

  emitRelationshipDeleted(
    familyId: string,
    relationshipId: string,
    fromPersonId: string,
    toPersonId: string,
    type: string,
    actionBy: string,
  ) {
    this.gateway.emitRelationshipDeleted({
      familyId,
      relationshipId,
      fromPersonId,
      toPersonId,
      type,
      actionBy,
    });
  }

  // ── Notification Events ───────────────────────────────────────────

  emitNotificationNew(
    notificationId: string,
    userId: string,
    eventType: string,
    title: string,
    body: string,
    priority: string,
    familyId?: string,
  ) {
    this.gateway.emitNotificationNew({
      notificationId,
      userId,
      eventType,
      title,
      body,
      priority,
      familyId,
    });
  }

  // ── Invitation Events ─────────────────────────────────────────────

  emitInvitationCreated(
    invitationId: string,
    familyId: string,
    inviterId: string,
    recipientEmail?: string,
    recipientPhone?: string,
  ) {
    this.gateway.emitInvitationCreated({
      invitationId,
      familyId,
      inviterId,
      recipientEmail,
      recipientPhone,
      status: 'pending',
    });
  }

  emitInvitationAccepted(
    invitationId: string,
    familyId: string,
    inviterId: string,
  ) {
    this.gateway.emitInvitationAccepted({
      invitationId,
      familyId,
      inviterId,
      status: 'accepted',
    });
  }

  // ── Room Management ───────────────────────────────────────────────

  joinFamilyRoom(userId: string, familyId: string) {
    this.gateway.joinFamilyRoom(userId, familyId);
  }

  leaveFamilyRoom(userId: string, familyId: string) {
    this.gateway.leaveFamilyRoom(userId, familyId);
  }

  // ── Presence ──────────────────────────────────────────────────────

  isUserOnline(userId: string): boolean {
    return this.gateway.isUserOnline(userId);
  }

  getOnlineUserCount(): number {
    return this.gateway.getOnlineUserCount();
  }

  getOnlineUserIds(): string[] {
    return this.gateway.getOnlineUserIds();
  }
}
