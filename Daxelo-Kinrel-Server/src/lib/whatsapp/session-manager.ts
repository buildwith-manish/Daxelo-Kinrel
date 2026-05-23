// DAXELO KINREL — WhatsApp Session Manager
// Pack 04: WhatsApp Platform
// Memory-backed session store with 30-minute TTL and periodic cleanup

// ── Session State Enum ──────────────────────────────────────────────

export enum SessionState {
  IDLE = 'idle',
  ADDING_PERSON = 'adding_person',
  SELECTING_PERSON = 'selecting_person',
  INVITING_FAMILY = 'inviting_family',
  LANGUAGE_SELECT = 'language_select',
}

// ── Bot Session Interface ───────────────────────────────────────────

export interface BotSession {
  phone: string
  state: SessionState
  data: Record<string, unknown>
  updatedAt: Date
}

// ── Internal Storage Entry ──────────────────────────────────────────

interface SessionEntry {
  session: BotSession
  expiresAt: number // Unix timestamp in ms
}

// ── Constants ───────────────────────────────────────────────────────

const SESSION_TTL_MS = 30 * 60 * 1000 // 30 minutes
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000 // 5 minutes

// ── Session Manager ─────────────────────────────────────────────────

export class SessionManager {
  private readonly store: Map<string, SessionEntry> = new Map()
  private cleanupTimer: ReturnType<typeof setInterval> | null = null

  constructor() {
    this.startCleanup()
  }

  // ── Get or Create Session ────────────────────────────────────────

  async getOrCreate(phone: string): Promise<BotSession> {
    const entry = this.store.get(phone)

    if (entry && entry.expiresAt > Date.now()) {
      // Session is valid — touch the updatedAt field
      entry.session.updatedAt = new Date()
      return { ...entry.session }
    }

    // Session expired or not found — create a new one
    const session: BotSession = {
      phone,
      state: SessionState.IDLE,
      data: {},
      updatedAt: new Date(),
    }

    this.store.set(phone, {
      session,
      expiresAt: Date.now() + SESSION_TTL_MS,
    })

    return { ...session }
  }

  // ── Update Session ───────────────────────────────────────────────

  async update(
    phone: string,
    updates: Partial<BotSession>,
  ): Promise<BotSession> {
    const existing = await this.getOrCreate(phone)

    const updated: BotSession = {
      ...existing,
      ...updates,
      phone: existing.phone, // phone is immutable
      updatedAt: new Date(),
    }

    this.store.set(phone, {
      session: updated,
      expiresAt: Date.now() + SESSION_TTL_MS,
    })

    return { ...updated }
  }

  // ── Set State ────────────────────────────────────────────────────

  async setState(
    phone: string,
    state: SessionState,
    data?: Record<string, unknown>,
  ): Promise<BotSession> {
    const existing = await this.getOrCreate(phone)

    return this.update(phone, {
      state,
      data: data ?? existing.data,
    })
  }

  // ── Reset Session ────────────────────────────────────────────────

  async reset(phone: string): Promise<BotSession> {
    this.store.delete(phone)
    return this.getOrCreate(phone)
  }

  // ── Delete Session ───────────────────────────────────────────────

  async delete(phone: string): Promise<void> {
    this.store.delete(phone)
  }

  // ── Get Active Session Count ─────────────────────────────────────

  getActiveSessionCount(): number {
    const now = Date.now()
    let count = 0
    for (const entry of this.store.values()) {
      if (entry.expiresAt > now) count++
    }
    return count
  }

  // ── Cleanup Expired Sessions ─────────────────────────────────────

  private cleanup(): void {
    const now = Date.now()
    for (const [key, entry] of this.store.entries()) {
      if (entry.expiresAt <= now) {
        this.store.delete(key)
      }
    }
  }

  // ── Start Periodic Cleanup ───────────────────────────────────────

  private startCleanup(): void {
    if (this.cleanupTimer) return
    this.cleanupTimer = setInterval(() => {
      this.cleanup()
    }, CLEANUP_INTERVAL_MS)

    // Allow the process to exit even if the timer is running
    if (this.cleanupTimer.unref) {
      this.cleanupTimer.unref()
    }
  }

  // ── Stop Cleanup ─────────────────────────────────────────────────

  stopCleanup(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer)
      this.cleanupTimer = null
    }
  }
}

// ── Singleton Export ────────────────────────────────────────────────

export const sessionManager = new SessionManager()
