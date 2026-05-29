import { OnGatewayConnection, OnGatewayDisconnect } from '@nestjs/websockets';
export declare class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
    private server;
    private readonly logger;
    handleConnection(client: any): void;
    handleDisconnect(client: any): void;
    handleJoinFamily(client: any, data: {
        familyId: string;
    }): {
        event: string;
        familyId: string;
    };
    handleLeaveFamily(client: any, data: {
        familyId: string;
    }): {
        event: string;
        familyId: string;
    };
    broadcastToFamily(familyId: string, event: string, payload: any): void;
}
