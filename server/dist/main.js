"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const core_1 = require("@nestjs/core");
const common_1 = require("@nestjs/common");
const app_module_1 = require("./app.module");
const config_1 = require("@nestjs/config");
const all_exceptions_filter_1 = require("./common/filters/all-exceptions.filter");
const transform_interceptor_1 = require("./common/interceptors/transform.interceptor");
const field_trim_interceptor_1 = require("./common/interceptors/field-trim.interceptor");
const timestamp_interceptor_1 = require("./common/interceptors/timestamp.interceptor");
const security_headers_interceptor_1 = require("./common/interceptors/security-headers.interceptor");
const logging_interceptor_1 = require("./common/interceptors/logging.interceptor");
const logger_service_1 = require("./common/logger/logger.service");
const alerting_service_1 = require("./common/alerting/alerting.service");
const helmet_1 = __importDefault(require("helmet"));
const compression = require('compression');
const CORS_WHITELIST = [
    'http://localhost:3001',
    'http://localhost:8080',
    'https://kinrel.app',
    'https://daxelo-kinrel-server.onrender.com',
    'capabile://',
    'com.daxelo.kinrel',
];
async function bootstrap() {
    const app = await core_1.NestFactory.create(app_module_1.AppModule, {
        bufferLogs: true,
    });
    const configService = app.get(config_1.ConfigService);
    const loggerService = app.get(logger_service_1.LoggerService);
    const alertingService = app.get(alerting_service_1.AlertingService);
    app.useLogger(loggerService);
    const apiPrefix = configService.get('API_PREFIX', 'api');
    app.use((0, helmet_1.default)());
    app.use(compression({
        threshold: 1024,
        level: 6,
    }));
    app.setGlobalPrefix(apiPrefix);
    const corsOriginsEnv = configService.get('CORS_ORIGINS', '');
    const allowedOrigins = corsOriginsEnv
        ? corsOriginsEnv.split(',').map((s) => s.trim())
        : CORS_WHITELIST;
    app.enableCors({
        origin: (origin, callback) => {
            if (!origin) {
                return callback(null, true);
            }
            if (allowedOrigins.includes(origin)) {
                return callback(null, true);
            }
            if (!corsOriginsEnv &&
                (origin.startsWith('http://localhost:') ||
                    origin.startsWith('http://127.0.0.1:'))) {
                return callback(null, true);
            }
            return callback(null, false);
        },
        credentials: true,
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
        allowedHeaders: [
            'Content-Type',
            'Authorization',
            'X-User-Id',
            'Idempotency-Key',
            'X-Correlation-Id',
        ],
    });
    app.useGlobalPipes(new common_1.ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
        transformOptions: { enableImplicitConversion: true },
    }));
    app.useGlobalFilters(new all_exceptions_filter_1.AllExceptionsFilter(alertingService));
    app.useGlobalInterceptors(new security_headers_interceptor_1.SecurityHeadersInterceptor(), new logging_interceptor_1.LoggingInterceptor(loggerService, alertingService), new transform_interceptor_1.TransformInterceptor(), new field_trim_interceptor_1.FieldTrimInterceptor(), new timestamp_interceptor_1.TimestampInterceptor());
    app.enableShutdownHooks();
    const port = configService.get('PORT', 3000);
    await app.listen(port);
    loggerService.log(`🚀 DAXELO KINREL Server running on http://localhost:${port}/${apiPrefix}`, 'Bootstrap');
    loggerService.log(`📡 API routes: /${apiPrefix}/* and /${apiPrefix}/v1/* for Flutter compatibility`, 'Bootstrap');
    process.on('SIGTERM', async () => {
        loggerService.log('SIGTERM received — shutting down gracefully...', 'Bootstrap');
        await app.close();
        loggerService.log('Application shut down complete', 'Bootstrap');
        process.exit(0);
    });
}
bootstrap();
//# sourceMappingURL=main.js.map