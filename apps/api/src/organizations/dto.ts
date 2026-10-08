import { IsEnum, IsString, MinLength } from 'class-validator'; import { OrganizationRole } from '@prisma/client';
export class CreateOrganizationDto { @IsString() @MinLength(2) name!: string; }
export class AddMemberDto { @IsString() userId!: string; @IsEnum(OrganizationRole) role!: OrganizationRole; }
