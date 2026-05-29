"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var PaymentsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.PaymentsService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const prisma_service_1 = require("../../prisma/prisma.service");
let PaymentsService = PaymentsService_1 = class PaymentsService {
    constructor(prisma, config) {
        this.prisma = prisma;
        this.config = config;
        this.logger = new common_1.Logger(PaymentsService_1.name);
    }
    async createOrder(userId, plan, amount, currency = 'INR') {
        this.logger.log(`Creating order for user ${userId}, plan: ${plan}, amount: ${amount}`);
        return {
            orderId: `order_${Date.now()}`,
            amount,
            currency,
            plan,
        };
    }
    async verifyAndActivate(userId, paymentData) {
        this.logger.log(`Verifying payment for user ${userId}`);
        return this.prisma.subscription.upsert({
            where: { userId },
            update: {
                plan: paymentData.plan || 'pro_monthly',
                status: 'active',
                supportTier: 'standard',
                startDate: new Date(),
            },
            create: {
                userId,
                plan: paymentData.plan || 'pro_monthly',
                status: 'active',
                supportTier: 'standard',
                startDate: new Date(),
            },
        });
    }
    async getSubscription(userId) {
        return this.prisma.subscription.findUnique({ where: { userId } });
    }
    async cancelSubscription(userId) {
        return this.prisma.subscription.update({
            where: { userId },
            data: { status: 'cancelled' },
        });
    }
};
exports.PaymentsService = PaymentsService;
exports.PaymentsService = PaymentsService = PaymentsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService])
], PaymentsService);
//# sourceMappingURL=payments.service.js.map