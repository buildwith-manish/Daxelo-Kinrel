// server/src/aura/role-glyph.service.ts
//
// AURA — Role Glyph Service
//
// Classifies each family member into one of 6 roles based on their graph
// position, then upserts a MemberAuraRole row per member.
//
// Roles:
//   root       — the oldest ancestor (matches metrics.rootNodeId)
//   anchor     — highest betweenness centrality (the "bridge" of the family)
//   bridge     — 2nd–4th highest betweenness (secondary bridges)
//   weaver     — high degree (≥4) connecting many members, not root/anchor/bridge
//   leaf       — terminal nodes (degree ≤ 1) or youngest generation
//   twin_node  — members at the same generation with the same degree signature
//
// The role → glyph shape mapping is fixed and language-agnostic.
// The glyph color is derived from the AURA palette (primary/secondary/accent).

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { GraphMetrics } from './graph-metrics';
import { AuraSymbolParameters } from './aura-parameter-generator.service';

export type RoleKey = 'root' | 'anchor' | 'bridge' | 'weaver' | 'leaf' | 'twin_node';

export interface MemberRole {
  memberId: string;
  roleKey: RoleKey;
  betweennessScore: number;
  degreeCount: number;
  generationIndex: number;
  glyphShape: string;
  glyphColorHex: string;
}

// Glyph shape for each role (visual treatment hint for the Flutter renderer)
const ROLE_GLYPH_SHAPES: Record<RoleKey, string> = {
  root:       'deep_anchor',
  anchor:     'bridge_cross',
  bridge:     'two_circle_intersection',
  weaver:     'outward_spiral',
  leaf:       'open_petal',
  twin_node:  'mirror_glyph',
};

