import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { throwIfSupabaseError } from '../common/supabase-error.util';
import { SupabaseService } from '../supabase/supabase.service';
import {
  AnnualCategoryBreakdownQueryDto,
  MonthlyCategoryBreakdownQueryDto,
  MonthlyReportQueryDto,
} from './dto/monthly-report.dto';

@Controller('reports')
@UseGuards(SupabaseAuthGuard)
export class ReportsController {
  constructor(private readonly supabaseService: SupabaseService) {}

  @Get('monthly-summary')
  async getMonthlySummary(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: MonthlyReportQueryDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('get_monthly_summary', {
      p_year: query.year,
      p_month: query.month,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Get('monthly-account-flows')
  async getMonthlyAccountFlows(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: MonthlyReportQueryDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('get_monthly_account_flows', {
      p_year: query.year,
      p_month: query.month,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Get('annual-category-breakdown')
  async getAnnualCategoryBreakdown(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: AnnualCategoryBreakdownQueryDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('get_annual_category_breakdown', {
      p_year: query.year,
      p_type: query.type,
      p_currency_code: query.currency_code ?? 'PYG',
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Get('monthly-category-breakdown')
  async getMonthlyCategoryBreakdown(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: MonthlyCategoryBreakdownQueryDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('get_monthly_category_breakdown', {
      p_year: query.year,
      p_month: query.month,
      p_type: query.type,
      p_currency_code: query.currency_code ?? 'PYG',
    });

    throwIfSupabaseError(error);
    return data;
  }
}
