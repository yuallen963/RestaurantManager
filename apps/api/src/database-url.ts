const DEFAULT_CONNECTION_LIMIT = 5;
const DEFAULT_POOL_TIMEOUT_SECONDS = 20;

function positiveInteger(value: string | undefined, fallback: number) {
  const parsed = Number.parseInt(value ?? '', 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

export function pooledDatabaseUrl(
  rawUrl = process.env.DATABASE_URL,
  connectionLimit = process.env.DATABASE_CONNECTION_LIMIT,
  poolTimeout = process.env.DATABASE_POOL_TIMEOUT_SECONDS,
) {
  if (!rawUrl) return rawUrl;
  const url = new URL(rawUrl);
  if (!url.searchParams.has('connection_limit')) {
    url.searchParams.set(
      'connection_limit',
      String(positiveInteger(connectionLimit, DEFAULT_CONNECTION_LIMIT)),
    );
  }
  if (!url.searchParams.has('pool_timeout')) {
    url.searchParams.set(
      'pool_timeout',
      String(positiveInteger(poolTimeout, DEFAULT_POOL_TIMEOUT_SECONDS)),
    );
  }
  return url.toString();
}
