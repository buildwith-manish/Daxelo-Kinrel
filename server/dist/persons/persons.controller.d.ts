import { PersonsService } from './persons.service';
import { AddPersonDto } from '../dto/add-person.dto';
import { UpdatePersonDto } from '../dto/update-person.dto';
export declare class PersonsController {
    private readonly personsService;
    constructor(personsService: PersonsService);
    listPersons(user: any, familyId: string): Promise<{
        persons: any;
    }>;
    addPerson(user: any, familyId: string, body: AddPersonDto): Promise<{
        person: any;
    }>;
}
export declare class PersonController {
    private readonly personsService;
    constructor(personsService: PersonsService);
    updatePerson(user: any, id: string, body: UpdatePersonDto): Promise<{
        person: any;
    }>;
    deletePerson(user: any, id: string): Promise<{
        message: string;
        id: string;
    }>;
}
