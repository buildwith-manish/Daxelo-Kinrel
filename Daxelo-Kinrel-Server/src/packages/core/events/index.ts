/**
 * KINREL Mirror — Core Event System
 * Typed event bus for decoupled communication between modules.
 */

export type EventHandler<T = unknown> = (payload: T) => void | Promise<void>;

export interface EventMap {
  'user.registered': { userId: string; email: string; name: string };
  'family.created': { familyId: string; name: string; creatorId: string };
  'family.updated': { familyId: string; changedFields: string[]; updatedBy: string };
  'family.deleted': { familyId: string; deletedBy: string };
  'person.created': { personId: string; familyId: string; name: string; relationship: string };
  'person.updated': { personId: string; familyId: string; changedFields: string[] };
  'person.deleted': { personId: string; familyId: string; softDelete: boolean };
  'relationship.created': { relationshipId: string; familyId: string; fromPersonId: string; toPersonId: string; type: string };
  'relationship.deleted': { relationshipId: string; familyId: string };
  'notification.sent': { notificationId: string; userId: string; channels: string[] };
  'moderation.case_created': { caseId: string; category: string; priority: string };
  'moderation.action_taken': { caseId: string; action: string; actorType: string };
  'api_key.created': { keyId: string; userId: string; tier: string };
  'api_key.revoked': { keyId: string; userId: string; reason: string };
  'support.ticket_created': { ticketId: string; userId: string; category: string; severity: string };
  'community.joined': { communityId: string; userId: string; role: string };
  'invitation.sent': { invitationId: string; familyId: string; channel: string };
  'invitation.accepted': { invitationId: string; familyId: string; userId: string };
}

type EventKey = keyof EventMap;

class EventBus {
  private handlers = new Map<EventKey, Set<EventHandler>>();

  on<K extends EventKey>(event: K, handler: EventHandler<EventMap[K]>): () => void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Set());
    }
    const set = this.handlers.get(event)!;
    set.add(handler as EventHandler);

    // Return unsubscribe function
    return () => {
      set.delete(handler as EventHandler);
      if (set.size === 0) {
        this.handlers.delete(event);
      }
    };
  }

  async emit<K extends EventKey>(event: K, payload: EventMap[K]): Promise<void> {
    const handlers = this.handlers.get(event);
    if (!handlers || handlers.size === 0) return;

    const promises: (void | Promise<void>)[] = [];
    for (const handler of handlers) {
      try {
        const result = handler(payload);
        if (result instanceof Promise) {
          promises.push(result.catch((err) => {
            console.error(`[EventBus] Error in handler for "${event}":`, err);
          }));
        }
      } catch (err) {
        console.error(`[EventBus] Error in handler for "${event}":`, err);
      }
    }

    await Promise.all(promises);
  }

  removeAllHandlers(event?: EventKey): void {
    if (event) {
      this.handlers.delete(event);
    } else {
      this.handlers.clear();
    }
  }

  handlerCount(event?: EventKey): number {
    if (event) return this.handlers.get(event)?.size ?? 0;
    let total = 0;
    for (const set of this.handlers.values()) total += set.size;
    return total;
  }
}

export const eventBus = new EventBus();
