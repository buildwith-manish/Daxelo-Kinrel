/**
 * KINREL Mirror — Data Repository Layer
 * Base repository with common CRUD operations and query building.
 */

import { db } from '@/lib/db';
import { Prisma } from '@prisma/client';

export interface PaginationOptions {
  page?: number;
  limit?: number;
  cursor?: string;
  sort?: string;
  order?: 'asc' | 'desc';
}

export interface PaginatedResult<T> {
  data: T[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    hasMore: boolean;
    totalPages: number;
  };
}

export abstract class BaseRepository<TModel, TCreate, TUpdate> {
  protected abstract getModel(): any;

  async findById(id: string): Promise<TModel | null> {
    return this.getModel().findUnique({ where: { id } });
  }

  async findMany(options?: {
    where?: Record<string, unknown>;
    include?: Record<string, unknown>;
    pagination?: PaginationOptions;
  }): Promise<PaginatedResult<TModel>> {
    const page = options?.pagination?.page ?? 1;
    const limit = Math.min(options?.pagination?.limit ?? 20, 100);
    const sort = options?.pagination?.sort ?? 'createdAt';
    const order = options?.pagination?.order ?? 'desc';

    const [data, total] = await Promise.all([
      this.getModel().findMany({
        where: options?.where,
        include: options?.include,
        orderBy: { [sort]: order },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.getModel().count({ where: options?.where }),
    ]);

    return {
      data,
      pagination: {
        page,
        limit,
        total,
        hasMore: page * limit < total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  async create(data: TCreate): Promise<TModel> {
    return this.getModel().create({ data });
  }

  async update(id: string, data: TUpdate): Promise<TModel> {
    return this.getModel().update({ where: { id }, data });
  }

  async delete(id: string): Promise<TModel> {
    return this.getModel().delete({ where: { id } });
  }

  async count(where?: Record<string, unknown>): Promise<number> {
    return this.getModel().count({ where });
  }

  async exists(id: string): Promise<boolean> {
    const record = await this.getModel().findUnique({ where: { id }, select: { id: true } });
    return !!record;
  }
}

// ── Family Repository ─────────────────────────────────────────────

export class FamilyRepository extends BaseRepository<any, any, any> {
  protected getModel() { return db.family; }

  async findByUserId(userId: string) {
    const memberships = await db.familyMember.findMany({
      where: { userId },
      include: { family: { include: { _count: { select: { members: true, persons: true } } } } },
      orderBy: { joinedAt: 'desc' },
    });
    return memberships.map(m => ({
      id: m.family.id,
      name: m.family.name,
      description: m.family.description,
      primaryLanguage: m.family.primaryLanguage,
      gotra: m.family.gotra,
      originVillage: m.family.originVillage,
      role: m.role,
      memberCount: m.family._count.members,
      personCount: m.family._count.persons,
      createdAt: m.family.createdAt,
      updatedAt: m.family.updatedAt,
    }));
  }

  async findWithMembership(familyId: string, userId: string) {
    const [family, membership] = await Promise.all([
      db.family.findUnique({ where: { id: familyId }, include: { _count: { select: { members: true, persons: true } } } }),
      db.familyMember.findUnique({ where: { familyId_userId: { familyId, userId } } }),
    ]);
    if (!family || !membership) return null;
    return { family, membership };
  }
}

export const familyRepo = new FamilyRepository();

// ── Person Repository ─────────────────────────────────────────────

export class PersonRepository extends BaseRepository<any, any, any> {
  protected getModel() { return db.person; }

  async findByFamily(familyId: string, options?: PaginationOptions & { search?: string; deceased?: boolean; includeRelationships?: boolean }) {
    const where: any = { familyId, deletedAt: null };
    if (options?.deceased === true) where.isDeceased = true;
    if (options?.deceased === false) where.isDeceased = false;
    if (options?.search) {
      where.OR = [
        { name: { contains: options.search } },
        { relationship: { contains: options.search } },
      ];
    }
    return this.findMany({
      where,
      include: options?.includeRelationships ? { relationshipsFrom: true, relationshipsTo: true } : undefined,
      pagination: options,
    });
  }
}

export const personRepo = new PersonRepository();

// ── Relationship Repository ───────────────────────────────────────

const INVERSE_RELATIONSHIP_MAP: Record<string, string> = {
  father: 'son', mother: 'son', son: 'father', daughter: 'mother',
  husband: 'wife', wife: 'husband', elder_brother: 'younger_brother',
  younger_brother: 'elder_brother', elder_sister: 'younger_sister',
  younger_sister: 'elder_sister', brother: 'brother', sister: 'sister',
  paternal_grandfather: 'grandson', paternal_grandmother: 'grandson',
  maternal_grandfather: 'grandson', maternal_grandmother: 'grandson',
  husbands_father: 'sons_wife', husbands_mother: 'sons_wife',
  wives_father: 'daughters_husband', wives_mother: 'daughters_husband',
  sons_wife: 'husbands_father', daughters_husband: 'wives_father',
};

export function getInverseRelationship(type: string): string {
  return INVERSE_RELATIONSHIP_MAP[type] || 'related_to';
}

export class RelationshipRepository extends BaseRepository<any, any, any> {
  protected getModel() { return db.relationship; }

  async createBidirectional(familyId: string, fromPersonId: string, toPersonId: string, type: string) {
    const inverseType = getInverseRelationship(type);
    return db.$transaction(async (tx) => {
      const rel = await tx.relationship.create({
        data: { familyId, fromPersonId, toPersonId, type, direction: 'from' },
        include: { fromPerson: true, toPerson: true },
      });
      const existingInverse = await tx.relationship.findFirst({
        where: { familyId, fromPersonId: toPersonId, toPersonId: fromPersonId, type: inverseType },
      });
      if (!existingInverse) {
        await tx.relationship.create({ data: { familyId, fromPersonId: toPersonId, toPersonId: fromPersonId, type: inverseType, direction: 'from' } });
      }
      return rel;
    });
  }

  async deleteBidirectional(relationshipId: string, familyId: string) {
    const rel = await db.relationship.findFirst({ where: { id: relationshipId, familyId } });
    if (!rel) return null;
    const inverseType = getInverseRelationship(rel.type);
    await db.$transaction(async (tx) => {
      await tx.relationship.delete({ where: { id: relationshipId } });
      const inverse = await tx.relationship.findFirst({
        where: { familyId, fromPersonId: rel.toPersonId, toPersonId: rel.fromPersonId, type: inverseType },
      });
      if (inverse) await tx.relationship.delete({ where: { id: inverse.id } });
    });
    return rel;
  }
}

export const relationshipRepo = new RelationshipRepository();

// ── User Repository ───────────────────────────────────────────────

export class UserRepository extends BaseRepository<any, any, any> {
  protected getModel() { return db.user; }

  async findByEmail(email: string) {
    return db.user.findUnique({ where: { email } });
  }

  async findByEmailWithAuth(email: string) {
    return db.user.findUnique({
      where: { email },
      select: { id: true, email: true, name: true, role: true, passwordHash: true, preferredLanguage: true },
    });
  }
}

export const userRepo = new UserRepository();

// ── Notification Repository ───────────────────────────────────────

export class NotificationRepository extends BaseRepository<any, any, any> {
  protected getModel() { return db.notification; }

  async findByUser(userId: string, options?: { limit?: number; offset?: number; read?: boolean }) {
    const where: any = { userId };
    if (options?.read !== undefined) where.read = options.read;
    const [notifications, unreadCount] = await Promise.all([
      db.notification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: Math.min(options?.limit ?? 20, 100),
        skip: options?.offset ?? 0,
        include: { updates: { orderBy: { createdAt: 'desc' } } },
      }),
      db.notification.count({ where: { userId, read: false } }),
    ]);
    return { notifications, unreadCount };
  }

  async markRead(userId: string, notificationIds?: string[]) {
    const where: any = { userId, read: false };
    if (notificationIds?.length) where.id = { in: notificationIds };
    return db.notification.updateMany({ where, data: { read: true, readAt: new Date() } });
  }
}

export const notificationRepo = new NotificationRepository();
