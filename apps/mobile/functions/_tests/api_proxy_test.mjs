import assert from 'node:assert/strict';
import test from 'node:test';

import { apiTarget, proxyApiRequest } from '../_shared/api_proxy.mjs';

const pagesUrl = 'https://restaurant-finance-beta.pages.dev';
const apiOrigin = 'https://restaurantmanager-production-6231.up.railway.app';

test('maps only versioned API paths to the fixed configured origin', () => {
  assert.equal(
    apiTarget(`${pagesUrl}/api/v1/auth/refresh?attempt=1`, apiOrigin).toString(),
    `${apiOrigin}/api/v1/auth/refresh?attempt=1`,
  );
  assert.equal(apiTarget(`${pagesUrl}/not-api`, apiOrigin), null);
  assert.throws(() => apiTarget(`${pagesUrl}/api/v1/auth/me`, 'http://bad.test'));
});

test('forwards cookies and authorization without forwarding infrastructure headers', async () => {
  let forwarded;
  const response = await proxyApiRequest(
    new Request(`${pagesUrl}/api/v1/auth/refresh`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer access-token',
        Cookie: 'fundwell_refresh=refresh-token',
        Origin: pagesUrl,
        Host: 'attacker.example',
        'CF-Connecting-IP': '192.0.2.1',
      },
      body: '{}',
    }),
    { API_ORIGIN: apiOrigin },
    async (request) => {
      forwarded = request;
      return new Response('{"accessToken":"replacement"}', {
        headers: {
          'Content-Type': 'application/json',
          'Set-Cookie': 'fundwell_refresh=rotated; Path=/api/v1/auth; HttpOnly; Secure; SameSite=None',
        },
      });
    },
  );

  assert.equal(forwarded.url, `${apiOrigin}/api/v1/auth/refresh`);
  assert.equal(forwarded.headers.get('Origin'), pagesUrl);
  assert.equal(forwarded.headers.get('X-FundWell-Client'), 'web');
  assert.equal(forwarded.headers.get('Authorization'), 'Bearer access-token');
  assert.equal(forwarded.headers.get('Cookie'), 'fundwell_refresh=refresh-token');
  assert.equal(forwarded.headers.get('Host'), null);
  assert.equal(forwarded.headers.get('CF-Connecting-IP'), null);
  assert.match(response.headers.get('Set-Cookie'), /fundwell_refresh=rotated/);
  assert.equal(response.headers.get('Cache-Control'), 'no-store, max-age=0');
});

test('rejects cross-origin mutations and never accepts a caller-supplied target', async () => {
  let called = false;
  const response = await proxyApiRequest(
    new Request(`${pagesUrl}/api/v1/auth/logout?target=https://evil.example`, {
      method: 'POST',
      headers: { Origin: 'https://evil.example' },
      body: '{}',
    }),
    { API_ORIGIN: apiOrigin },
    async () => {
      called = true;
      return new Response();
    },
  );
  assert.equal(response.status, 403);
  assert.equal(called, false);
});

test('rejects mutation requests that omit the browser Origin header', async () => {
  const response = await proxyApiRequest(
    new Request(`${pagesUrl}/api/v1/auth/refresh`, {
      method: 'POST',
      body: '{}',
    }),
    { API_ORIGIN: apiOrigin },
    async () => new Response(),
  );
  assert.equal(response.status, 403);
});
