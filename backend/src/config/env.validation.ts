export interface EnvironmentVariables {
  PORT: number;
  CORS_ORIGIN: string;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
}

export function validateEnv(config: Record<string, unknown>): EnvironmentVariables {
  const portRaw = config.PORT ?? '3000';
  const port = Number(portRaw);

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un número entero entre 1 y 65535.');
  }

  const supabaseUrl = String(config.SUPABASE_URL ?? '').trim();
  if (!supabaseUrl || !supabaseUrl.startsWith('https://')) {
    throw new Error('SUPABASE_URL es obligatorio y debe iniciar con https://');
  }

  const supabaseAnonKey = String(config.SUPABASE_ANON_KEY ?? '').trim();
  if (!supabaseAnonKey) {
    throw new Error('SUPABASE_ANON_KEY es obligatorio.');
  }

  const corsOrigin = String(config.CORS_ORIGIN ?? '*').trim() || '*';

  return {
    PORT: port,
    CORS_ORIGIN: corsOrigin,
    SUPABASE_URL: supabaseUrl,
    SUPABASE_ANON_KEY: supabaseAnonKey,
  };
}
