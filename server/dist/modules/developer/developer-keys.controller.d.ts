import { DeveloperService } from './developer.service';
export declare class DeveloperKeysController {
    private readonly developerService;
    constructor(developerService: DeveloperService);
    listApiKeys(userId: string): Promise<any>;
    createApiKey(userId: string, body: {
        name: string;
        scopes?: string[];
        tier?: string;
    }): Promise<{
        id: any;
        name: any;
        key: string;
        keyPrefix: any;
        scopes: string[];
        tier: any;
        createdAt: any;
    }>;
    revokeApiKey(userId: string, id: string): Promise<{
        id: any;
        name: any;
        revoked: boolean;
        revokedAt: any;
    }>;
}
