import { CanActivate, ExecutionContext } from '@nestjs/common';
export declare class OptionalAuthGuard implements CanActivate {
    private readonly supabaseAnonKey;
    constructor();
    canActivate(context: ExecutionContext): Promise<boolean>;
}
