import { ForbiddenException } from '@nestjs/common';
import { InvitationController } from '../src/auth/invitation.controller';
import { OrganizationsController } from '../src/organizations/organizations.controller';

describe('public demo team privacy', () => {
  it('does not expose member identities to public-demo tokens', () => {
    const service: any = { members: jest.fn() };
    const controller = new OrganizationsController(service);
    expect(() => controller.members({ sub: 'demo-user', publicDemo: true }, 'demo-org')).toThrow(ForbiddenException);
    expect(service.members).not.toHaveBeenCalled();
  });

  it('does not expose invitation emails to public-demo tokens', () => {
    const service: any = { list: jest.fn() };
    const controller = new InvitationController(service);
    expect(() => controller.list({ sub: 'demo-user', publicDemo: true }, 'demo-org')).toThrow(ForbiddenException);
    expect(service.list).not.toHaveBeenCalled();
  });
});
