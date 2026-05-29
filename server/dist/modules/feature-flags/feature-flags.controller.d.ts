import { FeatureFlagsService } from './feature-flags.service';
export declare class FeatureFlagsController {
    private readonly featureFlagsService;
    constructor(featureFlagsService: FeatureFlagsService);
    getAllFlags(): Promise<any>;
    isFlagEnabled(name: string): Promise<{
        name: string;
        enabled: boolean;
    }>;
    setFlag(body: {
        name: string;
        enabled: boolean;
        description?: string;
    }): Promise<any>;
}
