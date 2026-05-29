import { PrismaService } from '../../prisma/prisma.service';
export interface TreeNode {
    person: {
        id: string;
        familyId: string;
        name: string;
        gender: string | null;
        dateOfBirth: Date | null;
        isDeceased: boolean;
        birthYear: number | null;
        isAnchor: boolean;
        photoUrl: string | null;
        photoThumb: string | null;
        sideOfFamily: string | null;
        generationIndex: number;
    };
    relationships: Array<{
        id: string;
        toPersonId: string;
        relationshipKey: string;
        direction: string;
        label: string | null;
    }>;
    children: TreeNode[];
}
export interface FlatGraphResult {
    persons: Array<Record<string, any>>;
    relationships: Array<Record<string, any>>;
}
export interface PathResult {
    path: Array<Record<string, any>>;
    relationships: Array<Record<string, any>>;
}
export declare class GraphService {
    private prisma;
    constructor(prisma: PrismaService);
    getGraph(userId: string, familyId: string, options?: {
        root?: string;
        depth?: number;
        format?: 'flat' | 'tree';
        from?: string;
        to?: string;
        locale?: string;
    }): Promise<FlatGraphResult | PathResult | {
        root: TreeNode | null;
        totalNodes: number;
    }>;
    resolveRootPersonId(userId: string, familyId: string, root?: string): Promise<string>;
    getTree(familyId: string, rootPersonId: string, depth?: number): Promise<{
        root: TreeNode | null;
        totalNodes: number;
    }>;
    getPath(familyId: string, fromPersonId: string, toPersonId: string): Promise<PathResult>;
    getPathWithAuth(userId: string, familyId: string, fromPersonId: string, toPersonId: string): Promise<PathResult>;
    getFlatGraph(familyId: string): Promise<FlatGraphResult>;
    private requireFamilyMember;
    private formatPerson;
}
