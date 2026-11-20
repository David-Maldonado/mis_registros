import { IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  display_name?: string | null;

  @IsUUID()
  default_currency_id!: string;

  @IsString()
  @MaxLength(100)
  timezone!: string;
}
