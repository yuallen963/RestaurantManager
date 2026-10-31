import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { JwtAuthGuard } from '../src/auth/jwt-auth.guard';

const context = (method: string) => {
  const request: any = { method, headers: { authorization: 'Bearer demo-token' } };
  return {
    request,
    context: { switchToHttp: () => ({ getRequest: () => request }) } as ExecutionContext,
  };
};

describe('public demo read-only enforcement', () => {
  const originalMode = process.env.PUBLIC_DEMO_MODE;
  beforeEach(() => { process.env.PUBLIC_DEMO_MODE = 'true'; });
  afterEach(() => {
    if (originalMode === undefined) delete process.env.PUBLIC_DEMO_MODE;
    else process.env.PUBLIC_DEMO_MODE = originalMode;
  });
  const prisma: any = {
    user: { findFirst: jest.fn().mockResolvedValue({ id: 'demo-user', email: 'demo@profitlens.local' }) },
  };
  const jwt: any = {
    verifyAsync: jest.fn().mockResolvedValue({ sub: 'demo-user', publicDemo: true }),
  };

  it.each(['GET', 'HEAD', 'OPTIONS'])('allows demo %s requests', async (method) => {
    const request = context(method);
    await expect(new JwtAuthGuard(jwt, prisma).canActivate(request.context)).resolves.toBe(true);
    expect(request.request.user.publicDemo).toBe(true);
  });

  it.each(['POST', 'PATCH', 'PUT', 'DELETE'])('rejects demo %s requests before controller logic', async (method) => {
    await expect(new JwtAuthGuard(jwt, prisma).canActivate(context(method).context)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('preserves normal authenticated mutations', async () => {
    const standardJwt: any = { verifyAsync: jest.fn().mockResolvedValue({ sub: 'owner-user' }) };
    prisma.user.findFirst.mockResolvedValueOnce({ id: 'owner-user', email: 'owner@example.com' });
    await expect(new JwtAuthGuard(standardJwt, prisma).canActivate(context('POST').context)).resolves.toBe(true);
  });

  it('rejects previously issued demo tokens as soon as public mode is disabled', async () => {
    process.env.PUBLIC_DEMO_MODE = 'false';
    await expect(new JwtAuthGuard(jwt, prisma).canActivate(context('GET').context)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects normal tokens for the synthetic demo identity', async () => {
    const ordinaryJwt: any = { verifyAsync: jest.fn().mockResolvedValue({ sub: 'demo-user' }) };
    await expect(new JwtAuthGuard(ordinaryJwt, prisma).canActivate(context('GET').context)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('requires a verified, active user with an organization membership', async () => {
    prisma.user.findFirst.mockResolvedValueOnce(null);
    const ordinaryJwt: any = { verifyAsync: jest.fn().mockResolvedValue({ sub: 'former-member' }) };
    await expect(new JwtAuthGuard(ordinaryJwt, prisma).canActivate(context('GET').context)).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ memberships: { some: { organization: { archivedAt: null } } } }) }));
  });
});
