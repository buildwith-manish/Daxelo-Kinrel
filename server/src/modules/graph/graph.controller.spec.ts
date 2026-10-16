// server/src/modules/graph/graph.controller.spec.ts
//
// Unit tests for the graph controller's family-membership enforcement
// on the /graph/:familyId/tree and /graph/:familyId/path endpoints.
//
// SECURITY (audit F-02 / F-03): These two endpoints previously called
// `resolveRootPersonId` for "auth", which performs no membership check.
// The fix routes them through `graphService.assertMember(...)` — the same
// `requireFamilyMember` path used by every other graph endpoint. These
// tests prove:
//   1. A member of the family can still call both endpoints and gets the
//      same data as before (response shape unchanged).
//   2. A signed-in user from a different family (or any non-member of a
//      private family) is denied — `assertMember` throws and the graph
//      data methods are never called.
//   3. An unauthenticated request is denied at the JwtAuthGuard layer
//      (verified indirectly: the controller never gets a `userId` to
//      pass to `assertMember`, so the guard would 401 before the
//      controller body runs — we simulate this by asserting the
//      controller methods never proceed when `assertMember` rejects).
//
// JwtAuthGuard itself is part of `@nestjs/passport` and is exercised
// end-to-end in the families/members suites; we don't re-test it here.

import { Test, TestingModule } from '@nestjs/testing';
import { NotFoundException, ForbiddenException, BadRequestException } from '@nestjs/common';
import { GraphController } from './graph.controller';
import { GraphService, EnrichedGraphResult } from './graph.service';
import { GraphEngineService } from './graph-engine.service';

// ── Mocks ─────────────────────────────────────────────────────────────

const makeGraphServiceMock = () => ({
  // The security guard. assertMember is the public wrapper around the
  // private requireFamilyMember. We control its behaviour per-test.
  assertMember: jest.fn(),
  // Other service methods that the controller delegates to. Their return
  // values are not the focus of these tests — we just need to assert they
  // ARE or ARE NOT called depending on the membership outcome.
  resolveRootPersonId: jest.fn(),
  getTree: jest.fn(),
  getEnrichedGraph: jest.fn().mockResolvedValue({} as EnrichedGraphResult),
  computeLayout: jest.fn(),
  getMemberDetails: jest.fn(),
  getMembersByGeneration: jest.fn(),
  getGraph: jest.fn(),
});

const makeGraphEngineMock = () => ({
  findPath: jest.fn(),
  getAllRelationships: jest.fn(),
  invalidateCache: jest.fn(),
});

