import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { EnvironmentVariables } from './config/env.validation';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  const configService = app.get(ConfigService<EnvironmentVariables, true>);
  const corsOrigin = configService.get('CORS_ORIGIN', { infer: true });
  const port = configService.get('PORT', { infer: true });

  const allowedOrigins = corsOrigin
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
  const allowLocalhostAnyPort = allowedOrigins.some(
    (item) => item.includes('localhost') || item.includes('127.0.0.1'),
  );

  app.enableCors({
    origin:
      corsOrigin === '*'
        ? true
        : (origin: string | undefined, callback: (err: Error | null, allow?: boolean) => void) => {
            if (!origin || allowedOrigins.includes(origin)) {
              callback(null, true);
              return;
            }
            if (allowLocalhostAnyPort && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
              callback(null, true);
              return;
            }
            callback(new Error('Origen no permitido por CORS.'));
          },
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  await app.listen(port);
}

bootstrap();
