import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class MonthlyReportQueryDto {
  @Type(() => Number)
  @IsInt()
  @Min(1970)
  @Max(2100)
  year!: number;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(12)
  month!: number;
}

export class AnnualCategoryBreakdownQueryDto {
  @Type(() => Number)
  @IsInt()
  @Min(1970)
  @Max(2100)
  year!: number;

  @IsIn(['income', 'expense'])
  type!: 'income' | 'expense';

  @IsOptional()
  @IsString()
  currency_code?: string;
}

