import {
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { Type } from 'class-transformer';

const POSITIVE_DECIMAL_REGEX = /^\d{1,14}(\.\d{1,4})?$/;
const SIGNED_DECIMAL_REGEX = /^-?\d{1,14}(\.\d{1,4})?$/;

export class ListTransactionsQueryDto {
  @IsOptional()
  @IsISO8601()
  cursor_occurred_at?: string;

  @IsOptional()
  @IsUUID()
  cursor_id?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}

export class CreateIncomeOrExpenseDto {
  @IsUUID()
  client_request_id!: string;

  @IsUUID()
  account_id!: string;

  @IsUUID()
  category_id!: string;

  @IsString()
  @Matches(POSITIVE_DECIMAL_REGEX, {
    message: 'amount debe ser un número decimal positivo con hasta 4 decimales.',
  })
  amount!: string;

  @IsISO8601()
  occurred_at!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string | null;
}

export class CreateTransferDto {
  @IsUUID()
  client_request_id!: string;

  @IsUUID()
  from_account_id!: string;

  @IsUUID()
  to_account_id!: string;

  @IsString()
  @Matches(POSITIVE_DECIMAL_REGEX, {
    message: 'amount debe ser un número decimal positivo con hasta 4 decimales.',
  })
  amount!: string;

  @IsISO8601()
  occurred_at!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string | null;
}

export class CreateRefundDto {
  @IsUUID()
  client_request_id!: string;

  @IsUUID()
  original_transaction_id!: string;

  @IsUUID()
  account_id!: string;

  @IsString()
  @Matches(POSITIVE_DECIMAL_REGEX, {
    message: 'amount debe ser un número decimal positivo con hasta 4 decimales.',
  })
  amount!: string;

  @IsISO8601()
  occurred_at!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string | null;
}

export class CreateAdjustmentDto {
  @IsUUID()
  client_request_id!: string;

  @IsUUID()
  account_id!: string;

  @IsString()
  @Matches(SIGNED_DECIMAL_REGEX, {
    message: 'signed_amount debe ser un número decimal válido con hasta 4 decimales.',
  })
  signed_amount!: string;

  @IsISO8601()
  occurred_at!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string | null;
}

export class ReplaceTransactionDto {
  @IsUUID()
  client_request_id!: string;

  @IsUUID()
  account_id!: string;

  @IsString()
  @Matches(SIGNED_DECIMAL_REGEX, {
    message: 'amount debe ser un número decimal válido con hasta 4 decimales.',
  })
  amount!: string;

  @IsISO8601()
  occurred_at!: string;

  @IsOptional()
  @IsUUID()
  category_id?: string | null;

  @IsOptional()
  @IsUUID()
  to_account_id?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string | null;
}

export class UpdateTransactionDescriptionDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string | null;
}

export class VoidTransactionDto {
  @IsOptional()
  @IsString()
  @MaxLength(300)
  void_reason?: string | null;
}
