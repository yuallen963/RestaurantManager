const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);
const STRIPPED_REQUEST_HEADERS = new Set([
  'cf-connecting-ip',
  'cf-ipcountry',
  'cf-ray',
  'cf-visitor',
  'forwarded',
  'host',
  'x-forwarded-for',
  'x-forwarded-host',
  'x-forwarded-proto',
]);

function errorResponse(status, message) {
  return new Response(JSON.stringify({ message }), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store, max-age=0',
    },
  });
}

export function apiTarget(requestUrl, configuredOrigin) {
  if (!configuredOrigin) throw new Error('API_ORIGIN is not configured');
  const origin = new URL(configuredOrigin);
  if (origin.protocol !== 'https:' || origin.username || origin.password ||
      origin.pathname !== '/' || origin.search || origin.hash) {
    throw new Error('API_ORIGIN must be an HTTPS origin without a path');
  }

  const incoming = new URL(requestUrl);
  if (!incoming.pathname.startsWith('/api/v1/')) return null;
  return new URL(`${incoming.pathname}${incoming.search}`, origin);
}

export async function proxyApiRequest(request, env, fetchImpl = fetch) {
  const incoming = new URL(request.url);
  const origin = request.headers.get('Origin');

  // A browser mutation must originate from this exact Pages deployment. This
  // keeps the refresh cookie usable without turning the proxy into a CSRF
  // relay for another website.
  if ((!SAFE_METHODS.has(request.method) && origin !== incoming.origin) ||
      (origin && origin !== incoming.origin)) {
    return errorResponse(403, 'Request origin is not allowed');
  }

  let target;
  try {
    target = apiTarget(request.url, env.API_ORIGIN);
  } catch (_) {
    return errorResponse(503, 'API proxy is not configured');
  }
  if (!target) return errorResponse(404, 'API route not found');

  const headers = new Headers(request.headers);
  for (const name of STRIPPED_REQUEST_HEADERS) headers.delete(name);
  // NestJS validates this exact public origin for browser session requests.
  headers.set('Origin', incoming.origin);
  headers.set('X-FundWell-Client', 'web');

  const body = request.method === 'GET' || request.method === 'HEAD'
    ? undefined
    : await request.arrayBuffer();
  const upstream = new Request(target, {
    method: request.method,
    headers,
    body,
    redirect: 'manual',
  });
  const response = await fetchImpl(upstream, {
    cf: { cacheEverything: false, cacheTtl: 0 },
  });
  const responseHeaders = new Headers(response.headers);
  responseHeaders.set('Cache-Control', 'no-store, max-age=0');
  responseHeaders.set('Pragma', 'no-cache');
  responseHeaders.set('Vary', 'Origin, Cookie, Authorization');
  responseHeaders.set('X-Content-Type-Options', 'nosniff');
  responseHeaders.set('X-Frame-Options', 'DENY');
  responseHeaders.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  responseHeaders.set(
    'Permissions-Policy',
    'camera=(), microphone=(), geolocation=(), payment=()',
  );
  responseHeaders.set(
    'Strict-Transport-Security',
    'max-age=31536000; includeSubDomains',
  );

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: responseHeaders,
  });
}
