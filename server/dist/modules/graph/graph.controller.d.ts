import { GraphService } from './graph.service';
export declare class GraphController {
    private graphService;
    constructor(graphService: GraphService);
    getGraph(userId: string, familyId: string, root?: string, depth?: string, format?: 'flat' | 'tree', from?: string, to?: string, locale?: string): Promise<import("./graph.service").FlatGraphResult | import("./graph.service").PathResult | {
        root: import("./graph.service").TreeNode | null;
        totalNodes: number;
    }>;
    getTree(userId: string, familyId: string, root?: string, depth?: string, locale?: string): Promise<{
        root: import("./graph.service").TreeNode | null;
        totalNodes: number;
    }>;
    getPath(userId: string, familyId: string, from?: string, to?: string): Promise<import("./graph.service").PathResult>;
}
