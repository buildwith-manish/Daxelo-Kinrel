/**
 * Daxelo-Kinrel — Root NestJS module.
 * Wires together all services + controllers per spec §18.
 */
import { Module } from "@nestjs/common";
import { PrismaService } from "./prisma/prisma.service";
import { KinshipService } from "./modules/kinship/kinship.service";
import { KinshipController } from "./modules/kinship/kinship.controller";
import { CanonicalIdService } from "./modules/kinship/canonical-id.service";
import { GraphEngineService } from "./modules/graph/graph-engine.service";
import { PathCanonicalizer } from "./modules/graph/path-canonicalizer";
import { GraphService } from "./modules/graph/graph.service";
import { RelationshipsService } from "./modules/relationships/relationships.service";
import { RelationshipsController } from "./modules/relationships/relationships.controller";
import { RelationshipValidator } from "./modules/relationships/relationship.validator";
import { FamilyService } from "./modules/family/family.service";
import { FamilyController } from "./modules/family/family.controller";
import { SignatureCacheService } from "./cache/signature-cache.service";
import { HealthController } from "./modules/health/health.controller";

@Module({
  imports: [],
  controllers: [FamilyController, RelationshipsController, KinshipController, HealthController],
  providers: [
    PrismaService,
    // Cache (spec §13)
    SignatureCacheService,
    // Kinship module (spec §18 — kinship/)
    KinshipService,
    CanonicalIdService,
    // Graph module (spec §18 — graph/)
    GraphEngineService,
    PathCanonicalizer,
    GraphService,
    // Relationships module (spec §18 — relationships/)
    RelationshipsService,
    RelationshipValidator,
    // Family orchestration (spec §18 — family/)
    FamilyService,
  ],
  exports: [
    FamilyService,
    RelationshipsService,
    GraphEngineService,
    KinshipService,
    CanonicalIdService,
    SignatureCacheService,
    PrismaService,
  ],
})
export class AppModule {}

