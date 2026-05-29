import { TimelineService } from './timeline.service';
export declare class TimelineController {
    private readonly timelineService;
    constructor(timelineService: TimelineService);
    getTimeline(familyId: string, limit?: string, cursor?: string): Promise<{
        data: any;
        nextCursor: any;
    }>;
    createPost(familyId: string, body: {
        authorId: string;
        postType: string;
        content: Record<string, any>;
    }): Promise<any>;
}
