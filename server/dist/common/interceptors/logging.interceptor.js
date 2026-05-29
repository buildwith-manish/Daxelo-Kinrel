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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.LoggingInterceptor = void 0;
const common_1 = require("@nestjs/common");
const operators_1 = require("rxjs/operators");
const uuid_1 = require("uuid");
const logger_service_1 = require("../logger/logger.service");
const alerting_service_1 = require("../alerting/alerting.service");
let LoggingInterceptor = class LoggingInterceptor {
    constructor(loggerService, alertingService) {
        this.loggerService = loggerService;
        this.alertingService = alertingService;
    }
    intercept(context, next) {
        const request = context.switchToHttp().getRequest();
        const response = context.switchToHttp().getResponse();
        const correlationId = request.headers['x-correlation-id'] || (0, uuid_1.v4)();
        const startTime = Date.now();
        response.setHeader('X-Correlation-Id', correlationId);
        const userId = request.user?.id || request.headers['x-user-id'] || undefined;
        return next.handle().pipe((0, operators_1.tap)({
            next: () => {
                const duration = Date.now() - startTime;
                this.loggerService.logRequest({
                    method: request.method,
                    url: request.url,
                    userId,
                    correlationId,
                }, { statusCode: response.statusCode }, duration);
                if (this.alertingService) {
                    const isError = response.statusCode >= 400;
                    this.alertingService.recordRequest(duration, isError);
                }
            },
            error: () => {
                const duration = Date.now() - startTime;
                const statusCode = response.statusCode || 500;
                this.loggerService.logRequest({
                    method: request.method,
                    url: request.url,
                    userId,
                    correlationId,
                }, { statusCode }, duration);
                if (this.alertingService) {
                    this.alertingService.recordRequest(duration, true);
                }
            },
        }));
    }
};
exports.LoggingInterceptor = LoggingInterceptor;
exports.LoggingInterceptor = LoggingInterceptor = __decorate([
    (0, common_1.Injectable)(),
    __param(1, (0, common_1.Optional)()),
    __metadata("design:paramtypes", [logger_service_1.LoggerService,
        alerting_service_1.AlertingService])
], LoggingInterceptor);
//# sourceMappingURL=logging.interceptor.js.map