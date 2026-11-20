import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { throwIfSupabaseError } from '../common/supabase-error.util';
import { SupabaseService } from '../supabase/supabase.service';
import { CreateAccountDto, UpdateAccountDto } from './dto/account.dto';

@Controller('accounts')
@UseGuards(SupabaseAuthGuard)
export class AccountsController {
  constructor(private readonly supabaseService: SupabaseService) {}

  @Get()
  async findAll(@CurrentUser() user: AuthenticatedUser) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client
      .from('accounts')
      .select(
        'id, currency_id, name, type, initial_balance, credit_limit, is_active, created_at, updated_at',
      )
      .order('name', { ascending: true });

    throwIfSupabaseError(error);
    return data;
  }

  @Get('balances')
  async findBalances(@CurrentUser() user: AuthenticatedUser) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client
      .from('account_balances')
      .select('*')
      .order('name', { ascending: true });

    throwIfSupabaseError(error);
    return data;
  }

  @Post()
  async create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateAccountDto) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('create_account', {
      p_currency_id: dto.currency_id,
      p_name: dto.name,
      p_type: dto.type,
      p_initial_balance: dto.initial_balance ?? '0',
      p_credit_limit: dto.credit_limit ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Patch(':id')
  async update(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateAccountDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('update_account', {
      p_account_id: id,
      p_name: dto.name,
      p_initial_balance: dto.initial_balance,
      p_credit_limit: dto.credit_limit ?? null,
      p_is_active: dto.is_active,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Delete(':id')
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('delete_account', {
      p_account_id: id,
    });

    throwIfSupabaseError(error);
    return { deleted: Boolean(data) };
  }
}
