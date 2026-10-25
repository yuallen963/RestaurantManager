import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { AuthController } from '../src/auth/auth.controller';

const webRequest = (extra: Record<string, string> = {}) => ({
  ip: '127.0.0.1',
  headers: {
    'x-fundwell-client': 'web',
    origin: 'https://app.fundwell.test',
    ...extra,
  },
});

const response = () => ({ setHeader: jest.fn() });

describe('AuthController browser sessions', () => {
  const previousOrigin = process.env.CORS_ORIGIN;

  beforeEach(() => {
    process.env.CORS_ORIGIN = 'https://app.fundwell.test';
  });

  afterAll(() => {
    process.env.CORS_ORIGIN = previousOrigin;
  });

  function setup() {
    const auth: any = {
      login: jest.fn().mockResolvedValue({
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'Bearer',
      }),
      refresh: jest.fn().mockResolvedValue({
        accessToken: 'next-access',
        refreshToken: 'next-refresh',
        tokenType: 'Bearer',
      }),
      logout: jest.fn().mockResolvedValue(undefined),
      sharedTestSession: jest.fn(),
      publicDemoSession: jest.fn().mockResolvedValue({ accessToken: 'demo-access', tokenType: 'Bearer', accountMode: 'demo' }),
    };
    const limiter: any = { check: jest.fn() };
    const security: any = {};
    return { auth, controller: new AuthController(auth, limiter, security) };
  }

  it('stores a browser refresh token only in an HttpOnly cookie', async () => {
    const { controller } = setup();
    const res = response();

    const result = await controller.login(
      webRequest(),
      res,
      { email: 'owner@example.com', password: 'long-enough-password' },
    );

    expect(result).toEqual({ accessToken: 'access-token', tokenType: 'Bearer' });
    expect(res.setHeader).toHaveBeenCalledWith(
      'Set-Cookie',
      expect.stringMatching(/^fundwell_refresh=.*HttpOnly.*SameSite=/),
    );
  });

  it('rotates the browser cookie without accepting a body token', async () => {
    const { controller, auth } = setup();
    const res = response();
    const result = await controller.refresh(
      webRequest({ cookie: 'other=x; fundwell_refresh=cookie-refresh' }),
      res,
      {},
    );

    expect(auth.refresh).toHaveBeenCalledWith('cookie-refresh');
    expect(result).toEqual({ accessToken: 'next-access', tokenType: 'Bearer' });
    expect(res.setHeader).toHaveBeenCalledWith(
      'Set-Cookie',
      expect.stringContaining('next-refresh'),
    );
  });

  it('rejects cookie-backed requests from an unapproved web origin', () => {
    const { controller } = setup();
    expect(() =>
      controller.refresh(
        webRequest({ origin: 'https://attacker.example', cookie: 'fundwell_refresh=token' }),
        response(),
        {},
      ),
    ).toThrow(ForbiddenException);
  });

  it('never exposes the shared beta session endpoint to web clients', () => {
    const { controller } = setup();
    expect(() => controller.sharedTestSession(webRequest())).toThrow(NotFoundException);
  });

  it('exposes public demo access only to the approved web origin', async () => {
    const { controller, auth } = setup();
    await expect(controller.publicDemoSession(webRequest())).resolves.toEqual({
      accessToken: 'demo-access', tokenType: 'Bearer', accountMode: 'demo',
    });
    expect(auth.publicDemoSession).toHaveBeenCalledTimes(1);
    expect(() => controller.publicDemoSession({ ip: 'native', headers: {} })).toThrow(NotFoundException);
    expect(() => controller.publicDemoSession(webRequest({ origin: 'https://attacker.example' }))).toThrow(ForbiddenException);
  });

  it('forwards the internal client token for native shared beta sessions', () => {
    const { controller, auth } = setup();
    controller.sharedTestSession({
      ip: 'device',
      headers: { 'x-fundwell-shared-test-token': 'internal-client-token' },
    });
    expect(auth.sharedTestSession).toHaveBeenCalledWith('internal-client-token');
  });

  it('preserves the native refresh-token response contract', async () => {
    const { controller } = setup();
    const result = await controller.login(
      { ip: 'device', headers: {} },
      response(),
      { email: 'owner@example.com', password: 'long-enough-password' },
    );
    expect(result).toMatchObject({ refreshToken: 'refresh-token' });
  });
});
