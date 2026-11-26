import { validateEnv } from './env.validation';

describe('validateEnv', () => {
  it('acepta una configuración válida', () => {
    const result = validateEnv({
      PORT: '3000',
      CORS_ORIGIN: 'https://misregistros.app',
      SUPABASE_URL: 'https://demo.supabase.co',
      SUPABASE_ANON_KEY: 'anon-key',
    });

    expect(result).toEqual({
      PORT: 3000,
      CORS_ORIGIN: 'https://misregistros.app',
      SUPABASE_URL: 'https://demo.supabase.co',
      SUPABASE_ANON_KEY: 'anon-key',
    });
  });

  it('rechaza SUPABASE_URL sin https://', () => {
    expect(() =>
      validateEnv({
        SUPABASE_URL: 'http://demo.supabase.co',
        SUPABASE_ANON_KEY: 'anon-key',
      }),
    ).toThrow('SUPABASE_URL');
  });

  it('rechaza SUPABASE_ANON_KEY vacío', () => {
    expect(() =>
      validateEnv({
        SUPABASE_URL: 'https://demo.supabase.co',
        SUPABASE_ANON_KEY: '',
      }),
    ).toThrow('SUPABASE_ANON_KEY');
  });

  it('rechaza PORT fuera de rango', () => {
    expect(() =>
      validateEnv({
        PORT: '99999',
        SUPABASE_URL: 'https://demo.supabase.co',
        SUPABASE_ANON_KEY: 'anon-key',
      }),
    ).toThrow('PORT');
  });
});
