export declare class RealtimeService {
    private readonly logger;
    prepareEvent(familyId: string, eventType: string, payload: any): {
        familyId: string;
        eventType: string;
        payload: any;
        timestamp: string;
    };
}
