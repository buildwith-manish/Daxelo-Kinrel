/**
 * Socket event DTOs for WebSocket communication.
 * Used for type-safe event handling in the WebSocket gateway.
 */

/**
 * Event types emitted by the server
 */
export type ServerEvent =
  | 'family:updated'
  | 'person:created'
  | 'person:updated'
  | 'person:deleted'
  | 'relationship:created'
  | 'relationship:deleted'
  | 'graph:updated'
  | 'notification:new'
  | 'invitation:created'
  | 'invitation:accepted'
  | 'user:online'
  | 'user:offline';

/**
 * Payload for family:updated events
 */
export interface FamilyUpdatedPayload {
  familyId: string;
  updatedBy: string;
  changes: Record<string, unknown>;
}

/**
 * Payload for person:created / person:updated / person:deleted events
 */
export interface PersonEventPayload {
  familyId: string;
  personId: string;
  personName?: string;
  actionBy: string;
  data?: Record<string, unknown>;
}

/**
 * Payload for relationship:created / relationship:deleted events
 */
export interface RelationshipEventPayload {
  familyId: string;
  relationshipId: string;
  fromPersonId: string;
  toPersonId: string;
  type: string;
  actionBy: string;
}

/**
 * Payload for graph:updated events
 */
export interface GraphUpdatedPayload {
  familyId: string;
  changeType: 'person' | 'relationship';
  changedBy: string;
}

/**
 * Payload for notification:new events
 */
export interface NotificationNewPayload {
  notificationId: string;
  userId: string;
  eventType: string;
  title: string;
  body: string;
  priority: string;
  familyId?: string;
}

/**
 * Payload for invitation:created / invitation:accepted events
 */
export interface InvitationEventPayload {
  invitationId: string;
  familyId: string;
  inviterId: string;
  recipientEmail?: string;
  recipientPhone?: string;
  status: string;
}

/**
 * Payload for user:online / user:offline events
 */
export interface UserPresencePayload {
  userId: string;
  status: 'online' | 'offline';
  timestamp: Date;
}

/**
 * Map of event names to their payload types
 */
export interface ServerEventMap {
  'family:updated': FamilyUpdatedPayload;
  'person:created': PersonEventPayload;
  'person:updated': PersonEventPayload;
  'person:deleted': PersonEventPayload;
  'relationship:created': RelationshipEventPayload;
  'relationship:deleted': RelationshipEventPayload;
  'graph:updated': GraphUpdatedPayload;
  'notification:new': NotificationNewPayload;
  'invitation:created': InvitationEventPayload;
  'invitation:accepted': InvitationEventPayload;
  'user:online': UserPresencePayload;
  'user:offline': UserPresencePayload;
}
