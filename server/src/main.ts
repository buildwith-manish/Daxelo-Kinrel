import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { FieldTrimInterceptor } from './common/interceptors/field-trim.interceptor';
import { TimestampInterceptor } from './common/interceptors/timestamp.interceptor';
import { SecurityHeadersInterceptor } from './common/interceptors/security-headers.interceptor';
import { LoggingInterceptor } from './common/interceptors/logging.interceptor';
import { LoggerService } from './common/logger/logger.service';
import { AlertingService } from './common/alerting/alerting.service';
import helmet from 'helmet';
const compression = require('compression');

// ── CORS Whitelist ─────────────────────────────────────────────────
const CORS_WHITELIST = [
  'http://localhost:3001',                              // Flutter web dev
  'http://localhost:8080',                              // Flutter web alt
  'https://kinrel.app',                                // Production
  'https://daxelo-kinrel-server.onrender.com',         // Render backend
  'capabile://',                                        // iOS app scheme
  'com.daxelo.kinrel',                                 // Android app scheme
];

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true,
  });

  const configService = app.get(ConfigService);
  const loggerService = app.get(LoggerService);
  const alertingService = app.get(AlertingService);

  // ── Custom structured logger (Winston) ──────────────────────────
  app.useLogger(loggerService);

  const apiPrefix = configService.get<string>('API_PREFIX', 'api');

  // ── Helmet — HTTP security headers ──────────────────────────────
  app.use(helmet());

  // ── Gzip compression — reduces response sizes for slow networks ─
  // Particularly important for the /api/sync endpoint (50KB limit)
  app.use(compression({
    threshold: 1024, // Only compress responses > 1KB
    level: 6,        // Balance between speed and compression ratio
  }));

  // Global prefix — all routes become /api/...
  // Controllers using @Controller('v1/xxx') will be accessible at /api/v1/xxx
  // This supports the Flutter app's /v1/ endpoint pattern when prefixed with /api
  app.setGlobalPrefix(apiPrefix);

  // ── CORS — whitelist with env override ──────────────────────────
  const corsOriginsEnv = configService.get<string>('CORS_ORIGINS', '');
  const allowedOrigins = corsOriginsEnv
    ? corsOriginsEnv.split(',').map((s) => s.trim())
    : CORS_WHITELIST;

  app.enableCors({
    origin: (origin: string | undefined, callback: (err: Error | null, allow?: boolean) => void) => {
      // Allow requests with no origin (mobile apps, curl, server-to-server)
      if (!origin) {
        return callback(null, true);
      }
      if (allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      // In development, allow localhost on any port
      if (
        !corsOriginsEnv &&
        (origin.startsWith('http://localhost:') ||
         origin.startsWith('http://127.0.0.1:'))
      ) {
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

  // ── Global validation pipe ──────────────────────────────────────
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  // ── Global exception filter (with alerting integration) ────────
  app.useGlobalFilters(new AllExceptionsFilter(alertingService));

  // ── Global interceptors — order matters: ────────────────────────
  // 1. SecurityHeadersInterceptor: adds security HTTP headers + removes X-Powered-By
  // 2. LoggingInterceptor: adds X-Correlation-Id + structured request logging
  // 3. TransformInterceptor: adds X-Response-Time header
  // 4. FieldTrimInterceptor: removes null/undefined fields to save bandwidth
  // 5. TimestampInterceptor: adds `ts` field for cache validation (no envelope)
  app.useGlobalInterceptors(
    new SecurityHeadersInterceptor(),
    new LoggingInterceptor(loggerService, alertingService),
    new TransformInterceptor(),
    new FieldTrimInterceptor(),
    new TimestampInterceptor(),
  );

  // Enable graceful shutdown hooks — ensures Prisma disconnects,
  // WebSocket connections close, and in-flight requests complete
  // before the process exits. Prevents data corruption on restarts.
  app.enableShutdownHooks();

  const port = configService.get<number>('PORT', 3000);
  await app.listen(port);
  loggerService.log(
    `🚀 DAXELO KINREL Server running on http://localhost:${port}/${apiPrefix}`,
    'Bootstrap',
  );
  loggerService.log(
    `📡 API routes: /${apiPrefix}/* and /${apiPrefix}/v1/* for Flutter compatibility`,
    'Bootstrap',
  );

  // Graceful shutdown on SIGTERM (e.g. Kubernetes pod termination, docker stop)
  process.on('SIGTERM', async () => {
    loggerService.log('SIGTERM received — shutting down gracefully...', 'Bootstrap');
    await app.close();
    loggerService.log('Application shut down complete', 'Bootstrap');
    process.exit(0);
  });
}
bootstrap();
