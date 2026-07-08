import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { FieldTrimInterceptor } from './common/interceptors/field-trim.interceptor';
import { TimestampInterceptor } from './common/interceptors/timestamp.interceptor';
import { ResponseEnvelopeInterceptor } from './common/interceptors/response-envelope.interceptor';
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
  'https://daxelokinrel.com',                          // Production domain
  'https://app.daxelokinrel.com',                      // App subdomain
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

  // ── Helmet — HTTP security headers + CSP ────────────────────────
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", "data:", "https://res.cloudinary.com"],
        connectSrc: ["'self'", "https://*.supabase.co"],
      },
    },
    crossOriginEmbedderPolicy: false,
  }));

  // ── Request ID tracking ────────────────────────────────────────
  app.use((req: any, res: any, next: any) => {
    const requestId = req.headers['x-request-id'] || require('crypto').randomBytes(8).toString('hex');
    req.headers['x-request-id'] = requestId;
    res.setHeader('x-request-id', requestId);
    next();
  });

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

  // ── Root path handler ──────────────────────────────────────────
  // NestJS's global prefix only applies to controllers. The bare root "/"
  // is handled by Express directly. This avoids "Cannot GET /" 404 errors
  // that spam the logs when health checkers or bots hit the root URL.
  app.use('/', (req: any, res: any, next: any) => {
    if (req.path === '/') {
      return res.json({
        service: 'Daxelo Kinrel API',
        version: '1.0.0',
        status: 'running',
        docs: '/docs',
        health: '/api/health',
      });
    }
    next();
  });

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
  // 6. ResponseEnvelopeInterceptor: wraps response in { success, data, timestamp } envelope
  app.useGlobalInterceptors(
    new SecurityHeadersInterceptor(),
    new LoggingInterceptor(loggerService, alertingService),
    new TransformInterceptor(),
    new FieldTrimInterceptor(),
    new TimestampInterceptor(),
    new ResponseEnvelopeInterceptor(),
  );

  // Enable graceful shutdown hooks — ensures Prisma disconnects,
  // WebSocket connections close, and in-flight requests complete
  // before the process exits. Prevents data corruption on restarts.
  app.enableShutdownHooks();

  // ── Swagger / OpenAPI documentation ────────────────────────────────
  // P6-FIX: Use 'docs' path (NOT 'api/docs') because app.setGlobalPrefix('api')
  // already prepends /api to controller routes. SwaggerModule.setup registers
  // its route directly on Express — it does NOT go through NestJS's prefix system.
  // With 'docs', the Swagger UI is at /docs and the JSON at /docs-json.
  // Using 'api/docs' would try to register at /api/docs but the NestJS
  // router with global prefix 'api' intercepts /api/* first and returns 404.
  const swaggerConfig = new DocumentBuilder()
    .setTitle('Daxelo Kinrel API')
    .setDescription('Indian Family Relationship Intelligence API')
    .setVersion('1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('docs', app, document);

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
  loggerService.log(
    `📖 Swagger docs: http://localhost:${port}/docs`,
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

// ── Crash diagnostics ──────────────────────────────────────────────────
// Catch uncaught exceptions and unhandled rejections so the error is logged
// before the process exits. Without these, Node prints to stderr which may
// not be visible in all hosting environments (e.g. Render dashboard).
process.on('uncaughtException', (err) => {
  console.error('💥 UNCAUGHT EXCEPTION:', err);
  console.error(err?.stack || err);
  // Give the log time to flush before exiting
  setTimeout(() => process.exit(1), 1000);
});

process.on('unhandledRejection', (reason) => {
  console.error('💥 UNHANDLED REJECTION:', reason);
  // Don't exit on unhandled rejection — just log it
  // (some promises may reject during module init but the app can recover)
});

bootstrap().catch((err) => {
  console.error('💥 BOOTSTRAP FAILED:', err);
  console.error(err?.stack || err);
  process.exit(1);
});
