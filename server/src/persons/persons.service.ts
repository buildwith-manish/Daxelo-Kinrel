import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class PersonsService {
  constructor(private readonly prisma: PrismaService) {}

  async listPersons(userId: string, familyId: string) {
    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });

    return persons;
  }

  async addPerson(userId: string, familyId: string, data: any) {
    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    const person = await this.prisma.person.create({
      data: {
        name: data.name,
        familyId,
        gender: data.gender || null,
        birthYear: data.birthYear || null,
        isAnchor: data.isAnchor || false,
        generationIndex: data.generationIndex || null,
        city: data.city || null,
        gotra: data.gotra || null,
        isDeceased: data.isDeceased || false,
        privacyLevel: data.privacyLevel || 'public',
        occupation: data.occupation || null,
        notes: data.notes || null,
        sideOfFamily: data.sideOfFamily || null,
        photoUrl: data.photoUrl || null,
        dateOfBirth: data.dateOfBirth || null,
      },
    });

    // Update family member count
    const count = await this.prisma.person.count({
      where: { familyId, deletedAt: null },
    });
    await this.prisma.family.update({
      where: { id: familyId },
      data: { memberCount: count },
    });

    return person;
  }

  async updatePerson(userId: string, personId: string, data: any) {
    const person = await this.prisma.person.findUnique({
      where: { id: personId },
    });
    if (!person) {
      throw new NotFoundException('Person not found');
    }

    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: person.familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    const allowedFields = [
      'name', 'gender', 'birthYear', 'isAnchor', 'generationIndex',
      'city', 'gotra', 'isDeceased', 'privacyLevel', 'occupation',
      'notes', 'sideOfFamily', 'photoUrl', 'dateOfBirth',
    ];
    const updateData: any = {};
    for (const field of allowedFields) {
      if (data[field] !== undefined) {
        updateData[field] = data[field];
      }
    }

    return this.prisma.person.update({
      where: { id: personId },
      data: updateData,
    });
  }

  async deletePerson(userId: string, personId: string) {
    const person = await this.prisma.person.findUnique({
      where: { id: personId },
    });
    if (!person) {
      throw new NotFoundException('Person not found');
    }

    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: person.familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    // Soft delete
    const deleted = await this.prisma.person.update({
      where: { id: personId },
      data: { deletedAt: new Date() },
    });

    // Update family member count
    const count = await this.prisma.person.count({
      where: { familyId: person.familyId, deletedAt: null },
    });
    await this.prisma.family.update({
      where: { id: person.familyId },
      data: { memberCount: count },
    });

    return { message: 'Person deleted', id: personId };
  }
}
