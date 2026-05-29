import { OnGatewayConnection, OnGatewayDisconnect } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
export interface MinimalPayload {
    id: string;
    updatedAt: string;
    type: string;
    familyId?: string;
    [key: string]: unknown;
}
export declare class KinrelGateway implements OnGatewayConnection, OnGatewayDisconnect {
    server: Server;
    private connectedUsers;
    private graphDebounceTimers;
    handleConnection(client: Socket): Promise<void>;
    handleDisconnect(client: Socket): void;
    handleJoinFamily(client: Socket, data: {
        familyId: string;
    }): void;
    handleLeaveFamily(client: Socket, data: {
        familyId: string;
    }): void;
    emitToFamily(familyId: string, event: string, payload: MinimalPayload): void;
    private _debouncedGraphEmit;
}
