// Mock for @prisma/client — avoids needing a real database in tests
export class PrismaClient {
  $connect = jest.fn();
  $disconnect = jest.fn();
  $transaction = jest.fn();
  $on = jest.fn();
}
