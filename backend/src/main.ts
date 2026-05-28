import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { PerformanceInterceptor } from './common/interceptors/performance.interceptor';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import helmet from 'helmet';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Global prefix — all routes will be /api/*
  app.setGlobalPrefix('api');

  // Security headers via Helmet
  app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
  }));

  // CORS whitelist
  app.enableCors({
    origin: [
      'https://kinrel.app',
      'https://app.kinrel.app',
      'http://localhost:3000',
      'http://localhost:3001',
    ],
    credentials: true,
  });

  // Global validation pipe
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // Global response interceptor
  app.useGlobalInterceptors(new TransformInterceptor());

  // Global performance logging interceptor
  app.useGlobalInterceptors(new PerformanceInterceptor());

  // Global exception filter
  app.useGlobalFilters(new HttpExceptionFilter());

  // Replace default logger with Pino
  app.useLogger(app.get(Logger));

  // Enable shutdown hooks for proper cleanup
  app.enableShutdownHooks();

  const port = process.env.PORT || 3001;
  await app.listen(port);
  console.log(`🚀 NestJS backend running on http://localhost:${port}/api`);
}
bootstrap();
