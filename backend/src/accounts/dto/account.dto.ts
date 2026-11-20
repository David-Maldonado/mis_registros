import {
  IsBoolean,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
} from 'class-validator';

const DECIMAL_REGEX = /^-?\d{1,14}(\.\d{1,4})?$/;
const POSITIVE_DECIMAL_REGEX = /^\d{1,14}(\.\d{1,4})?$/;

export class CreateAccountDto {
  @IsUUID()
  currency_id!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

  @IsIn(['cash', 'bank', 'e_wallet', 'credit_card'])
  type!: 'cash' | 'bank' | 'e_wallet' | 'credit_card';

  @IsOptional()
  @IsString()
  @Matches(DECIMAL_REGEX, {
    message: 'initial_balance debe ser un número decimal válido con hasta 4 decimales.',
  })
  initial_balance?: string;

  @IsOptional()
  @IsString()
  @Matches(POSITIVE_DECIMAL_REGEX, {
    message: 'credit_limit debe ser un número decimal positivo con hasta 4 decimales.',
  })
  credit_limit?: string | null;
}

export class UpdateAccountDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

  @IsString()
  @Matches(DECIMAL_REGEX, {
    message: 'initial_balance debe ser un número decimal válido con hasta 4 decimales.',
  })
  initial_balance!: string;

  @IsOptional()
  @IsString()
  @Matches(POSITIVE_DECIMAL_REGEX, {
    message: 'credit_limit debe ser un número decimal positivo con hasta 4 decimales.',
  })
  credit_limit?: string | null;

  @IsBoolean()
  is_active!: boolean;
}
