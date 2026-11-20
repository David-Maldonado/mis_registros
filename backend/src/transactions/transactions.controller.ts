import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { throwIfSupabaseError } from '../common/supabase-error.util';
import { SupabaseService } from '../supabase/supabase.service';
import {
  CreateAdjustmentDto,
  CreateIncomeOrExpenseDto,
  CreateRefundDto,
  CreateTransferDto,
  ListTransactionsQueryDto,
  ReplaceTransactionDto,
  UpdateTransactionDescriptionDto,
  VoidTransactionDto,
} from './dto/transaction.dto';

@Controller('transactions')
@UseGuards(SupabaseAuthGuard)
export class TransactionsController {
  constructor(private readonly supabaseService: SupabaseService) {}

  @Get()
  async findAll(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: ListTransactionsQueryDto,
  ) {
    if ((query.cursor_occurred_at && !query.cursor_id) || (!query.cursor_occurred_at && query.cursor_id)) {
      throw new BadRequestException(
        'cursor_occurred_at y cursor_id deben enviarse juntos para paginar.',
      );
    }

    const limit = query.limit ?? 20;
    const client = this.supabaseService.getUserClient(user.accessToken);

    let builder = client
      .from('transactions')
      .select(
        `
        id,
        client_request_id,
        type,
        status,
        currency_id,
        amount,
        category_id,
        related_transaction_id,
        replaces_transaction_id,
        occurred_at,
        description,
        voided_at,
        void_reason,
        created_at,
        updated_at,
        account_movements (
          id,
          account_id,
          signed_amount
        )
      `,
      )
      .order('occurred_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(limit + 1);

    if (query.cursor_occurred_at && query.cursor_id) {
      builder = builder.or(
        `occurred_at.lt.${query.cursor_occurred_at},and(occurred_at.eq.${query.cursor_occurred_at},id.lt.${query.cursor_id})`,
      );
    }

    const { data, error } = await builder;
    throwIfSupabaseError(error);

    const rows = data ?? [];
    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;
    const last = items[items.length - 1];

    return {
      items,
      next_cursor:
        hasMore && last
          ? {
              occurred_at: last.occurred_at,
              id: last.id,
            }
          : null,
    };
  }

  @Post('income')
  async createIncome(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateIncomeOrExpenseDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('create_income', {
      p_client_request_id: dto.client_request_id,
      p_account_id: dto.account_id,
      p_category_id: dto.category_id,
      p_amount: dto.amount,
      p_occurred_at: dto.occurred_at,
      p_description: dto.description ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Post('expense')
  async createExpense(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateIncomeOrExpenseDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('create_expense', {
      p_client_request_id: dto.client_request_id,
      p_account_id: dto.account_id,
      p_category_id: dto.category_id,
      p_amount: dto.amount,
      p_occurred_at: dto.occurred_at,
      p_description: dto.description ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Post('transfer')
  async createTransfer(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateTransferDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('create_transfer', {
      p_client_request_id: dto.client_request_id,
      p_from_account_id: dto.from_account_id,
      p_to_account_id: dto.to_account_id,
      p_amount: dto.amount,
      p_occurred_at: dto.occurred_at,
      p_description: dto.description ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Post('refund')
  async createRefund(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateRefundDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('create_refund', {
      p_client_request_id: dto.client_request_id,
      p_original_transaction_id: dto.original_transaction_id,
      p_account_id: dto.account_id,
      p_amount: dto.amount,
      p_occurred_at: dto.occurred_at,
      p_description: dto.description ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Post('adjustment')
  async createAdjustment(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateAdjustmentDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('create_adjustment', {
      p_client_request_id: dto.client_request_id,
      p_account_id: dto.account_id,
      p_signed_amount: dto.signed_amount,
      p_occurred_at: dto.occurred_at,
      p_description: dto.description ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Put(':id')
  async replace(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReplaceTransactionDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('replace_transaction', {
      p_client_request_id: dto.client_request_id,
      p_transaction_id: id,
      p_account_id: dto.account_id,
      p_amount: dto.amount,
      p_occurred_at: dto.occurred_at,
      p_category_id: dto.category_id ?? null,
      p_to_account_id: dto.to_account_id ?? null,
      p_description: dto.description ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Patch(':id/description')
  async updateDescription(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateTransactionDescriptionDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('update_transaction_description', {
      p_transaction_id: id,
      p_description: dto.description ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Post(':id/void')
  async voidTransaction(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: VoidTransactionDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('void_transaction', {
      p_transaction_id: id,
      p_void_reason: dto.void_reason ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }
}
