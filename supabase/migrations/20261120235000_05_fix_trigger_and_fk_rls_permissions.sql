-- =============================================================================
-- Migración 05: Permisos EXECUTE en funciones de trigger para roles de ejecución,
--               políticas RLS para comprobaciones internas de FK (postgres)
--               y backfill de perfiles para usuarios existentes
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Conceder EXECUTE en funciones de trigger y auxiliares a app_ledger_writer
--    y app_user_purger (permanecen revocadas para PUBLIC, anon y authenticated,
--    por lo que PostgREST no las expone como RPC).
-- -----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION
  public.set_updated_at(),
  public.trg_currencies_lifecycle(),
  public.trg_accounts_lifecycle(),
  public.trg_categories_lifecycle(),
  public.trg_transactions_immutability(),
  public.trg_account_movements_immutability(),
  public.trg_validate_transaction_ledger(),
  public._require_auth_user_id(),
  public._validate_monetary_amount(numeric, uuid, boolean, boolean),
  public._get_account_balance(uuid),
  public.create_income(uuid, uuid, uuid, numeric, timestamptz, text),
  public.create_expense(uuid, uuid, uuid, numeric, timestamptz, text),
  public.create_transfer(uuid, uuid, uuid, numeric, timestamptz, text),
  public.create_refund(uuid, uuid, uuid, numeric, timestamptz, text),
  public.create_adjustment(uuid, uuid, numeric, timestamptz, text)
TO app_ledger_writer;

GRANT EXECUTE ON FUNCTION
  public.set_updated_at(),
  public.trg_accounts_lifecycle(),
  public.trg_categories_lifecycle(),
  public.trg_transactions_immutability(),
  public.trg_account_movements_immutability(),
  public.trg_validate_transaction_ledger(),
  public.trg_profiles_purge_user_data()
TO app_user_purger;

-- -----------------------------------------------------------------------------
-- 2. Políticas RLS para el propietario de las tablas (postgres)
--    En PostgreSQL, las comprobaciones internas de claves foráneas
--    (SELECT ... FOR KEY SHARE) se ejecutan como el propietario de la tabla (postgres).
--    Con FORCE ROW LEVEL SECURITY activo y sin BYPASSRLS en postgres (Supabase),
--    postgres necesita política en las tablas referenciadas.
-- -----------------------------------------------------------------------------
CREATE POLICY profiles_owner_fk_check
  ON public.profiles
  FOR ALL
  TO postgres
  USING (true)
  WITH CHECK (true);

CREATE POLICY accounts_owner_fk_check
  ON public.accounts
  FOR ALL
  TO postgres
  USING (true)
  WITH CHECK (true);

CREATE POLICY categories_owner_fk_check
  ON public.categories
  FOR ALL
  TO postgres
  USING (true)
  WITH CHECK (true);

CREATE POLICY transactions_owner_fk_check
  ON public.transactions
  FOR ALL
  TO postgres
  USING (true)
  WITH CHECK (true);

CREATE POLICY account_movements_owner_fk_check
  ON public.account_movements
  FOR ALL
  TO postgres
  USING (true)
  WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- 3. Asegurar que todo usuario existente en auth.users tenga su fila en profiles
-- -----------------------------------------------------------------------------
INSERT INTO public.profiles (id, display_name, default_currency_id, timezone)
SELECT
  u.id,
  NULLIF(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
  c.id,
  'America/Asuncion'
FROM auth.users u
CROSS JOIN LATERAL (
  SELECT id FROM public.currencies WHERE code = 'PYG' LIMIT 1
) c
WHERE NOT EXISTS (
  SELECT 1 FROM public.profiles p WHERE p.id = u.id
);
