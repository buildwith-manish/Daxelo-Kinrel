"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.FieldTrimInterceptor = void 0;
const common_1 = require("@nestjs/common");
const operators_1 = require("rxjs/operators");
let FieldTrimInterceptor = class FieldTrimInterceptor {
    intercept(context, next) {
        return next.handle().pipe((0, operators_1.map)((data) => this.trimNulls(data)));
    }
    trimNulls(value) {
        if (value === null || value === undefined) {
            return undefined;
        }
        if (Array.isArray(value)) {
            return value.map((item) => this.trimNulls(item));
        }
        if (typeof value === 'object' && value.constructor === Object) {
            const result = {};
            for (const [key, val] of Object.entries(value)) {
                if (val !== null && val !== undefined) {
                    result[key] = this.trimNulls(val);
                }
            }
            return result;
        }
        return value;
    }
};
exports.FieldTrimInterceptor = FieldTrimInterceptor;
exports.FieldTrimInterceptor = FieldTrimInterceptor = __decorate([
    (0, common_1.Injectable)()
], FieldTrimInterceptor);
//# sourceMappingURL=field-trim.interceptor.js.map