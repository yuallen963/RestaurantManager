import { OrganizationRole, PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';
import { randomBytes } from 'crypto';

const prisma = new PrismaClient();
const email = process.env.PRIVATE_BETA_USER_EMAIL?.trim().toLowerCase();
const environment = process.env.TARGET_ENVIRONMENT?.trim();
const dryRun = process.env.DRY_RUN === 'true';
const confirmed = process.env.CONFIRM_PRIVATE_BETA_SETUP === 'YES';
const organizationName = 'Private Account';
const locationName = 'Private Restaurant';

async function inspect() {
  if (!email) throw new Error('PRIVATE_BETA_USER_EMAIL is required');
  if (!environment) throw new Error('TARGET_ENVIRONMENT is required');
  if (!dryRun && !confirmed) throw new Error('Set CONFIRM_PRIVATE_BETA_SETUP=YES to write records');
  const existing = await prisma.user.findUnique({
    where: { email },
    include: { memberships: { include: { organization: { include: { locations: true } } } } },
  });
  if (existing) {
    if (existing.memberships.length !== 1) throw new Error('Refusing existing private user with unexpected memberships');
    const membership = existing.memberships[0];
    if (membership.role !== OrganizationRole.OWNER || membership.organization.name !== organizationName) throw new Error('Refusing to overwrite an unrelated existing user');
    if (membership.organization.locations.length !== 1 || membership.organization.locations[0].name !== locationName) throw new Error('Existing private account does not have exactly the expected restaurant');
  }
  return existing;
}

async function main() {
  const existing = await inspect();
  if (dryRun) {
    console.log(JSON.stringify({ dryRun: true, environment, email, existing: Boolean(existing), organization: organizationName, location: locationName }, null, 2));
    return;
  }
  if (existing) {
    console.log(JSON.stringify({ dryRun: false, idempotent: true, userId: existing.id, organizationId: existing.memberships[0].organizationId, locationId: existing.memberships[0].organization.locations[0].id }, null, 2));
    return;
  }
  const passwordHash = await argon2.hash(randomBytes(48).toString('base64url'));
  const created = await prisma.$transaction(async (tx) => {
    const user = await tx.user.create({ data: { email: email!, passwordHash, firstName: 'Private', lastName: 'Account', emailVerifiedAt: new Date() } });
    const organization = await tx.organization.create({ data: { name: organizationName, memberships: { create: { userId: user.id, role: OrganizationRole.OWNER } } } });
    const location = await tx.restaurantLocation.create({ data: { organizationId: organization.id, name: locationName, timezone: 'America/Detroit', invoiceEmailToken: randomBytes(24).toString('hex') } });
    await tx.onboardingState.create({ data: { userId: user.id, organizationId: organization.id, restaurantLocationId: location.id, currentStep: 5, onboardingCompletedAt: new Date() } });
    return { user, organization, location };
  });
  console.log(JSON.stringify({ dryRun: false, idempotent: false, userId: created.user.id, organizationId: created.organization.id, locationId: created.location.id }, null, 2));
}

main().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }).finally(() => prisma.$disconnect());
