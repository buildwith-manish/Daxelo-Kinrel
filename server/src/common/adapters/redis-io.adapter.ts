import { IoAdapter } from '@nestjs/platform-socket.io';
import { ServerOptions } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';
import { Logger } from '@nestjs/common';

/**
 * Custom WebSocket adapter that adds Redis pub/sub support for multi-instance
 * deployments. When REDIS_URL is configured and NODE_ENV is production,
 * Socket.IO events are broadcast across all server instances via Redis.
 *
 * Without Redis (development / single-instance), the default in-memory
 * adapter is used — no behavioural change.
 */
export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor: ReturnType<typeof createAdapter> | null = null;

  async connectToRedis(redisUrl: string): Promise<void> {
    try {
      const pubClient = createClient({ url: redisUrl });
      const subClient = pubClient.duplicate();

      await Promise.all([pubClient.connect(), subClient.connect()]);

      this.adapterConstructor = createAdapter(pubClient, subClient);
      this.logger.log('Socket.IO Redis adapter connected — multi-instance WS enabled');
    } catch (err: any) {
      this.logger.warn(`Socket.IO Redis adapter failed: ${err.message} — falling back to default adapter`);
    }
  }

  createIOServer(port: number, options?: ServerOptions): any {
    const server = super.createIOServer(port, options);

    if (this.adapterConstructor) {
      server.adapter(this.adapterConstructor);
    }

    return server;
  }
}
