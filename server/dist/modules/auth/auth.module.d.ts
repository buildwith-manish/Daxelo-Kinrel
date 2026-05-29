import { OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { AuthService } from './auth.service';
export declare class AuthModule implements OnModuleInit, OnModuleDestroy {
    private readonly authService;
    private cleanupInterval;
    constructor(authService: AuthService);
    onModuleInit(): void;
    onModuleDestroy(): void;
}
