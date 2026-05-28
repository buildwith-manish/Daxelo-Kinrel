import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import type { Response } from 'express';

/**
 * SecurityHeadersInterceptor
 *
 * Adds security-related HTTP headers to every outgoing response:
 *  - X-Content-Type-Options: nosniff          — prevents MIME-type sniffing
 *  - X-Frame-Options: DENY                    — prevents clickjacking via iframes
 *  - X-XSS-Protection: 1; mode=block          — enables browser XSS filter
 *  - Referrer-Policy: strict-origin-when-cross-origin — limits referrer leakage
 *  - Content-Security-Policy: default-src 'self'      — restricts resource loading
 *
 * Also removes the X-Powered-By header to avoid fingerprinting.
 */
@Injectable()
export class SecurityHeadersInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const response = context.switchToHttp().getResponse<Response>();

    // Remove X-Powered-By to avoid server fingerprinting
    response.removeHeader('X-Powered-By');

    return next.handle().pipe(
      tap(() => {
        // Prevent MIME-type sniffing
        response.setHeader('X-Content-Type-Options', 'nosniff');

        // Prevent clickjacking via iframes
        response.setHeader('X-Frame-Options', 'DENY');

        // Enable browser XSS filter
        response.setHeader('X-XSS-Protection', '1; mode=block');

        // Limit referrer information leakage
        response.setHeader(
          'Referrer-Policy',
          'strict-origin-when-cross-origin',
        );

        // Restrict resource loading to same origin
        response.setHeader(
          'Content-Security-Policy',
          "default-src 'self'",
        );
      }),
    );
  }
}