@Injectable()
export class RoleGlyphService {
  private readonly logger = new Logger(RoleGlyphService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Compute role classifications for every member and upsert MemberAuraRole rows.
   *
   * Strategy:
   *   1. Sort all nodes by betweenness desc.
   *   2. anchor = top betweenness node (if score > 0.05).
   *   3. bridges = 2nd–4th highest betweenness (if score > 0.02).
   *   4. root = metrics.rootNodeId.
   *   5. twin_nodes = members sharing (generation, degree) signature with another member.
   *   6. leaves = degree ≤ 1 OR youngest generation.
   *   7. everyone else with degree ≥ 4 = weaver; otherwise leaf.
   *
   * Priority order (first match wins): root → anchor → bridge → twin_node → leaf → weaver.
   */
  async computeAndSaveRoles(
    familyId: string,
    metrics: GraphMetrics,
    params: AuraSymbolParameters,
  ): Promise<void> {
    const nodeIds = Object.keys(metrics.betweennessMap);
    if (nodeIds.length === 0) {
      this.logger.debug(`Family ${familyId} has 0 members — skipping role computation`);
      return;
    }

    // ── Identify special nodes ──────────────────────────────────────────

    // Sort by betweenness descending
    const sortedByBetweenness = [...nodeIds].sort(
      (a, b) => (metrics.betweennessMap[b] ?? 0) - (metrics.betweennessMap[a] ?? 0),
    );

    const anchorId = sortedByBetweenness[0]; // top betweenness
    const bridgeIds = new Set(sortedByBetweenness.slice(1, 4)); // 2nd–4th = bridges

    // Find leaf nodes: degree === 1 or youngest generation
    const maxGeneration = Math.max(...Object.values(metrics.generationMap));
    const leafNodes = new Set(
      nodeIds.filter(
        (id) =>
          (metrics.degreeMap[id] ?? 0) <= 1 ||
          (metrics.generationMap[id] ?? 0) === maxGeneration,
      ),
    );

    // Find twin nodes: members sharing (generation, degree) signature
    const twinNodes = this.findTwinNodes(nodeIds, metrics);

    // ── Classify every member ───────────────────────────────────────────
    const roles: MemberRole[] = nodeIds.map((memberId) => {
      const generation = metrics.generationMap[memberId] ?? 0;
      const betweenness = metrics.betweennessMap[memberId] ?? 0;
      const degree = metrics.degreeMap[memberId] ?? 0;

      let roleKey: RoleKey;
      if (memberId === metrics.rootNodeId) {
        roleKey = 'root';
      } else if (memberId === anchorId && betweenness > 0.05) {
        roleKey = 'anchor';
      } else if (bridgeIds.has(memberId) && betweenness > 0.02) {
        roleKey = 'bridge';
      } else if (twinNodes.has(memberId)) {
        roleKey = 'twin_node';
      } else if (leafNodes.has(memberId)) {
        roleKey = 'leaf';
      } else {
        // Weaver: high degree, connects many — but not root/anchor/bridge
        roleKey = degree >= 4 ? 'weaver' : 'leaf';
      }

      return {
        memberId,
        roleKey,
        betweennessScore: betweenness,
        degreeCount: degree,
        generationIndex: generation,
        glyphShape: ROLE_GLYPH_SHAPES[roleKey],
        glyphColorHex: this.roleColor(roleKey, params),
      };
    });

    // ── Batch upsert all member roles ───────────────────────────────────
    // Prisma doesn't support bulk upsert natively, so we use Promise.all
    // with individual upserts. For families < 500 members this is fast enough.
    await Promise.all(
      roles.map((role) =>
        this.prisma.memberAuraRole.upsert({
          where: {
            familyId_memberId: { familyId, memberId: role.memberId },
          },
          create: {
            familyId,
            memberId: role.memberId,
            roleKey: role.roleKey,
            betweennessScore: role.betweennessScore,
            degreeCount: role.degreeCount,
            generationIndex: role.generationIndex,
            glyphShape: role.glyphShape,
            glyphColorHex: role.glyphColorHex,
            computedAt: new Date(),
          },
          update: {
            roleKey: role.roleKey,
            betweennessScore: role.betweennessScore,
            degreeCount: role.degreeCount,
            generationIndex: role.generationIndex,
            glyphShape: role.glyphShape,
            glyphColorHex: role.glyphColorHex,
            computedAt: new Date(),
          },
        }),
      ),
    );

    // ── Delete stale roles for members no longer in the family ──────────
    // (e.g., if a member was deleted since the last AURA computation)
    const roleCounts = await this.prisma.memberAuraRole.count({
      where: { familyId },
    });
    if (roleCounts > roles.length) {
      await this.prisma.memberAuraRole.deleteMany({
        where: {
          familyId,
          memberId: { notIn: roles.map((r) => r.memberId) },
        },
      });
      this.logger.debug(
        `Deleted ${roleCounts - roles.length} stale MemberAuraRole rows for family ${familyId}`,
      );
    }

    this.logger.log(
      `Computed ${roles.length} member roles for family ${familyId} ` +
        `(root=${roles.filter((r) => r.roleKey === 'root').length}, ` +
        `anchor=${roles.filter((r) => r.roleKey === 'anchor').length}, ` +
        `bridge=${roles.filter((r) => r.roleKey === 'bridge').length}, ` +
        `weaver=${roles.filter((r) => r.roleKey === 'weaver').length}, ` +
        `leaf=${roles.filter((r) => r.roleKey === 'leaf').length}, ` +
        `twin_node=${roles.filter((r) => r.roleKey === 'twin_node').length})`,
    );
  }

  /**
   * Find twin nodes: members at the same generation index with the same degree.
   * Returns a Set of member IDs that share a (generation, degree) signature
   * with at least one other member.
   */
  private findTwinNodes(
    nodeIds: string[],
    metrics: GraphMetrics,
  ): Set<string> {
    const signature = (id: string) =>
      `${metrics.generationMap[id] ?? 0}_${metrics.degreeMap[id] ?? 0}`;

    const sigCounts: Record<string, string[]> = {};
    for (const id of nodeIds) {
      const sig = signature(id);
      if (!sigCounts[sig]) sigCounts[sig] = [];
      sigCounts[sig].push(id);
    }

    const twins = new Set<string>();
    for (const group of Object.values(sigCounts)) {
      if (group.length >= 2) {
        group.forEach((id) => twins.add(id));
      }
    }
    return twins;
  }

  /**
   * Map a role to a color from the AURA palette.
   * Root/Weaver use primary, Anchor uses secondary, Bridge/Twin use accent,
   * Leaf uses accent (terminal nodes blend into the outer ring).
   */
  private roleColor(roleKey: RoleKey, params: AuraSymbolParameters): string {
    const roleColorMap: Record<RoleKey, string> = {
      root:       params.primaryColorHex,
      anchor:     params.secondaryColorHex,
      bridge:     params.accentColorHex,
      weaver:     params.primaryColorHex,
      leaf:       params.accentColorHex,
      twin_node:  params.secondaryColorHex,
    };
    return roleColorMap[roleKey];
  }
}
