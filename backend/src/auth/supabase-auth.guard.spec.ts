import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { SupabaseAuthGuard } from './supabase-auth.guard';

describe('SupabaseAuthGuard', () => {
  const mockGetUser = jest.fn();
  const mockSupabaseService = {
    getAnonClient: () => ({
      auth: {
        getUser: mockGetUser,
      },
    }),
  } as unknown as SupabaseService;

  const createContext = (authorization?: string): ExecutionContext =>
    ({
      switchToHttp: () => ({
        getRequest: () => ({
          headers: authorization ? { authorization } : {},
        }),
      }),
    }) as unknown as ExecutionContext;

  beforeEach(() => {
    mockGetUser.mockReset();
  });

  it('rechaza solicitudes sin encabezado Authorization', async () => {
    const guard = new SupabaseAuthGuard(mockSupabaseService);
    await expect(guard.canActivate(createContext())).rejects.toThrow(UnauthorizedException);
  });

  it('rechaza tokens inválidos devueltos por Supabase Auth', async () => {
    mockGetUser.mockResolvedValue({
      data: { user: null },
      error: { message: 'invalid token' },
    });

    const guard = new SupabaseAuthGuard(mockSupabaseService);
    await expect(guard.canActivate(createContext('Bearer fake-jwt'))).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('adjunta el usuario autenticado cuando el token es válido', async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: '11111111-1111-1111-1111-111111111111',
          email: 'usuario@ejemplo.com',
        },
      },
      error: null,
    });

    const request = { headers: { authorization: 'Bearer valid-jwt' } } as Record<string, unknown>;
    const ctx = {
      switchToHttp: () => ({
        getRequest: () => request,
      }),
    } as unknown as ExecutionContext;

    const guard = new SupabaseAuthGuard(mockSupabaseService);
    const allowed = await guard.canActivate(ctx);

    expect(allowed).toBe(true);
    expect(request.user).toEqual({
      id: '11111111-1111-1111-1111-111111111111',
      email: 'usuario@ejemplo.com',
      accessToken: 'valid-jwt',
    });
  });
});
