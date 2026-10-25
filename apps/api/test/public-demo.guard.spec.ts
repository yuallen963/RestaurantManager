import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { JwtAuthGuard } from '../src/auth/jwt-auth.guard';

const context = (method: string) => {
  const request: any = { method, headers: { authorization: 'Bearer demo-token' } };
  return {
    request,
    context: { switchToHttp: () => ({ getRequest: () => request }) } as ExecutionContext,
  };
};

describe('public demo read-only enforcement', () => {
  const prisma: any = {
    user: { findFirst: jest.fn().mockResolvedValue({ id: 'demo-user' }) },
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
    await expect(new JwtAuthGuard(standardJwt, prisma).canActivate(context('POST').context)).resolves.toBe(true);
  });
});
