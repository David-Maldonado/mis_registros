import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  InternalServerErrorException,
  NotFoundException,
} from '@nestjs/common';
import { PostgrestError } from '@supabase/supabase-js';

/**
 * Traduce errores de PostgREST / PostgreSQL a excepciones HTTP apropiadas
 * sin exponer detalles internos de infraestructura.
 */
export function throwIfSupabaseError(error: PostgrestError | null): void {
  if (!error) {
    return;
  }

  const code = error.code ?? '';

  if (code === 'PGRST116' || code === 'P0002') {
    throw new NotFoundException(error.message || 'Recurso no encontrado.');
  }

  if (code === '23505') {
    throw new ConflictException(error.message || 'El registro ya existe o entra en conflicto.');
  }

  if (code === '42501') {
    throw new ForbiddenException(
      error.message
        ? `No tienes permisos para realizar esta operación (${error.message}).`
        : 'No tienes permisos para realizar esta operación.',
    );
  }

  if (
    code === '23514' ||
    code === '23503' ||
    code === '23502' ||
    code === '22P02' ||
    code === '22023' ||
    code === '22003'
  ) {
    throw new BadRequestException(error.message || 'Datos o estado inválidos para la operación.');
  }

  throw new InternalServerErrorException('Error al procesar la operación en la base de datos.');
}
