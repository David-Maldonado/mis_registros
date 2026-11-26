-- =============================================================================
-- Migración 04: Funciones RPC de escritura y vistas/funciones de lectura
-- Referencia: docs/DATA_MODEL.md v1.3 (secciones 6, 9 y 10)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Funciones auxiliares internas (no expuestas como RPC)
-- -----------------------------------------------------------------------------

-- Obtiene auth.uid() o rechaza la solicitud si no hay sesión autenticada
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
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Autenticación requerida.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_user_id;
END;
$$;

ALTER FUNCTION public._require_auth_user_id() OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public._require_auth_user_id() FROM PUBLIC, anon, authenticated;

-- Valida precisión monetaria antes de almacenar en numeric(18,4) (sección 9.5)
CREATE OR REPLACE FUNCTION public._validate_monetary_amount(
  p_amount numeric,
  p_currency_id uuid,
  p_allow_zero boolean DEFAULT false,
  p_allow_negative boolean DEFAULT false
)
RETURNS numeric(18,4)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_decimal_places smallint;
  v_is_active boolean;
BEGIN
  IF p_amount IS NULL THEN
    RAISE EXCEPTION 'El importe es obligatorio.'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF NOT p_allow_zero AND p_amount = 0 THEN
    RAISE EXCEPTION 'El importe no puede ser cero.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT p_allow_negative AND p_amount < 0 THEN
    RAISE EXCEPTION 'El importe no puede ser negativo.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Límite de numeric(18,4): máximo 14 dígitos enteros
  IF abs(p_amount) >= 100000000000000::numeric THEN
    RAISE EXCEPTION 'El importe excede el límite máximo permitido por numeric(18,4).'
      USING ERRCODE = 'numeric_value_out_of_range';
  END IF;

  SELECT c.decimal_places, c.is_active
    INTO v_decimal_places, v_is_active
    FROM public.currencies c
   WHERE c.id = p_currency_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La moneda especificada no existe.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF round(p_amount, v_decimal_places) <> p_amount THEN
    RAISE EXCEPTION 'El importe tiene más decimales que los permitidos por la moneda (%).', v_decimal_places
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN p_amount::numeric(18,4);
END;
$$;

ALTER FUNCTION public._validate_monetary_amount(numeric, uuid, boolean, boolean) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public._validate_monetary_amount(numeric, uuid, boolean, boolean) FROM PUBLIC, anon, authenticated;

-- Calcula el saldo actual contabilizado de una cuenta
CREATE OR REPLACE FUNCTION public._get_account_balance(p_account_id uuid)
RETURNS numeric(18,4)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT
    a.initial_balance + COALESCE((
      SELECT SUM(m.signed_amount)
        FROM public.account_movements m
        JOIN public.transactions t ON t.id = m.transaction_id
       WHERE m.account_id = a.id
         AND t.status = 'posted'
    ), 0)
  FROM public.accounts a
  WHERE a.id = p_account_id;
$$;