describe('GraphController — membership enforcement (audit F-02 / F-03)', () => {
  let controller: GraphController;
  let graphService: ReturnType<typeof makeGraphServiceMock>;
  let graphEngine: ReturnType<typeof makeGraphEngineMock>;

  beforeEach(async () => {
    graphService = makeGraphServiceMock();
    graphEngine = makeGraphEngineMock();

    const module: TestingModule = await Test.createTestingModule({
      controllers: [GraphController],
      providers: [
        { provide: GraphService, useValue: graphService },
        { provide: GraphEngineService, useValue: graphEngine },
      ],
    }).compile();

    controller = module.get<GraphController>(GraphController);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  // ── /graph/:familyId/tree (F-02) ───────────────────────────────────

  describe('GET /graph/:familyId/tree', () => {
    const userId = 'user_in_family_A';
    const familyId = 'family_A';
    const rootPersonId = 'person_anchor_A';
    const treeResult = { root: { id: rootPersonId, name: 'Alice' }, totalNodes: 5, isTruncated: false };

    it('allows a family member to fetch the tree and returns the same shape as before', async () => {
      // Member check passes — assertMember resolves (returns the membership
      // object; the controller does not inspect it).
      graphService.assertMember.mockResolvedValue({ id: 'm1', familyId, userId, role: 'member' });
      graphService.resolveRootPersonId.mockResolvedValue(rootPersonId);
      graphService.getTree.mockResolvedValue(treeResult);

      const result = await controller.getTree(userId, familyId, undefined, '20');

      // Membership was checked BEFORE any graph data was loaded. We assert
      // ordering via invocationCallOrder instead of jest-extended's
      // toHaveBeenCalledBefore (which isn't installed in this repo).
      expect(graphService.assertMember).toHaveBeenCalledWith(userId, familyId);
      expect(graphService.resolveRootPersonId).toHaveBeenCalledWith(userId, familyId, undefined);
      expect(graphService.getTree).toHaveBeenCalledWith(familyId, rootPersonId, 20);
      const assertCallOrder = graphService.assertMember.mock.invocationCallOrder[0];
      const resolveCallOrder = graphService.resolveRootPersonId.mock.invocationCallOrder[0];
      const treeCallOrder = graphService.getTree.mock.invocationCallOrder[0];
      expect(assertCallOrder).toBeLessThan(resolveCallOrder);
      expect(resolveCallOrder).toBeLessThan(treeCallOrder);
      // Response shape unchanged.
      expect(result).toEqual(treeResult);
    });

    it('denies a non-member of a private family with ForbiddenException BEFORE loading any graph data', async () => {
      // requireFamilyMember throws ForbiddenException for non-members of
      // private families. assertMember propagates the same exception.
      graphService.assertMember.mockRejectedValue(new ForbiddenException('This family tree is private.'));

      await expect(controller.getTree(userId, familyId)).rejects.toBeInstanceOf(ForbiddenException);

      // Critical: no graph data was loaded for the denied caller.
      expect(graphService.resolveRootPersonId).not.toHaveBeenCalled();
      expect(graphService.getTree).not.toHaveBeenCalled();
    });

    it('returns 404 (NotFoundException) for a non-existent family WITHOUT loading graph data', async () => {
      // requireFamilyMember throws NotFoundException when the family does
      // not exist. This matches the existing behaviour of every other
      // graph endpoint — we are explicitly NOT changing it.
      graphService.assertMember.mockRejectedValue(new NotFoundException('Family not found'));

      await expect(controller.getTree(userId, 'nonexistent_family')).rejects.toBeInstanceOf(NotFoundException);

      expect(graphService.resolveRootPersonId).not.toHaveBeenCalled();
      expect(graphService.getTree).not.toHaveBeenCalled();
    });

    it('does not call assertMember with stale data — familyId comes straight from the path param', async () => {
      graphService.assertMember.mockResolvedValue(null); // public family read-only
      graphService.resolveRootPersonId.mockResolvedValue(rootPersonId);
      graphService.getTree.mockResolvedValue(treeResult);

      await controller.getTree(userId, familyId, 'rootPersonXYZ', '10');

      // The membership check MUST use the same familyId the controller
      // received from the route — no transformation, no fallback.
      expect(graphService.assertMember).toHaveBeenCalledWith(userId, familyId);
      // The root query param is forwarded to resolveRootPersonId unchanged.
      expect(graphService.resolveRootPersonId).toHaveBeenCalledWith(userId, familyId, 'rootPersonXYZ');
    });
  });

  // ── /graph/:familyId/path (F-03) ───────────────────────────────────

  describe('GET /graph/:familyId/path', () => {
    const userId = 'user_in_family_A';
    const familyId = 'family_A';
    const from = 'person_A1';
    const to = 'person_A2';
    const findPathResult = { found: true, path: [{ personId: from, personName: 'Alice', primitive: 'self' }], distance: 1 };

    it('allows a family member to fetch the path and returns the same { forward } shape as before', async () => {
      graphService.assertMember.mockResolvedValue({ id: 'm1', familyId, userId, role: 'member' });
      graphEngine.findPath.mockResolvedValue(findPathResult);

      const result = await controller.getPath(userId, familyId, from, to);

      expect(graphService.assertMember).toHaveBeenCalledWith(userId, familyId);
      expect(graphEngine.findPath).toHaveBeenCalledWith(familyId, from, to);
      // Membership was checked BEFORE the BFS path search ran.
      const assertCallOrder = graphService.assertMember.mock.invocationCallOrder[0];
      const findCallOrder = graphEngine.findPath.mock.invocationCallOrder[0];
      expect(assertCallOrder).toBeLessThan(findCallOrder);
      // Response shape unchanged — still wrapped in { forward }.
      expect(result).toEqual({ forward: findPathResult });
    });

    it('rejects with BadRequestException when from/to are missing — BEFORE the membership check', async () => {
      // Input validation runs first (cheap rejection); the membership
      // check is not invoked at all in this case. This matches the
      // pre-fix behaviour.
      await expect(controller.getPath(userId, familyId, undefined, to)).rejects.toBeInstanceOf(BadRequestException);
      await expect(controller.getPath(userId, familyId, from, undefined)).rejects.toBeInstanceOf(BadRequestException);

      expect(graphService.assertMember).not.toHaveBeenCalled();
      expect(graphEngine.findPath).not.toHaveBeenCalled();
    });

    it('denies a non-member of a private family with ForbiddenException BEFORE running the BFS', async () => {
      graphService.assertMember.mockRejectedValue(new ForbiddenException('This family tree is private.'));

      await expect(controller.getPath(userId, familyId, from, to)).rejects.toBeInstanceOf(ForbiddenException);

      // Critical: BFS path search was NOT run for the denied caller.
      expect(graphEngine.findPath).not.toHaveBeenCalled();
    });

    it('returns 404 (NotFoundException) for a non-existent family WITHOUT running the BFS', async () => {
      graphService.assertMember.mockRejectedValue(new NotFoundException('Family not found'));

      await expect(controller.getPath(userId, 'nonexistent_family', from, to)).rejects.toBeInstanceOf(NotFoundException);

      expect(graphEngine.findPath).not.toHaveBeenCalled();
    });

    it('does not change the response shape for an authorised caller — { forward } wrapper preserved', async () => {
      // The fix intentionally does NOT switch to GraphService.getPathWithAuth
      // because that method returns { path, relationships } — a different
      // shape than the existing { forward } contract. This test pins the
      // contract so a future refactor cannot silently change it.
      graphService.assertMember.mockResolvedValue(null); // public family, read-only
      const richResult = {
        found: true,
        path: [{ personId: 'p1', personName: 'A', primitive: 'self' }],
        distance: 0,
        signature: { pathPattern: 'self' },
        result: { term: 'self', fundamentalEdge: 'self' },
      };
      graphEngine.findPath.mockResolvedValue(richResult);

      const result = await controller.getPath(userId, familyId, from, to);

      expect(result).toEqual({ forward: richResult });
      expect(result).not.toHaveProperty('path');
      expect(result).not.toHaveProperty('relationships');
    });
  });
});
