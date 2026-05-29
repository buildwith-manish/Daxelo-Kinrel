"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.KinrelGateway = void 0;
const websockets_1 = require("@nestjs/websockets");
const socket_io_1 = require("socket.io");
const jwt = __importStar(require("jsonwebtoken"));
const JWT_SECRET = process.env.JWT_ACCESS_SECRET || process.env.JWT_SECRET || 'kinrel-dev-secret-change-in-production';
let KinrelGateway = class KinrelGateway {
    constructor() {
        this.connectedUsers = new Map();
        this.graphDebounceTimers = new Map();
    }
    async handleConnection(client) {
        try {
            const token = client.handshake.auth?.token ||
                client.handshake.query?.token ||
                client.handshake.headers?.authorization?.replace('Bearer ', '');
            if (!token) {
                console.warn(`[WS] Connection rejected — no token: ${client.id}`);
                client.disconnect(true);
                return;
            }
            const payload = jwt.verify(token, JWT_SECRET);
            const userId = payload.sub;
            this.connectedUsers.set(client.id, userId);
            client.userId = userId;
            console.log(`[WS] Connected: ${client.id} (user: ${userId})`);
        }
        catch (err) {
            console.warn(`[WS] Connection rejected — invalid token: ${client.id}`, err.message);
            client.disconnect(true);
        }
    }
    handleDisconnect(client) {
        const userId = this.connectedUsers.get(client.id);
        if (userId) {
            this.connectedUsers.delete(client.id);
        }
        console.log(`[WS] Disconnected: ${client.id}`);
    }
    handleJoinFamily(client, data) {
        const userId = client.userId;
        if (!userId) {
            client.emit('error', { message: 'Not authenticated' });
            return;
        }
        const roomName = `family:${data.familyId}`;
        client.join(roomName);
        client.emit('joined:family', { familyId: data.familyId });
        client.to(roomName).emit('user:joined', { userId, familyId: data.familyId });
    }
    handleLeaveFamily(client, data) {
        const userId = client.userId;
        if (!userId)
            return;
        const roomName = `family:${data.familyId}`;
        client.leave(roomName);
        client.emit('left:family', { familyId: data.familyId });
        client.to(roomName).emit('user:left', { userId, familyId: data.familyId });
    }
    emitToFamily(familyId, event, payload) {
        if (event === 'graph:updated') {
            this._debouncedGraphEmit(familyId, payload);
            return;
        }
        this.server.to(`family:${familyId}`).emit(event, {
            ...payload,
            timestamp: new Date().toISOString(),
        });
    }
    _debouncedGraphEmit(familyId, payload) {
        const existingTimer = this.graphDebounceTimers.get(familyId);
        if (existingTimer) {
            clearTimeout(existingTimer);
        }
        const timer = setTimeout(() => {
            this.graphDebounceTimers.delete(familyId);
            this.server.to(`family:${familyId}`).emit('graph:updated', {
                ...payload,
                timestamp: new Date().toISOString(),
            });
        }, 500);
        this.graphDebounceTimers.set(familyId, timer);
    }
};
exports.KinrelGateway = KinrelGateway;
__decorate([
    (0, websockets_1.WebSocketServer)(),
    __metadata("design:type", socket_io_1.Server)
], KinrelGateway.prototype, "server", void 0);
__decorate([
    (0, websockets_1.SubscribeMessage)('join:family'),
    __param(0, (0, websockets_1.ConnectedSocket)()),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], KinrelGateway.prototype, "handleJoinFamily", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('leave:family'),
    __param(0, (0, websockets_1.ConnectedSocket)()),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], KinrelGateway.prototype, "handleLeaveFamily", null);
exports.KinrelGateway = KinrelGateway = __decorate([
    (0, websockets_1.WebSocketGateway)({
        cors: { origin: '*' },
        namespace: '/',
        transports: ['websocket'],
        pingTimeout: 10000,
        pingInterval: 25000,
    })
], KinrelGateway);
//# sourceMappingURL=kinrel.gateway.js.map