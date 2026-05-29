import { SupportService } from './support.service';
import { CreateTicketDto } from '../dto/create-ticket.dto';
export declare class SupportController {
    private readonly supportService;
    constructor(supportService: SupportService);
    createTicket(user: any, body: CreateTicketDto): Promise<{
        ticket: any;
    }>;
}
