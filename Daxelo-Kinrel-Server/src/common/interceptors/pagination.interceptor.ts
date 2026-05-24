import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import type { Request } from 'express';
import { v4 as uuidv4 } from 'uuid';

interface PaginatedData<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

interface PaginatedResponse<T> {
  data: T[];
  meta: {
    requestId: string;
    timestamp: string;
    version: string;
    pagination: {
      total: number;
      page: number;
      limit: number;
      totalPages: number;
      hasNextPage: boolean;
      hasPrevPage: boolean;
    };
  };
}

@Injectable()
export class PaginationInterceptor<T>
  implements NestInterceptor<PaginatedData<T>, PaginatedResponse<T>>
{
  private readonly version = '1.0.0';

  intercept(
    context: ExecutionContext,
    next: CallHandler,
  ): Observable<PaginatedResponse<T>> {
    const request = context.switchToHttp().getRequest<Request>();
    const requestId = (request.headers['x-request-id'] as string) || uuidv4();

    return next.handle().pipe(
      map((result: PaginatedData<T>) => ({
        data: result.items,
        meta: {
          requestId,
          timestamp: new Date().toISOString(),
          version: this.version,
          pagination: {
            total: result.total,
            page: result.page,
            limit: result.limit,
            totalPages: result.totalPages,
            hasNextPage: result.page < result.totalPages,
            hasPrevPage: result.page > 1,
          },
        },
      })),
    );
  }
}
