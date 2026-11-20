import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { throwIfSupabaseError } from '../common/supabase-error.util';
import { SupabaseService } from '../supabase/supabase.service';

@Controller('currencies')
@UseGuards(SupabaseAuthGuard)
export class CurrenciesController {
  constructor(private readonly supabaseService: SupabaseService) {}

  @Get()
  async findAll(@CurrentUser() user: AuthenticatedUser) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client
      .from('currencies')
      .select('id, code, name, symbol, decimal_places, is_active')
      .eq('is_active', true)
      .order('code', { ascending: true });

    throwIfSupabaseError(error);
    return data;
  }
}
