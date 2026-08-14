/**
 * Daxelo-Kinrel — Relationship HTTP Controller
 * =============================================
 * Endpoints:
 *   POST   /relationships              create fundamental edge (spec §8, §12)
 *   POST   /relationships/detect       auto-detect workflow (spec §10)
 *   GET    /relationships?familyId=    list edges in a family
 *   DELETE /relationships/:id          delete edge (invalidates caches)
 */

import { Body, Controller, Delete, Get, Param, Post, Query, BadRequestException } from "@nestjs/common";
import { RelationshipsService } from "./relationships.service";
import { CreateRelationshipDto, DetectRelationshipDto } from "../family/family.dto";

@Controller("relationships")
export class RelationshipsController {
  constructor(private readonly relationships: RelationshipsService) {}

  @Post()
  async create(@Body() dto: CreateRelationshipDto) {
    if (!dto.edgeType && !dto.detectedTerm) {
      throw new BadRequestException("Either edgeType or detectedTerm must be provided");
    }
    try {
      return await this.relationships.create({
        familyId: dto.familyId,
        personAId: dto.personAId,
        personBId: dto.personBId,
        edgeType: dto.edgeType as any,
        detectedTerm: dto.detectedTerm,
        locale: dto.locale ?? "en",
        temporal: dto.temporal as any,
        isInferred: dto.isInferred,
      });
    } catch (e: any) {
      throw new BadRequestException(e.message);
    }
  }

  @Post("detect")
  async detect(@Body() dto: DetectRelationshipDto) {
    return this.relationships.autoDetect(dto.familyId, dto.personAId, dto.personBId, dto.locale ?? "en");
  }

  @Get()
  async list(@Query("familyId") familyId: string) {
    if (!familyId) throw new BadRequestException("familyId query param required");
    return this.relationships.list(familyId);
  }

  @Delete(":id")
  async delete(@Param("id") id: string) {
    return this.relationships.delete(id);
  }
}
