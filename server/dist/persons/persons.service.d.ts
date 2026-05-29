import { PrismaService } from '../prisma/prisma.service';
export declare class PersonsService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    listPersons(userId: string, familyId: string): Promise<any>;
    addPerson(userId: string, familyId: string, data: any): Promise<any>;
    updatePerson(userId: string, personId: string, data: any): Promise<any>;
    deletePerson(userId: string, personId: string): Promise<{
        message: string;
        id: string;
    }>;
}
