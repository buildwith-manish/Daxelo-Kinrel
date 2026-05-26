import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { db } from '@/lib/db';
import { buildTree, findPath } from '@/lib/api/graph-traversal';
import { getKinshipTermByLocale, type LocaleCode } from '@/lib/kinship';
import { success, error } from '@/packages/api';

async function authenticate(request: NextRequest) {
  const session = await getServerSession(authOptions);
  if (session?.user?.id) return { userId: session.user.id };
  // Could also check Bearer token here
  return null;
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> },
) {
  try {
    const auth = await authenticate(request);
    if (!auth) return error('AUTH_REQUIRED', 'Authentication required', 401);

    const { familyId } = await params;
    const membership = await db.familyMember.findFirst({ where: { familyId, userId: auth.userId } });
    if (!membership) return error('NOT_FOUND', 'Family not found or access denied', 404);

    const url = new URL(request.url);
    const locale = (url.searchParams.get('locale') || 'en') as LocaleCode;
    const fromPersonId = url.searchParams.get('from');
    const toPersonId = url.searchParams.get('to');

    // Path-finding mode
    if (fromPersonId && toPersonId) {
      const [fromPerson, toPerson] = await Promise.all([
        db.person.findFirst({ where: { id: fromPersonId, familyId, deletedAt: null } }),
        db.person.findFirst({ where: { id: toPersonId, familyId, deletedAt: null } }),
      ]);
      if (!fromPerson) return error('NOT_FOUND', `Person "${fromPersonId}" not found`, 404);
      if (!toPerson) return error('NOT_FOUND', `Person "${toPersonId}" not found`, 404);

      const pathResult = await findPath(familyId, fromPersonId, toPersonId);
      if (!pathResult) {
        return success({ from: { id: fromPersonId, name: fromPerson.name }, to: { id: toPersonId, name: toPerson.name }, path: null, message: 'No path found' });
      }

      return success({
        from: { id: fromPersonId, name: fromPerson.name },
        to: { id: toPersonId, name: toPerson.name },
        path: pathResult.path,
        length: pathResult.length,
        relationshipDescription: pathResult.relationshipDescription,
        localizedDescription: pathResult.localizedDescription,
      });
    }

    // Tree mode
    const depth = Math.min(10, Math.max(1, parseInt(url.searchParams.get('depth') || '5')));
    const tree = await buildTree(familyId, depth);

    return success({ familyId, format: 'nested', depth, locale, tree });
  } catch (err) {
    if (err instanceof Error && err.message === 'Family not found') {
      return error('NOT_FOUND', 'Family not found', 404);
    }
    console.error('[Graph GET] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to build graph', 500);
  }
}
