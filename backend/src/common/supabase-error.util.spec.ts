import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  InternalServerErrorException,
  NotFoundException,
} from '@nestjs/common';
import { PostgrestError } from '@supabase/supabase-js';
import { throwIfSupabaseError } from './supabase-error.util';

describe('throwIfSupabaseError', () => {
  const buildError = (code: string, message: string): PostgrestError =>
    ({
      code,
      message,
      details: '',
      hint: '',
      name: 'PostgrestError',
    }) as PostgrestError;

  it('no lanza error cuando error es null', () => {
    expect(() => throwIfSupabaseError(null)).not.toThrow();
  });

  it('mapea P0002 y PGRST116 a NotFoundException', () => {
    expect(() => throwIfSupabaseError(buildError('P0002', 'no encontrado'))).toThrow(
      NotFoundException,
    );
    expect(() => throwIfSupabaseError(buildError('PGRST116', 'sin filas'))).toThrow(
      NotFoundException,
    );
  });

  it('mapea 23505 a ConflictException', () => {
    expect(() => throwIfSupabaseError(buildError('23505', 'duplicado'))).toThrow(
      ConflictException,
    );
  });

  it('mapea 42501 a ForbiddenException', () => {
    expect(() => throwIfSupabaseError(buildError('42501', 'sin permiso'))).toThrow(
      ForbiddenException,
    );
  });

  it('mapea violaciones de check/fk (23514, 23503) a BadRequestException', () => {
    expect(() => throwIfSupabaseError(buildError('23514', 'saldo negativo'))).toThrow(
      BadRequestException,
    );
    expect(() => throwIfSupabaseError(buildError('23503', 'fk invalida'))).toThrow(
      BadRequestException,
    );
  });

  it('mapea códigos desconocidos a InternalServerErrorException sin filtrar detalle', () => {
    expect(() => throwIfSupabaseError(buildError('XX000', 'internal detail'))).toThrow(
      InternalServerErrorException,
    );
  });
});
