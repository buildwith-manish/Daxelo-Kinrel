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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.LoggerService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const winston = __importStar(require("winston"));
const winston_daily_rotate_file_1 = __importDefault(require("winston-daily-rotate-file"));
let LoggerService = class LoggerService {
    constructor(configService) {
        this.configService = configService;
        const isDev = configService.get('NODE_ENV', 'development') !== 'production';
        const logLevel = configService.get('LOG_LEVEL', 'info');
        const logDir = configService.get('LOG_DIR', 'logs');
        const levels = {
            error: 0,
            warn: 1,
            info: 2,
            http: 3,
            debug: 4,
            verbose: 5,
        };
        const transports = [];
        transports.push(new winston.transports.Console({
            level: logLevel,
            format: isDev
                ? winston.format.combine(winston.format.colorize({ all: true }), winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }), winston.format.printf(({ timestamp, level, message, ...meta }) => {
                    const context = meta.context || '';
                    const ctx = context ? ` [${context}]` : '';
                    const metaStr = Object.keys(meta).length > 1
                        ? ` ${JSON.stringify(Object.fromEntries(Object.entries(meta).filter(([k]) => k !== 'context')))}`
                        : '';
                    return `${timestamp}${ctx} ${level}: ${message}${metaStr}`;
                }))
                : winston.format.combine(winston.format.timestamp(), winston.format.json()),
        }));
        transports.push(new winston_daily_rotate_file_1.default({
            dirname: logDir,
            filename: 'app-%DATE%.log',
            datePattern: 'YYYY-MM-DD',
            zippedArchive: true,
            maxSize: '20m',
            maxFiles: '14d',
            level: logLevel,
            format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
        }));
        transports.push(new winston_daily_rotate_file_1.default({
            dirname: logDir,
            filename: 'error-%DATE%.log',
            datePattern: 'YYYY-MM-DD',
            zippedArchive: true,
            maxSize: '20m',
            maxFiles: '30d',
            level: 'error',
            format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
        }));
        this.winston = winston.createLogger({
            levels,
            level: logLevel,
            defaultMeta: { service: 'daxelo-kinrel' },
            transports,
            exitOnError: false,
        });
    }
    log(message, context) {
        this.winston.info(message, { context });
    }
    error(message, trace, context) {
        this.winston.error(message, { context, trace });
    }
    warn(message, context) {
        this.winston.warn(message, { context });
    }
    debug(message, context) {
        this.winston.debug(message, { context });
    }
    verbose(message, context) {
        this.winston.verbose(message, { context });
    }
    logRequest(req, res, duration) {
        const meta = {
            method: req.method,
            route: req.url,
            statusCode: res.statusCode,
            duration,
            userId: req.userId || undefined,
            correlationId: req.correlationId || undefined,
        };
        if (res.statusCode >= 500) {
            this.winston.error(`${req.method} ${req.url} ${res.statusCode} — ${duration}ms`, meta);
        }
        else if (res.statusCode >= 400) {
            this.winston.warn(`${req.method} ${req.url} ${res.statusCode} — ${duration}ms`, meta);
        }
        else if (duration > 500) {
            this.winston.warn(`SLOW ${req.method} ${req.url} ${res.statusCode} — ${duration}ms`, meta);
        }
        else {
            this.winston.info(`${req.method} ${req.url} ${res.statusCode} — ${duration}ms`, meta);
        }
    }
    logError(error, context) {
        if (error instanceof Error) {
            this.winston.error(error.message, {
                context,
                stack: error.stack,
                errorName: error.name,
            });
        }
        else {
            this.winston.error(String(error), { context });
        }
    }
    logAlert(alertType, message, meta) {
        this.winston.error(`[ALERT][${alertType}] ${message}`, {
            alert: true,
            alertType,
            ...meta,
        });
    }
};
exports.LoggerService = LoggerService;
exports.LoggerService = LoggerService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService])
], LoggerService);
//# sourceMappingURL=logger.service.js.map