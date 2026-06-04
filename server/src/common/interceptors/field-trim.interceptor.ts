import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

/**
 * Removes null and undefined fields from API responses.
 * This saves bandwidth — null fields are not needed by the Flutter client.
 * Empty strings and empty arrays are kept (they may be meaningful).
 */
@Injectable()
export class FieldTrimInterceptor<T> implements NestInterceptor<T, any> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      map((data) => this.trimNulls(data)),
    );
  }

  private trimNulls(value: any): any {
    if (value === null || value === undefined) {
      return undefined; // Will be omitted by JSON.stringify
    }

    if (Array.isArray(value)) {
      return value.map((item) => this.trimNulls(item));
    }

    if (typeof value === 'object' && value.constructor === Object) {
      const result: Record<string, any> = {};
      for (const [key, val] of Object.entries(value)) {
        if (val !== null && val !== undefined) {
          result[key] = this.trimNulls(val);
        }
      }
      return result;
    }

    return value;
  }
}
