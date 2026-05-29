"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SecurityHeadersInterceptor = void 0;
const common_1 = require("@nestjs/common");
const operators_1 = require("rxjs/operators");
let SecurityHeadersInterceptor = class SecurityHeadersInterceptor {
    intercept(context, next) {
        const response = context.switchToHttp().getResponse();
        response.removeHeader('X-Powered-By');
        return next.handle().pipe((0, operators_1.tap)(() => {
            response.setHeader('X-Content-Type-Options', 'nosniff');
            response.setHeader('X-Frame-Options', 'DENY');
            response.setHeader('X-XSS-Protection', '1; mode=block');
            response.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
            response.setHeader('Content-Security-Policy', "default-src 'self'");
        }));
    }
};
exports.SecurityHeadersInterceptor = SecurityHeadersInterceptor;
exports.SecurityHeadersInterceptor = SecurityHeadersInterceptor = __decorate([
    (0, common_1.Injectable)()
], SecurityHeadersInterceptor);
//# sourceMappingURL=security-headers.interceptor.js.map