ALTER FUNCTION public._get_account_balance(uuid) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public._get_account_balance(uuid) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. RPC: Administración del perfil (sección 9.4)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_profile(
  p_display_name text,
  p_default_currency_id uuid,
  p_timezone text DEFAULT 'America/Asuncion'
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_clean_timezone text;
  v_currency_active boolean;
  v_profile public.profiles%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();
  v_clean_timezone := btrim(COALESCE(p_timezone, ''));

  IF v_clean_timezone = '' OR NOT EXISTS (
    SELECT 1
      FROM pg_catalog.pg_timezone_names tz
     WHERE tz.name = v_clean_timezone
  ) THEN
    RAISE EXCEPTION 'La zona horaria "%" no es un identificador IANA válido.', v_clean_timezone
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT c.is_active
    INTO v_currency_active
    FROM public.currencies c
   WHERE c.id = p_default_currency_id;

  IF NOT FOUND OR NOT v_currency_active THEN
    RAISE EXCEPTION 'La moneda por defecto debe existir y estar activa.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.profiles p
     SET display_name = NULLIF(btrim(p_display_name), ''),
         default_currency_id = p_default_currency_id,
         timezone = v_clean_timezone
   WHERE p.id = v_user_id
  RETURNING p.* INTO v_profile;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Perfil no encontrado para el usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN v_profile;
END;
$$;

ALTER FUNCTION public.update_profile(text, uuid, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.update_profile(text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_profile(text, uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3. RPC: Administración de cuentas (sección 9.2)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_account(
  p_currency_id uuid,
  p_name text,
  p_type text,
  p_initial_balance numeric DEFAULT 0,
  p_credit_limit numeric DEFAULT NULL
)
RETURNS public.accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_currency_active boolean;
  v_initial_balance numeric(18,4);
  v_credit_limit numeric(18,4);
  v_account public.accounts%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'El nombre de la cuenta no puede estar vacío.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_type NOT IN ('cash', 'bank', 'e_wallet', 'credit_card') THEN
    RAISE EXCEPTION 'Tipo de cuenta no válido: %.', p_type
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT c.is_active
    INTO v_currency_active
    FROM public.currencies c
   WHERE c.id = p_currency_id;

  IF NOT FOUND OR NOT v_currency_active THEN
    RAISE EXCEPTION 'La moneda seleccionada no existe o está inactiva.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_initial_balance := public._validate_monetary_amount(
    COALESCE(p_initial_balance, 0),
    p_currency_id,
    true,
    p_type = 'credit_card'
  );

  IF p_type = 'credit_card' THEN
    IF v_initial_balance > 0 THEN
      RAISE EXCEPTION 'El saldo inicial de una tarjeta de crédito debe ser menor o igual a cero.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF p_credit_limit IS NULL THEN
      RAISE EXCEPTION 'Las tarjetas de crédito requieren un límite de crédito positivo.'
        USING ERRCODE = 'check_violation';
    END IF;
    v_credit_limit := public._validate_monetary_amount(p_credit_limit, p_currency_id, false, false);
  ELSE
    IF p_credit_limit IS NOT NULL THEN
      RAISE EXCEPTION 'Solo las tarjetas de crédito pueden tener límite de crédito.'
        USING ERRCODE = 'check_violation';
    END IF;
    v_credit_limit := NULL;
  END IF;

  INSERT INTO public.accounts (
    user_id,
    currency_id,
    name,
    type,
    initial_balance,
    credit_limit,
    is_active
  )
  VALUES (
    v_user_id,
    p_currency_id,
    btrim(p_name),
    p_type,
    v_initial_balance,
    v_credit_limit,
    true
  )
  RETURNING * INTO v_account;

  RETURN v_account;
END;
$$;

ALTER FUNCTION public.create_account(uuid, text, text, numeric, numeric) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.create_account(uuid, text, text, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_account(uuid, text, text, numeric, numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_account(
  p_account_id uuid,
  p_name text,
  p_initial_balance numeric,
  p_credit_limit numeric,
  p_is_active boolean
)
RETURNS public.accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing public.accounts%ROWTYPE;
  v_initial_balance numeric(18,4);
  v_credit_limit numeric(18,4);
  v_updated public.accounts%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  -- Bloquear la fila de la cuenta para serializar con operaciones concurrentes (sección 10.2)
  SELECT a.*
    INTO v_existing
    FROM public.accounts a
   WHERE a.id = p_account_id
     AND a.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cuenta no encontrada o no pertenece al usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'El nombre de la cuenta no puede estar vacío.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_initial_balance := public._validate_monetary_amount(
    p_initial_balance,
    v_existing.currency_id,
    true,
    v_existing.type = 'credit_card'
  );

  IF v_existing.type = 'credit_card' THEN
    IF v_initial_balance > 0 THEN
      RAISE EXCEPTION 'El saldo inicial de una tarjeta de crédito debe ser menor o igual a cero.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF p_credit_limit IS NULL THEN
      RAISE EXCEPTION 'Las tarjetas de crédito requieren un límite de crédito positivo.'
        USING ERRCODE = 'check_violation';
    END IF;
    v_credit_limit := public._validate_monetary_amount(p_credit_limit, v_existing.currency_id, false, false);
  ELSE
    IF p_credit_limit IS NOT NULL THEN
      RAISE EXCEPTION 'Solo las tarjetas de crédito pueden tener límite de crédito.'
        USING ERRCODE = 'check_violation';
    END IF;
    v_credit_limit := NULL;
  END IF;

  UPDATE public.accounts a
     SET name = btrim(p_name),
         initial_balance = v_initial_balance,
         credit_limit = v_credit_limit,
         is_active = COALESCE(p_is_active, v_existing.is_active)
   WHERE a.id = v_existing.id
     AND a.user_id = v_user_id
  RETURNING * INTO v_updated;

  RETURN v_updated;
END;
$$;

ALTER FUNCTION public.update_account(uuid, text, numeric, numeric, boolean) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.update_account(uuid, text, numeric, numeric, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_account(uuid, text, numeric, numeric, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_account(p_account_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_id uuid;
BEGIN
  v_user_id := public._require_auth_user_id();

  SELECT a.id
    INTO v_existing_id
    FROM public.accounts a
   WHERE a.id = p_account_id
     AND a.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cuenta no encontrada o no pertenece al usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  DELETE FROM public.accounts a
   WHERE a.id = v_existing_id
     AND a.user_id = v_user_id;

  RETURN true;
END;
$$;

ALTER FUNCTION public.delete_account(uuid) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.delete_account(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_account(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. RPC: Administración de categorías (sección 9.3)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_category(
  p_name text,
  p_type text,
  p_parent_id uuid DEFAULT NULL
)
RETURNS public.categories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_parent public.categories%ROWTYPE;
  v_category public.categories%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'El nombre de la categoría no puede estar vacío.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_type NOT IN ('income', 'expense') THEN
    RAISE EXCEPTION 'El tipo de categoría debe ser income o expense.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_parent_id IS NOT NULL THEN
    SELECT c.*
      INTO v_parent
      FROM public.categories c
     WHERE c.id = p_parent_id
       AND c.user_id = v_user_id
       FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La categoría padre no existe o no pertenece al usuario.'
        USING ERRCODE = 'no_data_found';
    END IF;
  END IF;

  INSERT INTO public.categories (
    user_id,
    parent_id,
    name,
    type,
    is_active
  )
  VALUES (
    v_user_id,
    p_parent_id,
    btrim(p_name),
    p_type,
    true
  )
  RETURNING * INTO v_category;

  RETURN v_category;
END;
$$;

ALTER FUNCTION public.create_category(text, text, uuid) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.create_category(text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_category(text, text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_category(
  p_category_id uuid,
  p_name text,
  p_type text,
  p_parent_id uuid,
  p_is_active boolean
)
RETURNS public.categories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing public.categories%ROWTYPE;
  v_updated public.categories%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  -- Bloquear categorías involucradas en orden determinístico por UUID (sección 10.3)
  PERFORM 1
    FROM public.categories c
   WHERE c.user_id = v_user_id
     AND c.id IN (p_category_id, p_parent_id)
   ORDER BY c.id
     FOR UPDATE;

  SELECT c.*
    INTO v_existing
    FROM public.categories c
   WHERE c.id = p_category_id
     AND c.user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Categoría no encontrada o no pertenece al usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'El nombre de la categoría no puede estar vacío.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.categories c
     SET name = btrim(p_name),
         type = COALESCE(p_type, v_existing.type),
         parent_id = p_parent_id,
         is_active = COALESCE(p_is_active, v_existing.is_active)
   WHERE c.id = v_existing.id
     AND c.user_id = v_user_id
  RETURNING * INTO v_updated;

  RETURN v_updated;
END;
$$;

ALTER FUNCTION public.update_category(uuid, text, text, uuid, boolean) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.update_category(uuid, text, text, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_category(uuid, text, text, uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_category(p_category_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_id uuid;
BEGIN
  v_user_id := public._require_auth_user_id();

  SELECT c.id
    INTO v_existing_id
    FROM public.categories c
   WHERE c.id = p_category_id
     AND c.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Categoría no encontrada o no pertenece al usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  DELETE FROM public.categories c
   WHERE c.id = v_existing_id
     AND c.user_id = v_user_id;

  RETURN true;
END;
$$;

ALTER FUNCTION public.delete_category(uuid) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.delete_category(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_category(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 5. RPC: Operaciones financieras (sección 9.1)
-- -----------------------------------------------------------------------------

-- 5.1. create_income
CREATE OR REPLACE FUNCTION public.create_income(
  p_client_request_id uuid,
  p_account_id uuid,
  p_category_id uuid,
  p_amount numeric,
  p_occurred_at timestamptz,
  p_description text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_tx public.transactions%ROWTYPE;
  v_existing_acc_id uuid;
  v_account public.accounts%ROWTYPE;
  v_category public.categories%ROWTYPE;
  v_amount numeric(18,4);
  v_tx public.transactions%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF p_client_request_id IS NULL OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'client_request_id y occurred_at son obligatorios.'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- Idempotencia
  SELECT t.*
    INTO v_existing_tx
    FROM public.transactions t
   WHERE t.user_id = v_user_id
     AND t.client_request_id = p_client_request_id;

  IF FOUND THEN
    SELECT m.account_id
      INTO v_existing_acc_id
      FROM public.account_movements m
     WHERE m.transaction_id = v_existing_tx.id
     LIMIT 1;

    IF v_existing_tx.type = 'income'
       AND v_existing_acc_id = p_account_id
       AND v_existing_tx.category_id = p_category_id
       AND v_existing_tx.amount = p_amount
       AND v_existing_tx.occurred_at = p_occurred_at THEN
      RETURN v_existing_tx;
    END IF;

    RAISE EXCEPTION 'client_request_id ya fue utilizado con parámetros diferentes.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Bloquear cuenta y categoría
  SELECT a.*
    INTO v_account
    FROM public.accounts a
   WHERE a.id = p_account_id
     AND a.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND OR NOT v_account.is_active THEN
    RAISE EXCEPTION 'La cuenta no existe, no pertenece al usuario o está inactiva.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_account.type NOT IN ('cash', 'bank', 'e_wallet') THEN
    RAISE EXCEPTION 'Los ingresos solo pueden registrarse en cuentas líquidas.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT c.*
    INTO v_category
    FROM public.categories c
   WHERE c.id = p_category_id
     AND c.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND OR NOT v_category.is_active OR v_category.type <> 'income' THEN
    RAISE EXCEPTION 'La categoría debe existir, estar activa y ser de tipo income.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_amount := public._validate_monetary_amount(p_amount, v_account.currency_id, false, false);

  INSERT INTO public.transactions (
    user_id,
    client_request_id,
    type,
    status,
    currency_id,
    amount,
    category_id,
    occurred_at,
    description
  )
  VALUES (
    v_user_id,
    p_client_request_id,
    'income',
    'posted',
    v_account.currency_id,
    v_amount,
    v_category.id,
    p_occurred_at,
    NULLIF(btrim(p_description), '')
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.account_movements (
    user_id,
    transaction_id,
    account_id,
    currency_id,
    signed_amount,
    occurred_at
  )
  VALUES (
    v_user_id,
    v_tx.id,
    v_account.id,
    v_account.currency_id,
    v_amount,
    p_occurred_at
  );

  RETURN v_tx;
END;
$$;

ALTER FUNCTION public.create_income(uuid, uuid, uuid, numeric, timestamptz, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.create_income(uuid, uuid, uuid, numeric, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_income(uuid, uuid, uuid, numeric, timestamptz, text) TO authenticated;

-- 5.2. create_expense
CREATE OR REPLACE FUNCTION public.create_expense(
  p_client_request_id uuid,
  p_account_id uuid,
  p_category_id uuid,
  p_amount numeric,
  p_occurred_at timestamptz,
  p_description text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_tx public.transactions%ROWTYPE;
  v_existing_acc_id uuid;
  v_account public.accounts%ROWTYPE;
  v_category public.categories%ROWTYPE;
  v_amount numeric(18,4);
  v_current_balance numeric(18,4);
  v_tx public.transactions%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF p_client_request_id IS NULL OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'client_request_id y occurred_at son obligatorios.'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- Idempotencia
  SELECT t.*
    INTO v_existing_tx
    FROM public.transactions t
   WHERE t.user_id = v_user_id
     AND t.client_request_id = p_client_request_id;

  IF FOUND THEN
    SELECT m.account_id
      INTO v_existing_acc_id
      FROM public.account_movements m
     WHERE m.transaction_id = v_existing_tx.id
     LIMIT 1;

    IF v_existing_tx.type = 'expense'
       AND v_existing_acc_id = p_account_id
       AND v_existing_tx.category_id = p_category_id
       AND v_existing_tx.amount = p_amount
       AND v_existing_tx.occurred_at = p_occurred_at THEN
      RETURN v_existing_tx;
    END IF;

    RAISE EXCEPTION 'client_request_id ya fue utilizado con parámetros diferentes.'
      USING ERRCODE = 'unique_violation';
  END IF;

  SELECT a.*
    INTO v_account
    FROM public.accounts a
   WHERE a.id = p_account_id
     AND a.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND OR NOT v_account.is_active THEN
    RAISE EXCEPTION 'La cuenta no existe, no pertenece al usuario o está inactiva.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT c.*
    INTO v_category
    FROM public.categories c
   WHERE c.id = p_category_id
     AND c.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND OR NOT v_category.is_active OR v_category.type <> 'expense' THEN
    RAISE EXCEPTION 'La categoría debe existir, estar activa y ser de tipo expense.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_amount := public._validate_monetary_amount(p_amount, v_account.currency_id, false, false);

  -- Si es cuenta líquida, validar saldo suficiente (las tarjetas de crédito sí pueden quedar en negativo)
  IF v_account.type IN ('cash', 'bank', 'e_wallet') THEN
    v_current_balance := public._get_account_balance(v_account.id);
    IF v_current_balance - v_amount < 0 THEN
      RAISE EXCEPTION 'Saldo insuficiente en la cuenta líquida "%".', v_account.name
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  INSERT INTO public.transactions (
    user_id,
    client_request_id,
    type,
    status,
    currency_id,
    amount,
    category_id,
    occurred_at,
    description
  )
  VALUES (
    v_user_id,
    p_client_request_id,
    'expense',
    'posted',
    v_account.currency_id,
    v_amount,
    v_category.id,
    p_occurred_at,
    NULLIF(btrim(p_description), '')
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.account_movements (
    user_id,
    transaction_id,
    account_id,
    currency_id,
    signed_amount,
    occurred_at
  )
  VALUES (
    v_user_id,
    v_tx.id,
    v_account.id,
    v_account.currency_id,
    -v_amount,
    p_occurred_at
  );

  RETURN v_tx;
END;
$$;

ALTER FUNCTION public.create_expense(uuid, uuid, uuid, numeric, timestamptz, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.create_expense(uuid, uuid, uuid, numeric, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_expense(uuid, uuid, uuid, numeric, timestamptz, text) TO authenticated;

-- 5.3. create_transfer
CREATE OR REPLACE FUNCTION public.create_transfer(
  p_client_request_id uuid,
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_amount numeric,
  p_occurred_at timestamptz,
  p_description text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_tx public.transactions%ROWTYPE;
  v_existing_from_id uuid;
  v_existing_to_id uuid;
  v_from_account public.accounts%ROWTYPE;
  v_to_account public.accounts%ROWTYPE;
  v_amount numeric(18,4);
  v_from_balance numeric(18,4);
  v_tx public.transactions%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF p_client_request_id IS NULL OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'client_request_id y occurred_at son obligatorios.'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_from_account_id IS NULL OR p_to_account_id IS NULL OR p_from_account_id = p_to_account_id THEN
    RAISE EXCEPTION 'Las cuentas de origen y destino deben existir y ser diferentes.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Idempotencia
  SELECT t.*
    INTO v_existing_tx
    FROM public.transactions t
   WHERE t.user_id = v_user_id
     AND t.client_request_id = p_client_request_id;

  IF FOUND THEN
    SELECT m.account_id INTO v_existing_from_id
      FROM public.account_movements m
     WHERE m.transaction_id = v_existing_tx.id AND m.signed_amount < 0;

    SELECT m.account_id INTO v_existing_to_id
      FROM public.account_movements m
     WHERE m.transaction_id = v_existing_tx.id AND m.signed_amount > 0;

    IF v_existing_tx.type = 'transfer'
       AND v_existing_from_id = p_from_account_id
       AND v_existing_to_id = p_to_account_id
       AND v_existing_tx.amount = p_amount
       AND v_existing_tx.occurred_at = p_occurred_at THEN
      RETURN v_existing_tx;
    END IF;

    RAISE EXCEPTION 'client_request_id ya fue utilizado con parámetros diferentes.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Bloquear ambas cuentas en orden determinístico por UUID (sección 10.1)
  PERFORM 1
    FROM public.accounts a
   WHERE a.user_id = v_user_id
     AND a.id IN (p_from_account_id, p_to_account_id)
   ORDER BY a.id
     FOR UPDATE;

  SELECT a.* INTO v_from_account
    FROM public.accounts a
   WHERE a.id = p_from_account_id AND a.user_id = v_user_id;

  SELECT a.* INTO v_to_account
    FROM public.accounts a
   WHERE a.id = p_to_account_id AND a.user_id = v_user_id;

  IF v_from_account.id IS NULL OR v_to_account.id IS NULL THEN
    RAISE EXCEPTION 'Ambas cuentas deben existir y pertenecer al usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT v_from_account.is_active OR NOT v_to_account.is_active THEN
    RAISE EXCEPTION 'Ambas cuentas involucradas en la transferencia deben estar activas.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_from_account.currency_id <> v_to_account.currency_id THEN
    RAISE EXCEPTION 'No se permiten transferencias entre cuentas de monedas diferentes en V1.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_from_account.type NOT IN ('cash', 'bank', 'e_wallet') THEN
    RAISE EXCEPTION 'La cuenta de origen de una transferencia debe ser una cuenta líquida.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_amount := public._validate_monetary_amount(p_amount, v_from_account.currency_id, false, false);

  v_from_balance := public._get_account_balance(v_from_account.id);
  IF v_from_balance - v_amount < 0 THEN
    RAISE EXCEPTION 'Saldo insuficiente en la cuenta de origen "%".', v_from_account.name
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.transactions (
    user_id,
    client_request_id,
    type,
    status,
    currency_id,
    amount,
    occurred_at,
    description
  )
  VALUES (
    v_user_id,
    p_client_request_id,
    'transfer',
    'posted',
    v_from_account.currency_id,
    v_amount,
    p_occurred_at,
    NULLIF(btrim(p_description), '')
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.account_movements (
    user_id,
    transaction_id,
    account_id,
    currency_id,
    signed_amount,
    occurred_at
  )
  VALUES
    (v_user_id, v_tx.id, v_from_account.id, v_from_account.currency_id, -v_amount, p_occurred_at),
    (v_user_id, v_tx.id, v_to_account.id, v_to_account.currency_id, v_amount, p_occurred_at);

  RETURN v_tx;
END;
$$;

ALTER FUNCTION public.create_transfer(uuid, uuid, uuid, numeric, timestamptz, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.create_transfer(uuid, uuid, uuid, numeric, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_transfer(uuid, uuid, uuid, numeric, timestamptz, text) TO authenticated;

-- 5.4. create_refund
CREATE OR REPLACE FUNCTION public.create_refund(
  p_client_request_id uuid,
  p_original_transaction_id uuid,
  p_account_id uuid,
  p_amount numeric,
  p_occurred_at timestamptz,
  p_description text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_tx public.transactions%ROWTYPE;
  v_existing_acc_id uuid;
  v_orig_tx public.transactions%ROWTYPE;
  v_account public.accounts%ROWTYPE;
  v_amount numeric(18,4);
  v_refunded_so_far numeric(18,4);
  v_tx public.transactions%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF p_client_request_id IS NULL OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'client_request_id y occurred_at son obligatorios.'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- Idempotencia
  SELECT t.*
    INTO v_existing_tx
    FROM public.transactions t
   WHERE t.user_id = v_user_id
     AND t.client_request_id = p_client_request_id;

  IF FOUND THEN
    SELECT m.account_id INTO v_existing_acc_id
      FROM public.account_movements m
     WHERE m.transaction_id = v_existing_tx.id
     LIMIT 1;

    IF v_existing_tx.type = 'refund'
       AND v_existing_tx.related_transaction_id = p_original_transaction_id
       AND v_existing_acc_id = p_account_id
       AND v_existing_tx.amount = p_amount
       AND v_existing_tx.occurred_at = p_occurred_at THEN
      RETURN v_existing_tx;
    END IF;

    RAISE EXCEPTION 'client_request_id ya fue utilizado con parámetros diferentes.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Bloquear gasto original para serializar devoluciones concurrentes (sección 10.4)
  SELECT t.*
    INTO v_orig_tx
    FROM public.transactions t
   WHERE t.id = p_original_transaction_id
     AND t.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND OR v_orig_tx.type <> 'expense' OR v_orig_tx.status <> 'posted' THEN
    RAISE EXCEPTION 'El gasto original debe existir, pertenecer al usuario y estar contabilizado (posted).'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT a.*
    INTO v_account
    FROM public.accounts a
   WHERE a.id = p_account_id
     AND a.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND OR NOT v_account.is_active OR v_account.currency_id <> v_orig_tx.currency_id THEN
    RAISE EXCEPTION 'La cuenta receptora debe existir, estar activa y tener la misma moneda que el gasto original.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_amount := public._validate_monetary_amount(p_amount, v_orig_tx.currency_id, false, false);

  SELECT COALESCE(SUM(r.amount), 0)
    INTO v_refunded_so_far
    FROM public.transactions r
   WHERE r.related_transaction_id = v_orig_tx.id
     AND r.type = 'refund'
     AND r.status = 'posted';

  IF v_refunded_so_far + v_amount > v_orig_tx.amount THEN
    RAISE EXCEPTION 'El importe de la devolución supera el saldo pendiente de devolver del gasto original.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.transactions (
    user_id,
    client_request_id,
    type,
    status,
    currency_id,
    amount,
    category_id,
    related_transaction_id,
    occurred_at,
    description
  )
  VALUES (
    v_user_id,
    p_client_request_id,
    'refund',
    'posted',
    v_orig_tx.currency_id,
    v_amount,
    v_orig_tx.category_id,
    v_orig_tx.id,
    p_occurred_at,
    NULLIF(btrim(p_description), '')
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.account_movements (
    user_id,
    transaction_id,
    account_id,
    currency_id,
    signed_amount,
    occurred_at
  )
  VALUES (
    v_user_id,
    v_tx.id,
    v_account.id,
    v_account.currency_id,
    v_amount,
    p_occurred_at
  );

  RETURN v_tx;
END;
$$;

ALTER FUNCTION public.create_refund(uuid, uuid, uuid, numeric, timestamptz, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.create_refund(uuid, uuid, uuid, numeric, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_refund(uuid, uuid, uuid, numeric, timestamptz, text) TO authenticated;

-- 5.5. create_adjustment
CREATE OR REPLACE FUNCTION public.create_adjustment(
  p_client_request_id uuid,
  p_account_id uuid,
  p_signed_amount numeric,
  p_occurred_at timestamptz,
  p_description text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_tx public.transactions%ROWTYPE;
  v_existing_mov public.account_movements%ROWTYPE;
  v_account public.accounts%ROWTYPE;
  v_signed_amount numeric(18,4);
  v_current_balance numeric(18,4);
  v_tx public.transactions%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF p_client_request_id IS NULL OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'client_request_id y occurred_at son obligatorios.'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- Idempotencia
  SELECT t.*
    INTO v_existing_tx
    FROM public.transactions t
   WHERE t.user_id = v_user_id
     AND t.client_request_id = p_client_request_id;

  IF FOUND THEN
    SELECT m.* INTO v_existing_mov
      FROM public.account_movements m
     WHERE m.transaction_id = v_existing_tx.id
     LIMIT 1;

    IF v_existing_tx.type = 'adjustment'
       AND v_existing_mov.account_id = p_account_id
       AND v_existing_mov.signed_amount = p_signed_amount
       AND v_existing_tx.occurred_at = p_occurred_at THEN
      RETURN v_existing_tx;
    END IF;

    RAISE EXCEPTION 'client_request_id ya fue utilizado con parámetros diferentes.'
      USING ERRCODE = 'unique_violation';
  END IF;

  SELECT a.*
    INTO v_account
    FROM public.accounts a
   WHERE a.id = p_account_id
     AND a.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND OR NOT v_account.is_active THEN
    RAISE EXCEPTION 'La cuenta no existe, no pertenece al usuario o está inactiva.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_signed_amount := public._validate_monetary_amount(p_signed_amount, v_account.currency_id, false, true);

  IF v_account.type IN ('cash', 'bank', 'e_wallet') AND v_signed_amount < 0 THEN
    v_current_balance := public._get_account_balance(v_account.id);
    IF v_current_balance + v_signed_amount < 0 THEN
      RAISE EXCEPTION 'El ajuste negativo dejaría la cuenta líquida "%" con saldo negativo.', v_account.name
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  INSERT INTO public.transactions (
    user_id,
    client_request_id,
    type,
    status,
    currency_id,
    amount,
    occurred_at,
    description
  )
  VALUES (
    v_user_id,
    p_client_request_id,
    'adjustment',
    'posted',
    v_account.currency_id,
    abs(v_signed_amount),
    p_occurred_at,
    NULLIF(btrim(p_description), '')
  )
  RETURNING * INTO v_tx;

  INSERT INTO public.account_movements (
    user_id,
    transaction_id,
    account_id,
    currency_id,
    signed_amount,
    occurred_at
  )
  VALUES (
    v_user_id,
    v_tx.id,
    v_account.id,
    v_account.currency_id,
    v_signed_amount,
    p_occurred_at
  );

  RETURN v_tx;
END;
$$;

ALTER FUNCTION public.create_adjustment(uuid, uuid, numeric, timestamptz, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.create_adjustment(uuid, uuid, numeric, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_adjustment(uuid, uuid, numeric, timestamptz, text) TO authenticated;

-- 5.6. update_transaction_description
CREATE OR REPLACE FUNCTION public.update_transaction_description(
  p_transaction_id uuid,
  p_description text
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_tx public.transactions%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  SELECT t.*
    INTO v_tx
    FROM public.transactions t
   WHERE t.id = p_transaction_id
     AND t.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transacción no encontrada o no pertenece al usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE public.transactions t
     SET description = NULLIF(btrim(p_description), '')
   WHERE t.id = v_tx.id
     AND t.user_id = v_user_id
  RETURNING * INTO v_tx;

  RETURN v_tx;
END;
$$;

ALTER FUNCTION public.update_transaction_description(uuid, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.update_transaction_description(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_transaction_description(uuid, text) TO authenticated;

-- 5.7. void_transaction
CREATE OR REPLACE FUNCTION public.void_transaction(
  p_transaction_id uuid,
  p_void_reason text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_tx public.transactions%ROWTYPE;
  v_bad_account_name text;
BEGIN
  v_user_id := public._require_auth_user_id();

  SELECT t.*
    INTO v_tx
    FROM public.transactions t
   WHERE t.id = p_transaction_id
     AND t.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transacción no encontrada o no pertenece al usuario autenticado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_tx.status <> 'posted' THEN
    RAISE EXCEPTION 'Solo se pueden anular transacciones en estado posted.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Bloquear las cuentas afectadas en orden determinístico por UUID (sección 10.5)
  PERFORM 1
    FROM public.accounts a
   WHERE a.user_id = v_user_id
     AND a.id IN (
           SELECT m.account_id
             FROM public.account_movements m
            WHERE m.transaction_id = v_tx.id
         )
   ORDER BY a.id
     FOR UPDATE;

  UPDATE public.transactions t
     SET status = 'voided',
         voided_at = now(),
         void_reason = COALESCE(NULLIF(btrim(p_void_reason), ''), 'voided_by_user')
   WHERE t.id = v_tx.id
     AND t.user_id = v_user_id
  RETURNING * INTO v_tx;

  -- Comprobar inmediatamente que ninguna cuenta líquida afectada quede en negativo
  SELECT a.name
    INTO v_bad_account_name
    FROM public.accounts a
   WHERE a.id IN (
           SELECT m.account_id
             FROM public.account_movements m
            WHERE m.transaction_id = v_tx.id
         )
     AND a.type IN ('cash', 'bank', 'e_wallet')
     AND public._get_account_balance(a.id) < 0
   LIMIT 1;

  IF v_bad_account_name IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede anular la operación porque dejaría la cuenta líquida "%" con saldo negativo.', v_bad_account_name
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_tx;
END;
$$;

ALTER FUNCTION public.void_transaction(uuid, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.void_transaction(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_transaction(uuid, text) TO authenticated;

-- 5.8. replace_transaction (edición atómica: anula original y crea reemplazo - sección 6.10)
CREATE OR REPLACE FUNCTION public.replace_transaction(
  p_client_request_id uuid,
  p_transaction_id uuid,
  p_account_id uuid,
  p_amount numeric,
  p_occurred_at timestamptz,
  p_category_id uuid DEFAULT NULL,
  p_to_account_id uuid DEFAULT NULL,
  p_description text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_existing_tx public.transactions%ROWTYPE;
  v_old_tx public.transactions%ROWTYPE;
  v_orig_expense public.transactions%ROWTYPE;
  v_from_acc public.accounts%ROWTYPE;
  v_to_acc public.accounts%ROWTYPE;
  v_category public.categories%ROWTYPE;
  v_validated_amount numeric(18,4);
  v_tx_amount numeric(18,4);
  v_refunded_so_far numeric(18,4);
  v_bad_account_name text;
  v_new_tx public.transactions%ROWTYPE;
BEGIN
  v_user_id := public._require_auth_user_id();

  IF p_client_request_id IS NULL OR p_transaction_id IS NULL OR p_account_id IS NULL OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'client_request_id, transaction_id, account_id y occurred_at son obligatorios.'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- Idempotencia
  SELECT t.*
    INTO v_existing_tx
    FROM public.transactions t
   WHERE t.user_id = v_user_id
     AND t.client_request_id = p_client_request_id;

  IF FOUND THEN
    IF v_existing_tx.replaces_transaction_id = p_transaction_id THEN
      RETURN v_existing_tx;
    END IF;
    RAISE EXCEPTION 'client_request_id ya fue utilizado con parámetros diferentes.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 1. Bloquear transacción original
  SELECT t.*
    INTO v_old_tx
    FROM public.transactions t
   WHERE t.id = p_transaction_id
     AND t.user_id = v_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La transacción a reemplazar no existe o no pertenece al usuario.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_old_tx.status <> 'posted' THEN
    RAISE EXCEPTION 'Solo se pueden editar (reemplazar) transacciones en estado posted.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Si es devolución, bloquear primero el gasto original para serializar con otras devoluciones
  IF v_old_tx.type = 'refund' THEN
    SELECT t.*
      INTO v_orig_expense
      FROM public.transactions t
     WHERE t.id = v_old_tx.related_transaction_id
       AND t.user_id = v_user_id
       FOR UPDATE;

    IF NOT FOUND OR v_orig_expense.status <> 'posted' THEN
      RAISE EXCEPTION 'El gasto original de la devolución debe existir y estar en estado posted.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- 2. Bloquear todas las cuentas involucradas (anteriores y nuevas) en orden determinístico por UUID
  PERFORM 1
    FROM public.accounts a
   WHERE a.user_id = v_user_id
     AND (
       a.id IN (p_account_id, p_to_account_id)
       OR a.id IN (
            SELECT m.account_id
              FROM public.account_movements m
             WHERE m.transaction_id = v_old_tx.id
          )
     )
   ORDER BY a.id
     FOR UPDATE;

  SELECT a.*
    INTO v_from_acc
    FROM public.accounts a
   WHERE a.id = p_account_id
     AND a.user_id = v_user_id;

  IF NOT FOUND OR NOT v_from_acc.is_active THEN
    RAISE EXCEPTION 'La cuenta seleccionada no existe, no pertenece al usuario o está inactiva.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- 3. Validar reglas específicas según el tipo que se mantiene inmutable
  IF v_old_tx.type IN ('income', 'expense') THEN
    SELECT c.*
      INTO v_category
      FROM public.categories c
     WHERE c.id = p_category_id
       AND c.user_id = v_user_id
       FOR UPDATE;

    IF NOT FOUND OR NOT v_category.is_active OR v_category.type <> v_old_tx.type THEN
      RAISE EXCEPTION 'La categoría debe existir, estar activa y coincidir con el tipo (%).', v_old_tx.type
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_old_tx.type = 'income' AND v_from_acc.type NOT IN ('cash', 'bank', 'e_wallet') THEN
      RAISE EXCEPTION 'Los ingresos solo pueden registrarse en cuentas líquidas.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_validated_amount := public._validate_monetary_amount(p_amount, v_from_acc.currency_id, false, false);
    v_tx_amount := v_validated_amount;

  ELSIF v_old_tx.type = 'transfer' THEN
    IF p_to_account_id IS NULL OR p_account_id = p_to_account_id THEN
      RAISE EXCEPTION 'Las cuentas de origen y destino de una transferencia deben ser diferentes.'
        USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT a.*
      INTO v_to_acc
      FROM public.accounts a
     WHERE a.id = p_to_account_id
       AND a.user_id = v_user_id;

    IF NOT FOUND OR NOT v_to_acc.is_active THEN
      RAISE EXCEPTION 'La cuenta de destino no existe, no pertenece al usuario o está inactiva.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_from_acc.currency_id <> v_to_acc.currency_id THEN
      RAISE EXCEPTION 'Ambas cuentas de la transferencia deben tener la misma moneda.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_from_acc.type NOT IN ('cash', 'bank', 'e_wallet') THEN
      RAISE EXCEPTION 'La cuenta de origen de una transferencia debe ser una cuenta líquida.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_validated_amount := public._validate_monetary_amount(p_amount, v_from_acc.currency_id, false, false);
    v_tx_amount := v_validated_amount;

  ELSIF v_old_tx.type = 'refund' THEN
    IF v_from_acc.currency_id <> v_orig_expense.currency_id THEN
      RAISE EXCEPTION 'La cuenta receptora debe tener la misma moneda que el gasto original.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_validated_amount := public._validate_monetary_amount(p_amount, v_from_acc.currency_id, false, false);
    v_tx_amount := v_validated_amount;

  ELSIF v_old_tx.type = 'adjustment' THEN
    v_validated_amount := public._validate_monetary_amount(p_amount, v_from_acc.currency_id, false, true);
    v_tx_amount := abs(v_validated_amount);
  END IF;

  -- 4. Anular la transacción original con void_reason = 'replaced'
  UPDATE public.transactions t
     SET status = 'voided',
         voided_at = now(),
         void_reason = 'replaced'
   WHERE t.id = v_old_tx.id
     AND t.user_id = v_user_id;

  -- Si es devolución, validar el acumulado de devoluciones después de anular la anterior
  IF v_old_tx.type = 'refund' THEN
    SELECT COALESCE(SUM(r.amount), 0)
      INTO v_refunded_so_far
      FROM public.transactions r
     WHERE r.related_transaction_id = v_orig_expense.id
       AND r.type = 'refund'
       AND r.status = 'posted';

    IF v_refunded_so_far + v_tx_amount > v_orig_expense.amount THEN
      RAISE EXCEPTION 'El nuevo importe de devolución supera el saldo pendiente del gasto original.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- 5. Insertar la transacción de reemplazo con replaces_transaction_id = v_old_tx.id
  INSERT INTO public.transactions (
    user_id,
    client_request_id,
    type,
    status,
    currency_id,
    amount,
    category_id,
    related_transaction_id,
    replaces_transaction_id,
    occurred_at,
    description
  )
  VALUES (
    v_user_id,
    p_client_request_id,
    v_old_tx.type,
    'posted',
    v_from_acc.currency_id,
    v_tx_amount,
    CASE
      WHEN v_old_tx.type IN ('income', 'expense') THEN v_category.id
      WHEN v_old_tx.type = 'refund' THEN v_orig_expense.category_id
      ELSE NULL
    END,
    CASE
      WHEN v_old_tx.type = 'refund' THEN v_orig_expense.id
      ELSE NULL
    END,
    v_old_tx.id,
    p_occurred_at,
    NULLIF(btrim(p_description), '')
  )
  RETURNING * INTO v_new_tx;

  -- 6. Insertar el/los movimientos de la transacción de reemplazo
  IF v_old_tx.type = 'income' THEN
    INSERT INTO public.account_movements (
      user_id, transaction_id, account_id, currency_id, signed_amount, occurred_at
    ) VALUES (
      v_user_id, v_new_tx.id, v_from_acc.id, v_from_acc.currency_id, v_tx_amount, p_occurred_at
    );
  ELSIF v_old_tx.type = 'expense' THEN
    INSERT INTO public.account_movements (
      user_id, transaction_id, account_id, currency_id, signed_amount, occurred_at
    ) VALUES (
      v_user_id, v_new_tx.id, v_from_acc.id, v_from_acc.currency_id, -v_tx_amount, p_occurred_at
    );
  ELSIF v_old_tx.type = 'transfer' THEN
    INSERT INTO public.account_movements (
      user_id, transaction_id, account_id, currency_id, signed_amount, occurred_at
    ) VALUES
      (v_user_id, v_new_tx.id, v_from_acc.id, v_from_acc.currency_id, -v_tx_amount, p_occurred_at),
      (v_user_id, v_new_tx.id, v_to_acc.id, v_to_acc.currency_id, v_tx_amount, p_occurred_at);
  ELSIF v_old_tx.type = 'refund' THEN
    INSERT INTO public.account_movements (
      user_id, transaction_id, account_id, currency_id, signed_amount, occurred_at
    ) VALUES (
      v_user_id, v_new_tx.id, v_from_acc.id, v_from_acc.currency_id, v_tx_amount, p_occurred_at
    );
  ELSIF v_old_tx.type = 'adjustment' THEN
    INSERT INTO public.account_movements (
      user_id, transaction_id, account_id, currency_id, signed_amount, occurred_at
    ) VALUES (
      v_user_id, v_new_tx.id, v_from_acc.id, v_from_acc.currency_id, v_validated_amount, p_occurred_at
    );
  END IF;

  -- 7. Verificar que ninguna cuenta líquida involucrada (anterior o nueva) haya quedado con saldo negativo
  SELECT a.name
    INTO v_bad_account_name
    FROM public.accounts a
   WHERE a.user_id = v_user_id
     AND a.type IN ('cash', 'bank', 'e_wallet')
     AND (
       a.id IN (p_account_id, p_to_account_id)
       OR a.id IN (
            SELECT m.account_id
              FROM public.account_movements m
             WHERE m.transaction_id = v_old_tx.id
          )
     )
     AND public._get_account_balance(a.id) < 0
   LIMIT 1;

  IF v_bad_account_name IS NOT NULL THEN
    RAISE EXCEPTION 'El reemplazo no es válido porque dejaría la cuenta líquida "%" con saldo negativo.', v_bad_account_name
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_new_tx;
END;
$$;

ALTER FUNCTION public.replace_transaction(uuid, uuid, uuid, numeric, timestamptz, uuid, uuid, text) OWNER TO app_ledger_writer;
REVOKE ALL ON FUNCTION public.replace_transaction(uuid, uuid, uuid, numeric, timestamptz, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_transaction(uuid, uuid, uuid, numeric, timestamptz, uuid, uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6. Vistas y funciones de lectura y resúmenes (secciones 6.11 y 9.7)
-- -----------------------------------------------------------------------------

-- 6.1. Vista account_balances (security_invoker = true para respetar RLS)
CREATE OR REPLACE VIEW public.account_balances
WITH (security_invoker = true)
AS
SELECT
  a.id AS account_id,
  a.user_id,
  a.currency_id,
  c.code AS currency_code,
  c.symbol AS currency_symbol,
  c.decimal_places AS currency_decimal_places,
  a.name,
  a.type,
  a.is_active,
  a.initial_balance,
  COALESCE(SUM(m.signed_amount) FILTER (WHERE t.status = 'posted'), 0)::numeric(18,4) AS movements_balance,
  (a.initial_balance + COALESCE(SUM(m.signed_amount) FILTER (WHERE t.status = 'posted'), 0))::numeric(18,4) AS current_balance,
  a.credit_limit,
  CASE
    WHEN a.type = 'credit_card' THEN
      (a.credit_limit + a.initial_balance + COALESCE(SUM(m.signed_amount) FILTER (WHERE t.status = 'posted'), 0))::numeric(18,4)
    ELSE NULL
  END AS available_credit,
  a.created_at,
  a.updated_at
FROM public.accounts a
JOIN public.currencies c ON c.id = a.currency_id
LEFT JOIN public.account_movements m ON m.account_id = a.id
LEFT JOIN public.transactions t ON t.id = m.transaction_id
GROUP BY
  a.id,
  a.user_id,
  a.currency_id,
  c.code,
  c.symbol,
  c.decimal_places,
  a.name,
  a.type,
  a.is_active,
  a.initial_balance,
  a.credit_limit,
  a.created_at,
  a.updated_at;

REVOKE ALL ON TABLE public.account_balances FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.account_balances TO authenticated;

-- 6.2. Función get_monthly_summary: resumen mensual por moneda en la zona horaria del usuario
CREATE OR REPLACE FUNCTION public.get_monthly_summary(
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  currency_id uuid,
  currency_code text,
  currency_symbol text,
  decimal_places smallint,
  income_total numeric(18,4),
  gross_expense_total numeric(18,4),
  refund_total numeric(18,4),
  net_expense_total numeric(18,4),
  monthly_balance numeric(18,4),
  transfer_total numeric(18,4),
  adjustment_net_total numeric(18,4)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Autenticación requerida.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_year IS NULL OR p_year < 1970 OR p_year > 2100
     OR p_month IS NULL OR p_month < 1 OR p_month > 12 THEN
    RAISE EXCEPTION 'Año o mes fuera de rango válido.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT COALESCE(p.timezone, 'America/Asuncion')
    INTO v_timezone
    FROM public.profiles p
   WHERE p.id = v_user_id;

  IF v_timezone IS NULL THEN
    v_timezone := 'America/Asuncion';
  END IF;

  v_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0, v_timezone);
  v_end := (make_timestamp(p_year, p_month, 1, 0, 0, 0) + interval '1 month') AT TIME ZONE v_timezone;

  RETURN QUERY
  WITH tx_agg AS (
    SELECT
      t.currency_id,
      COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'income'), 0)::numeric(18,4) AS income_sum,
      COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'expense'), 0)::numeric(18,4) AS expense_sum,
      COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'refund'), 0)::numeric(18,4) AS refund_sum,
      COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'transfer'), 0)::numeric(18,4) AS transfer_sum
    FROM public.transactions t
    WHERE t.user_id = v_user_id
      AND t.status = 'posted'
      AND t.occurred_at >= v_start
      AND t.occurred_at < v_end
    GROUP BY t.currency_id
  ),
  adj_agg AS (
    SELECT
      m.currency_id,
      COALESCE(SUM(m.signed_amount), 0)::numeric(18,4) AS adjustment_sum
    FROM public.account_movements m
    JOIN public.transactions t ON t.id = m.transaction_id
    WHERE t.user_id = v_user_id
      AND t.status = 'posted'
      AND t.type = 'adjustment'
      AND t.occurred_at >= v_start
      AND t.occurred_at < v_end
    GROUP BY m.currency_id
  )
  SELECT
    c.id AS currency_id,
    c.code AS currency_code,
    c.symbol AS currency_symbol,
    c.decimal_places,
    COALESCE(tx.income_sum, 0)::numeric(18,4) AS income_total,
    COALESCE(tx.expense_sum, 0)::numeric(18,4) AS gross_expense_total,
    COALESCE(tx.refund_sum, 0)::numeric(18,4) AS refund_total,
    (COALESCE(tx.expense_sum, 0) - COALESCE(tx.refund_sum, 0))::numeric(18,4) AS net_expense_total,
    (COALESCE(tx.income_sum, 0) - (COALESCE(tx.expense_sum, 0) - COALESCE(tx.refund_sum, 0)))::numeric(18,4) AS monthly_balance,
    COALESCE(tx.transfer_sum, 0)::numeric(18,4) AS transfer_total,
    COALESCE(adj.adjustment_sum, 0)::numeric(18,4) AS adjustment_net_total
  FROM public.currencies c
  LEFT JOIN tx_agg tx ON tx.currency_id = c.id
  LEFT JOIN adj_agg adj ON adj.currency_id = c.id
  WHERE c.is_active = true
     OR tx.currency_id IS NOT NULL
     OR adj.currency_id IS NOT NULL
  ORDER BY c.code;
END;
$$;

REVOKE ALL ON FUNCTION public.get_monthly_summary(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_monthly_summary(integer, integer) TO authenticated;

-- 6.3. Función get_monthly_account_flows: entradas y salidas por cuenta en el mes
CREATE OR REPLACE FUNCTION public.get_monthly_account_flows(
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  account_id uuid,
  account_name text,
  account_type text,
  is_active boolean,
  currency_id uuid,
  currency_code text,
  currency_symbol text,
  inflows_total numeric(18,4),
  outflows_total numeric(18,4),
  net_flow numeric(18,4)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Autenticación requerida.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_year IS NULL OR p_year < 1970 OR p_year > 2100
     OR p_month IS NULL OR p_month < 1 OR p_month > 12 THEN
    RAISE EXCEPTION 'Año o mes fuera de rango válido.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT COALESCE(p.timezone, 'America/Asuncion')
    INTO v_timezone
    FROM public.profiles p
   WHERE p.id = v_user_id;

  IF v_timezone IS NULL THEN
    v_timezone := 'America/Asuncion';
  END IF;

  v_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0, v_timezone);
  v_end := (make_timestamp(p_year, p_month, 1, 0, 0, 0) + interval '1 month') AT TIME ZONE v_timezone;

  RETURN QUERY
  SELECT
    a.id AS account_id,
    a.name AS account_name,
    a.type AS account_type,
    a.is_active,
    a.currency_id,
    c.code AS currency_code,
    c.symbol AS currency_symbol,
    COALESCE(SUM(m.signed_amount) FILTER (
      WHERE t.status = 'posted'
        AND m.occurred_at >= v_start
        AND m.occurred_at < v_end
        AND m.signed_amount > 0
    ), 0)::numeric(18,4) AS inflows_total,
    COALESCE(SUM(-m.signed_amount) FILTER (
      WHERE t.status = 'posted'
        AND m.occurred_at >= v_start
        AND m.occurred_at < v_end
        AND m.signed_amount < 0
    ), 0)::numeric(18,4) AS outflows_total,
    COALESCE(SUM(m.signed_amount) FILTER (
      WHERE t.status = 'posted'
        AND m.occurred_at >= v_start
        AND m.occurred_at < v_end
    ), 0)::numeric(18,4) AS net_flow
  FROM public.accounts a
  JOIN public.currencies c ON c.id = a.currency_id
  LEFT JOIN public.account_movements m ON m.account_id = a.id
  LEFT JOIN public.transactions t ON t.id = m.transaction_id
  WHERE a.user_id = v_user_id
  GROUP BY
    a.id,
    a.name,
    a.type,
    a.is_active,
    a.currency_id,
    c.code,
    c.symbol
  ORDER BY c.code, a.name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_monthly_account_flows(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_monthly_account_flows(integer, integer) TO authenticated;

-- -----------------------------------------------------------------------------
-- 7. Principio de mínimo privilegio: revocar CREATE temporal tras asignar OWNER
-- -----------------------------------------------------------------------------
REVOKE CREATE ON SCHEMA public FROM app_ledger_writer, app_user_purger;

