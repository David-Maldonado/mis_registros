import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { EnvironmentVariables } from '../config/env.validation';

@Injectable()
export class SupabaseService {
  private readonly supabaseUrl: string;
  private readonly supabaseAnonKey: string;
  private readonly anonClient: SupabaseClient;

  constructor(private readonly configService: ConfigService<EnvironmentVariables, true>) {
    this.supabaseUrl = this.configService.get('SUPABASE_URL', { infer: true });
    this.supabaseAnonKey = this.configService.get('SUPABASE_ANON_KEY', { infer: true });

    this.anonClient = createClient(this.supabaseUrl, this.supabaseAnonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  }

  /**
   * Cliente anónimo usado exclusivamente para validar tokens JWT con Supabase Auth.
   */
  getAnonClient(): SupabaseClient {
    return this.anonClient;
  }

  /**
   * Crea un cliente por solicitud autenticado con el JWT del usuario.
   * Nunca usa service_role; todas las consultas y RPC respetan RLS.
   */
  getUserClient(accessToken: string): SupabaseClient {
    return createClient(this.supabaseUrl, this.supabaseAnonKey, {
      global: {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  }
}
