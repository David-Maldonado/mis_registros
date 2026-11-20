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
import { CreateCategoryDto, UpdateCategoryDto } from './dto/category.dto';

@Controller('categories')
@UseGuards(SupabaseAuthGuard)
export class CategoriesController {
  constructor(private readonly supabaseService: SupabaseService) {}

  @Get()
  async findAll(@CurrentUser() user: AuthenticatedUser) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client
      .from('categories')
      .select('id, parent_id, name, type, is_active, created_at, updated_at')
      .order('type', { ascending: true })
      .order('name', { ascending: true });

    throwIfSupabaseError(error);
    return data;
  }

  @Post()
  async create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateCategoryDto) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('create_category', {
      p_name: dto.name,
      p_type: dto.type,
      p_parent_id: dto.parent_id ?? null,
    });

    throwIfSupabaseError(error);
    return data;
  }

  @Patch(':id')
  async update(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCategoryDto,
  ) {
    const client = this.supabaseService.getUserClient(user.accessToken);
    const { data, error } = await client.rpc('update_category', {
      p_category_id: id,
      p_name: dto.name,
      p_type: dto.type,
      p_parent_id: dto.parent_id ?? null,
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
    const { data, error } = await client.rpc('delete_category', {
      p_category_id: id,
    });

    throwIfSupabaseError(error);
    return { deleted: Boolean(data) };
  }
}
