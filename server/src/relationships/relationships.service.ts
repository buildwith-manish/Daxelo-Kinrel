import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class RelationshipsService {
  constructor(private readonly prisma: PrismaService) {}

  async listRelationships(userId: string, familyId: string) {
    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    const relationships = await this.prisma.relationship.findMany({
      where: { familyId, isActive: true },
      include: {
        fromPerson: true,
        toPerson: true,
      },
    });

    return relationships;
  }

  async createRelationship(userId: string, familyId: string, data: any) {
    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    // Verify both persons exist in the family
    const fromPerson = await this.prisma.person.findFirst({
      where: { id: data.fromPersonId, familyId, deletedAt: null },
    });
    const toPerson = await this.prisma.person.findFirst({
      where: { id: data.toPersonId, familyId, deletedAt: null },
    });

    if (!fromPerson || !toPerson) {
      throw new NotFoundException('One or both persons not found in this family');
    }

    const relationship = await this.prisma.relationship.create({
      data: {
        familyId,
        fromPersonId: data.fromPersonId,
        toPersonId: data.toPersonId,
        type: data.type,
        relationshipKey: data.relationshipKey || null,
        direction: data.direction || null,
        label: data.label || null,
      },
    });

    // Update family relationship count / last activity
    await this.prisma.family.update({
      where: { id: familyId },
      data: { lastActivityAt: new Date() },
    });

    return relationship;
  }

  async deleteRelationship(userId: string, relationshipId: string) {
    const relationship = await this.prisma.relationship.findUnique({
      where: { id: relationshipId },
    });
    if (!relationship) {
      throw new NotFoundException('Relationship not found');
    }

    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: relationship.familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    // Soft delete by setting isActive to false
    await this.prisma.relationship.update({
      where: { id: relationshipId },
      data: { isActive: false },
    });

    return { message: 'Relationship deleted', id: relationshipId };
  }
}
