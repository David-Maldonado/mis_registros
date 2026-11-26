import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { throwIfSupabaseError } from '../common/supabase-error.util';
import { SupabaseService } from '../supabase/supabase.service';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Controller('profile')
@UseGuards(SupabaseAuthGuard)
export class ProfilesController {
  constructor(private readonly supabaseService: SupabaseService) {}

  @Get()
  async getOwnProfile(@CurrentUser() user: AuthenticatedUser) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client
      .from('profiles')
      .select('id, display_name, default_currency_id, timezone, created_at, updated_at')
      .eq('id', user.id)
      .single();

    throwIfSupabaseError(error);
    return data;
  }

  @Patch()
  async updateOwnProfile(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpdateProfileDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('update_profile', {
      p_display_name: dto.display_name ?? null,
      p_default_currency_id: dto.default_currency_id,
      p_timezone: dto.timezone,
    });

    throwIfSupabaseError(error);
    return data;
  }
}
