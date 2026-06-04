/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.spec.ts'],
  transform: {
    '^.+\\.ts$': ['ts-jest', {
      tsconfig: 'tsconfig.json',
      diagnostics: {
        // Only show diagnostics for test files, not source files
        warnOnly: true,
      },
    }],
  },
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^@modules/(.*)$': '<rootDir>/src/modules/$1',
    '^@common/(.*)$': '<rootDir>/src/common/$1',
    '^@prisma/client$': '<rootDir>/src/__mocks__/prisma-client.ts',
  },
  collectCoverageFrom: [
    'src/**/*.service.ts',
    '!src/**/*.spec.ts',
    '!src/**/index.ts',
  ],
};
