/**
 * Daxelo-Kinrel — NestJS bootstrap.
 */
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableCors();
  await app.listen(process.env.PORT ?? 3000);
  // eslint-disable-next-line no-console
  console.log(`Daxelo-Kinrel server running on port ${process.env.PORT ?? 3000}`);
}
bootstrap();
