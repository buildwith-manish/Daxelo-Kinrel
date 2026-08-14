/**
 * Daxelo-Kinrel — Family HTTP Controller
 * =======================================
 * Exposes FamilyService over REST. Per spec §10 the auto-detect workflow
 * is one round-trip: POST /relationships/detect returns the detected term
 * + signature + (if applicable) the missing fundamental edge the user
 * must confirm before storage.
 *
 * Endpoints:
 *   POST   /families                       create a family
 *   GET    /families/:id                   get family by id
 *   POST   /families/:id/persons           add a person
 *   GET    /families/:id/tree              build enriched tree (spec §3)
 *   GET    /families/:id/kinship           resolve kinship label A→B (spec §7, §14)
 *   POST   /families/:id/infer-spouse      spec §9 — returns suggestion, does NOT persist
 *   POST   /families/:id/confirm-spouse    spec §9.2 — persists inferred spouse edge
 */

import { Body, Controller, Get, Param, Post, Query, BadRequestException, NotFoundException } from "@nestjs/common";
import { FamilyService } from "./family.service";
import {
  CreateFamilyDto, CreatePersonDto, GetTreeDto,
  ResolveKinshipDto, InferSpouseDto,
} from "./family.dto";

@Controller("families")
export class FamilyController {
  constructor(private readonly family: FamilyService) {}

  @Post()
  async createFamily(@Body() dto: CreateFamilyDto) {
    return this.family.createFamily(dto.name);
  }

  @Get(":id")
  async getFamily(@Param("id") id: string) {
    const f = await this.family.prismaFamilyFind(id);
    if (!f) throw new NotFoundException("Family not found");
    return f;
  }

  @Post(":id/persons")
  async addPerson(@Param("id") id: string, @Body() dto: CreatePersonDto) {
    return this.family.addPerson(id, {
      fullName: dto.fullName,
      gender: dto.gender as any,
      birthDate: dto.birthDate ? new Date(dto.birthDate) : undefined,
      deathDate: dto.deathDate ? new Date(dto.deathDate) : undefined,
      isAdopted: dto.isAdopted,
    });
  }

  @Get(":id/tree")
  async getTree(
    @Param("id") id: string,
    @Query("rootPersonId") rootPersonId: string,
    @Query("locale") locale: string = "en",
    @Query("upDepth") upDepth?: string,
    @Query("downDepth") downDepth?: string,
  ) {
    if (!rootPersonId) throw new BadRequestException("rootPersonId query param required");
    return this.family.getTree(id, rootPersonId, locale, {
      upDepth: upDepth ? parseInt(upDepth, 10) : undefined,
      downDepth: downDepth ? parseInt(downDepth, 10) : undefined,
    });
  }

  @Get(":id/kinship")
  async resolveKinship(
    @Param("id") id: string,
    @Query("personAId") personAId: string,
    @Query("personBId") personBId: string,
    @Query("locale") locale: string = "en",
  ) {
    if (!personAId || !personBId) {
      throw new BadRequestException("personAId and personBId query params required");
    }
    return this.family.resolveKinshipLabel(id, personAId, personBId, locale);
  }

  @Post(":id/infer-spouse")
  async inferSpouse(@Param("id") id: string, @Body() dto: Omit<InferSpouseDto, "familyId">) {
    return this.family.inferSpouse(id, dto.personAId, dto.personBId);
  }

  @Post(":id/confirm-spouse")
  async confirmSpouse(@Param("id") id: string, @Body() dto: Omit<InferSpouseDto, "familyId">) {
    return this.family.confirmSpouseInference(id, dto.personAId, dto.personBId);
  }
}
