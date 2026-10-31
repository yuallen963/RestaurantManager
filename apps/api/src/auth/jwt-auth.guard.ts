import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma.service';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService, private readonly prisma: PrismaService) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest();
    const token = request.headers.authorization?.replace(/^Bearer\s+/i, '');
    if (!token) throw new UnauthorizedException('Missing access token');
    try {
      const payload = await this.jwt.verifyAsync(token, { secret: process.env.JWT_ACCESS_SECRET });
      const user = await this.prisma.user.findFirst({
        where: {
          id: payload.sub,
          disabledAt: null,
          deletedAt: null,
          emailVerifiedAt: { not: null },
          memberships: { some: { organization: { archivedAt: null } } },
        },
        select: { id: true, email: true },
      });
      if (!user) throw new Error();
      const demoEmail = (process.env.PUBLIC_DEMO_USER_EMAIL ?? 'demo@profitlens.local').trim().toLowerCase();
      if (payload.publicDemo === true) {
        if (process.env.PUBLIC_DEMO_MODE !== 'true' || user.email !== demoEmail) throw new Error();
      } else if (user.email === demoEmail) {
        // A normal token for the synthetic account must never bypass the demo flag.
        throw new Error();
      }
      if (payload.publicDemo === true && !['GET', 'HEAD', 'OPTIONS'].includes(request.method)) {
        throw new ForbiddenException('Demo access is read-only. Sign in to make changes.');
      }
      request.user = payload;
      return true;
    } catch (error) {
      if (error instanceof ForbiddenException) throw error;
      throw new UnauthorizedException('Invalid or expired access token');
    }
  }
}
