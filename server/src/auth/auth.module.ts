import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { PrismaModule } from '../prisma/prisma.module';
import { SupabaseAuthGuard } from './supabase-auth.guard';

@Module({
  imports: [PrismaModule],
  controllers: [AuthController],
  providers: [SupabaseAuthGuard],
  exports: [SupabaseAuthGuard],
})
export class AuthModule {}
