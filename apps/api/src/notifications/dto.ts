import { DevicePushPlatform } from '@prisma/client';
import { IsBoolean, IsEnum, IsOptional, IsString, IsUUID, Matches } from 'class-validator';
export class NotificationQuery { @IsOptional() @IsBoolean() unreadOnly?: boolean; }
export class PreferenceQuery { @IsUUID() organizationId!: string; @IsOptional() @IsUUID() restaurantLocationId?: string; }
export class UpdatePreferenceDto extends PreferenceQuery { @IsOptional() @IsBoolean() pushEnabled?: boolean; @IsOptional() @IsBoolean() weeklyDigestEnabled?: boolean; @IsOptional() @IsBoolean() priceAlertsEnabled?: boolean; @IsOptional() @IsBoolean() savingsAlertsEnabled?: boolean; @IsOptional() @IsBoolean() costAlertsEnabled?: boolean; @IsOptional() @IsBoolean() syncAlertsEnabled?: boolean; @IsOptional() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) quietHoursStart?: string | null; @IsOptional() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) quietHoursEnd?: string | null; @IsOptional() @IsString() timezone?: string; }
export class RegisterPushTokenDto { @IsEnum(DevicePushPlatform) platform!: DevicePushPlatform; @IsString() token!: string; }
