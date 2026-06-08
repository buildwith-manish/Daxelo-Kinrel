module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'security', 'perf', 'refactor',
      'test', 'docs', 'ci', 'chore', 'revert'
    ]],
  },
};
