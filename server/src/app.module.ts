import { Module } from '@nestjs/common';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { FamiliesModule } from './families/families.module';
import { PersonsModule } from './persons/persons.module';
import { RelationshipsModule } from './relationships/relationships.module';
import { InvitationsModule } from './invitations/invitations.module';
import { SupportModule } from './support/support.module';
import { PrismaModule } from './prisma/prisma.module';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    UsersModule,
    FamiliesModule,
    PersonsModule,
    RelationshipsModule,
    InvitationsModule,
    SupportModule,
  ],
})
export class AppModule {}
