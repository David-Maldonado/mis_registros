-- =============================================================================
-- Migración 06: Función public.current_auth_uid() para roles dedicados
-- Motivo: En Supabase Cloud el esquema auth pertenece a supabase_auth_admin y
--         no permite delegar USAGE ON SCHEMA auth a roles personalizados como
--         app_ledger_writer. Al leer los claims JWT directamente desde
--         pg_catalog.current_setting en public.current_auth_uid(), tanto RLS
--         como las RPC de app_ledger_writer obtienen la identidad autenticada
--         sin requerir acceso directo al esquema auth.
-- =============================================================================

-- 1. Crear public.current_auth_uid() equivalente a auth.uid()
CREATE OR REPLACE FUNCTION public.current_auth_uid()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT COALESCE(
    NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), ''),
    (NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '')::pg_catalog.jsonb ->> 'sub')
  )::uuid;
$$;

REVOKE ALL ON FUNCTION public.current_auth_uid() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_auth_uid()
  TO authenticated, app_ledger_writer, app_user_purger;

-- 2. Actualizar _require_auth_user_id() para usar public.current_auth_uid()
GRANT CREATE ON SCHEMA public TO app_ledger_writer;

CREATE OR REPLACE FUNCTION public._require_auth_user_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_auth_uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Autenticación requerida.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_user_id;
END;
$$;

ALTER FUNCTION public._require_auth_user_id() OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public._require_auth_user_id() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._require_auth_user_id() TO app_ledger_writer;

REVOKE CREATE ON SCHEMA public FROM app_ledger_writer;

-- 3. Actualizar políticas RLS para usar public.current_auth_uid()
ALTER POLICY profiles_select_own
  ON public.profiles
  USING (id = public.current_auth_uid());

ALTER POLICY profiles_update_own_writer
  ON public.profiles
  USING (id = public.current_auth_uid())
  WITH CHECK (id = public.current_auth_uid());

ALTER POLICY accounts_select_own
  ON public.accounts
  USING (user_id = public.current_auth_uid());

ALTER POLICY accounts_insert_own_writer
  ON public.accounts
  WITH CHECK (user_id = public.current_auth_uid());

ALTER POLICY accounts_update_own_writer
  ON public.accounts
  USING (user_id = public.current_auth_uid())
  WITH CHECK (user_id = public.current_auth_uid());

ALTER POLICY accounts_delete_own_writer
  ON public.accounts
  USING (user_id = public.current_auth_uid());

ALTER POLICY categories_select_own
  ON public.categories
  USING (user_id = public.current_auth_uid());

ALTER POLICY categories_insert_own_writer
  ON public.categories
  WITH CHECK (user_id = public.current_auth_uid());

ALTER POLICY categories_update_own_writer
  ON public.categories
  USING (user_id = public.current_auth_uid())
  WITH CHECK (user_id = public.current_auth_uid());

ALTER POLICY categories_delete_own_writer
  ON public.categories
  USING (user_id = public.current_auth_uid());

ALTER POLICY transactions_select_own
  ON public.transactions
  USING (user_id = public.current_auth_uid());

ALTER POLICY transactions_insert_own_writer
  ON public.transactions
  WITH CHECK (user_id = public.current_auth_uid());

ALTER POLICY transactions_update_own_writer
  ON public.transactions
  USING (user_id = public.current_auth_uid())
  WITH CHECK (user_id = public.current_auth_uid());

ALTER POLICY account_movements_select_own
  ON public.account_movements
  USING (user_id = public.current_auth_uid());

ALTER POLICY account_movements_insert_own_writer
  ON public.account_movements
  WITH CHECK (user_id = public.current_auth_uid());
