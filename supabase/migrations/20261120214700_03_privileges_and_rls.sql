-- =============================================================================
-- Migración 03: Seguridad de esquema, matriz de privilegios y políticas RLS
-- Referencia: docs/DATA_MODEL.md v1.3 (sección 8)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Endurecimiento del esquema public
-- -----------------------------------------------------------------------------
REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA public TO anon, authenticated, app_ledger_writer, app_user_purger;

-- -----------------------------------------------------------------------------
-- 2. Revocación explícita de privilegios DML sobre las tablas de dominio
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE
  public.currencies,
  public.profiles,
  public.accounts,
  public.categories,
  public.transactions,
  public.account_movements
FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Concesión de privilegios mínimos por rol (sección 8.4)
-- -----------------------------------------------------------------------------

-- 3.1. authenticated: solo lectura (sujeta a RLS); escrituras vía RPC
GRANT SELECT ON TABLE
  public.currencies,
  public.profiles,
  public.accounts,
  public.categories,
  public.transactions,
  public.account_movements
TO authenticated;

-- 3.2. app_ledger_writer: permisos mínimos requeridos por las RPC de escritura
GRANT SELECT ON TABLE public.currencies TO app_ledger_writer;

GRANT SELECT, UPDATE (display_name, default_currency_id, timezone, updated_at)
  ON TABLE public.profiles
  TO app_ledger_writer;

GRANT SELECT, INSERT, UPDATE (name, initial_balance, credit_limit, is_active, updated_at), DELETE
  ON TABLE public.accounts
  TO app_ledger_writer;

GRANT SELECT, INSERT, UPDATE (parent_id, name, type, is_active, updated_at), DELETE
  ON TABLE public.categories
  TO app_ledger_writer;

GRANT SELECT, INSERT, UPDATE (status, description, voided_at, void_reason, updated_at)
  ON TABLE public.transactions
  TO app_ledger_writer;

GRANT SELECT, INSERT
  ON TABLE public.account_movements
  TO app_ledger_writer;

-- 3.3. app_user_purger: permisos mínimos requeridos por el trigger de purga
GRANT SELECT
  ON TABLE public.profiles
  TO app_user_purger;

GRANT SELECT, DELETE
  ON TABLE
    public.account_movements,
    public.transactions,
    public.accounts,
    public.categories
  TO app_user_purger;

-- -----------------------------------------------------------------------------
-- 4. Políticas Row Level Security (sección 8.3)
-- -----------------------------------------------------------------------------

-- 4.1. currencies: catálogo global de solo lectura
CREATE POLICY currencies_select_all
  ON public.currencies
  FOR SELECT
  TO authenticated, app_ledger_writer, postgres, supabase_auth_admin
  USING (true);

-- 4.2. profiles: cada usuario consulta y actualiza únicamente su propio perfil
CREATE POLICY profiles_select_own
  ON public.profiles
  FOR SELECT
  TO authenticated, app_ledger_writer
  USING (id = auth.uid());

CREATE POLICY profiles_update_own_writer
  ON public.profiles
  FOR UPDATE
  TO app_ledger_writer
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Permite que el trigger handle_new_user (AFTER INSERT ON auth.users) cree el perfil
-- respetando FORCE ROW LEVEL SECURITY en public.profiles.
CREATE POLICY profiles_insert_on_signup
  ON public.profiles
  FOR INSERT
  TO postgres, supabase_auth_admin
  WITH CHECK (true);

CREATE POLICY profiles_select_purger
  ON public.profiles
  FOR SELECT
  TO app_user_purger
  USING (true);

-- 4.3. accounts
CREATE POLICY accounts_select_own
  ON public.accounts
  FOR SELECT
  TO authenticated, app_ledger_writer
  USING (user_id = auth.uid());

CREATE POLICY accounts_insert_own_writer
  ON public.accounts
  FOR INSERT
  TO app_ledger_writer
  WITH CHECK (user_id = auth.uid());

CREATE POLICY accounts_update_own_writer
  ON public.accounts
  FOR UPDATE
  TO app_ledger_writer
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY accounts_delete_own_writer
  ON public.accounts
  FOR DELETE
  TO app_ledger_writer
  USING (user_id = auth.uid());

CREATE POLICY accounts_purge_select
  ON public.accounts
  FOR SELECT
  TO app_user_purger
  USING (true);

CREATE POLICY accounts_purge_delete
  ON public.accounts
  FOR DELETE
  TO app_user_purger
  USING (true);

-- 4.4. categories
CREATE POLICY categories_select_own
  ON public.categories
  FOR SELECT
  TO authenticated, app_ledger_writer
  USING (user_id = auth.uid());

CREATE POLICY categories_insert_own_writer
  ON public.categories
  FOR INSERT
  TO app_ledger_writer
  WITH CHECK (user_id = auth.uid());

CREATE POLICY categories_update_own_writer
  ON public.categories
  FOR UPDATE
  TO app_ledger_writer
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY categories_delete_own_writer
  ON public.categories
  FOR DELETE
  TO app_ledger_writer
  USING (user_id = auth.uid());

CREATE POLICY categories_purge_select
  ON public.categories
  FOR SELECT
  TO app_user_purger
  USING (true);

CREATE POLICY categories_purge_delete
  ON public.categories
  FOR DELETE
  TO app_user_purger
  USING (true);

-- 4.5. transactions
CREATE POLICY transactions_select_own
  ON public.transactions
  FOR SELECT
  TO authenticated, app_ledger_writer
  USING (user_id = auth.uid());

CREATE POLICY transactions_insert_own_writer
  ON public.transactions
  FOR INSERT
  TO app_ledger_writer
  WITH CHECK (user_id = auth.uid());

CREATE POLICY transactions_update_own_writer
  ON public.transactions
  FOR UPDATE
  TO app_ledger_writer
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY transactions_purge_select
  ON public.transactions
  FOR SELECT
  TO app_user_purger
  USING (true);

CREATE POLICY transactions_purge_delete
  ON public.transactions
  FOR DELETE
  TO app_user_purger
  USING (true);

-- 4.6. account_movements
CREATE POLICY account_movements_select_own
  ON public.account_movements
  FOR SELECT
  TO authenticated, app_ledger_writer
  USING (user_id = auth.uid());

CREATE POLICY account_movements_insert_own_writer
  ON public.account_movements
  FOR INSERT
  TO app_ledger_writer
  WITH CHECK (user_id = auth.uid());

CREATE POLICY account_movements_purge_select
  ON public.account_movements
  FOR SELECT
  TO app_user_purger
  USING (true);

CREATE POLICY account_movements_purge_delete
  ON public.account_movements
  FOR DELETE
  TO app_user_purger
  USING (true);
