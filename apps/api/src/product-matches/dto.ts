import { IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class ProductMatchQuery {
  @IsUUID()
  restaurantLocationId!: string;
}

export class RenameProductGroupDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  displayName!: string;
}
