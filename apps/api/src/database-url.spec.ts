import { pooledDatabaseUrl } from './database-url';

describe('pooledDatabaseUrl', () => {
  it('adds conservative Prisma pool settings without exposing or changing credentials', () => {
    const result = new URL(
      pooledDatabaseUrl(
        'postgresql://restaurant:secret@example.internal:5432/fundwell?schema=public',
      )!,
    );

    expect(result.username).toBe('restaurant');
    expect(result.password).toBe('secret');
    expect(result.searchParams.get('schema')).toBe('public');
    expect(result.searchParams.get('connection_limit')).toBe('5');
    expect(result.searchParams.get('pool_timeout')).toBe('20');
  });

  it('respects explicit URL pool settings', () => {
    const result = new URL(
      pooledDatabaseUrl(
        'postgresql://example.internal/fundwell?connection_limit=3&pool_timeout=8',
        '9',
        '30',
      )!,
    );

    expect(result.searchParams.get('connection_limit')).toBe('3');
    expect(result.searchParams.get('pool_timeout')).toBe('8');
  });

  it('supports environment-style overrides and safe fallbacks', () => {
    const overridden = new URL(
      pooledDatabaseUrl('postgresql://example.internal/fundwell', '2', '12')!,
    );
    expect(overridden.searchParams.get('connection_limit')).toBe('2');
    expect(overridden.searchParams.get('pool_timeout')).toBe('12');

    const fallback = new URL(
      pooledDatabaseUrl('postgresql://example.internal/fundwell', '0', 'invalid')!,
    );
    expect(fallback.searchParams.get('connection_limit')).toBe('5');
    expect(fallback.searchParams.get('pool_timeout')).toBe('20');
  });
});
