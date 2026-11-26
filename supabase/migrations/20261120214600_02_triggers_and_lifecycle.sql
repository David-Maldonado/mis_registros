-- =============================================================================
-- Migración 02: Triggers de timestamps, creación automática de perfil,
--               ciclo de vida, inmutabilidad, validación diferida y purga
-- Referencia: docs/DATA_MODEL.md v1.3 (secciones 7 y 12)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger reutilizable de updated_at (sección 7.2)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_accounts_set_updated_at
  BEFORE UPDATE ON public.accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_categories_set_updated_at
  BEFORE UPDATE ON public.categories
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_transactions_set_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 2. Creación automática del perfil al registrarse en auth.users (sección 7.3)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_default_currency_id uuid;
  v_display_name text;
BEGIN
  SELECT c.id
    INTO v_default_currency_id
    FROM public.currencies c
   WHERE c.code = 'PYG'
   LIMIT 1;

  IF v_default_currency_id IS NULL THEN
    RAISE EXCEPTION 'La moneda por defecto (PYG) no existe en public.currencies.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_display_name := NULLIF(btrim(NEW.raw_user_meta_data ->> 'display_name'), '');

  INSERT INTO public.profiles (
    id,
    display_name,
    default_currency_id,
    timezone
  )
  VALUES (
    NEW.id,
    v_display_name,
    v_default_currency_id,
    'America/Asuncion'
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- -----------------------------------------------------------------------------
-- 3. Protección del catálogo de monedas (sección 4.2)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_currencies_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_in_use boolean;
BEGIN
  v_in_use := EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.default_currency_id = OLD.id
  ) OR EXISTS (
    SELECT 1 FROM public.accounts a WHERE a.currency_id = OLD.id
  ) OR EXISTS (
    SELECT 1 FROM public.transactions t WHERE t.currency_id = OLD.id
  );

  IF TG_OP = 'DELETE' THEN
    IF v_in_use THEN
      RAISE EXCEPTION 'No se puede eliminar una moneda que está en uso.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND v_in_use THEN
    IF NEW.code IS DISTINCT FROM OLD.code
       OR NEW.decimal_places IS DISTINCT FROM OLD.decimal_places THEN
      RAISE EXCEPTION 'No se puede modificar el código ni los decimales de una moneda en uso.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_currencies_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_currencies_lifecycle
  BEFORE UPDATE OR DELETE ON public.currencies
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_currencies_lifecycle();

-- -----------------------------------------------------------------------------
-- 4. Validación de ciclo de vida de cuentas (sección 7.4)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_accounts_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_has_movements boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF current_user <> 'app_user_purger' THEN
      SELECT EXISTS (
        SELECT 1
          FROM public.account_movements m
         WHERE m.account_id = OLD.id
      ) INTO v_has_movements;

      IF v_has_movements THEN
        RAISE EXCEPTION 'No se puede eliminar una cuenta utilizada; debe desactivarse.'
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.currency_id IS DISTINCT FROM OLD.currency_id
     OR NEW.type IS DISTINCT FROM OLD.type
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Los campos id, user_id, currency_id, type y created_at de una cuenta son inmutables.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.initial_balance IS DISTINCT FROM OLD.initial_balance THEN
    SELECT EXISTS (
      SELECT 1
        FROM public.account_movements m
       WHERE m.account_id = OLD.id
    ) INTO v_has_movements;

    IF v_has_movements THEN
      RAISE EXCEPTION 'No se puede modificar el saldo inicial cuando la cuenta ya tiene movimientos.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_accounts_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_accounts_lifecycle
  BEFORE UPDATE OR DELETE ON public.accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_accounts_lifecycle();

-- -----------------------------------------------------------------------------
-- 5. Validación de jerarquía y ciclo de vida de categorías (sección 7.5)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_categories_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_parent_parent_id uuid;
  v_parent_user_id uuid;
  v_parent_type text;
  v_has_transactions boolean;
  v_has_children boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF current_user <> 'app_user_purger' THEN
      SELECT EXISTS (
        SELECT 1 FROM public.transactions t WHERE t.category_id = OLD.id
      ) INTO v_has_transactions;

      SELECT EXISTS (
        SELECT 1 FROM public.categories c WHERE c.parent_id = OLD.id
      ) INTO v_has_children;

      IF v_has_transactions OR v_has_children THEN
        RAISE EXCEPTION 'No se puede eliminar una categoría utilizada o con subcategorías; debe desactivarse.'
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    RETURN OLD;
  END IF;

  -- Validar jerarquía de máximo dos niveles cuando tiene categoría padre
  IF NEW.parent_id IS NOT NULL THEN
    SELECT c.parent_id, c.user_id, c.type
      INTO v_parent_parent_id, v_parent_user_id, v_parent_type
      FROM public.categories c
     WHERE c.id = NEW.parent_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La categoría padre especificada no existe.'
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF v_parent_user_id IS DISTINCT FROM NEW.user_id
       OR v_parent_type IS DISTINCT FROM NEW.type THEN
      RAISE EXCEPTION 'La categoría padre debe pertenecer al mismo usuario y tener el mismo tipo.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_parent_parent_id IS NOT NULL THEN
      RAISE EXCEPTION 'La jerarquía de categorías admite como máximo dos niveles.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Los campos id, user_id y created_at de una categoría son inmutables.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.transactions t WHERE t.category_id = OLD.id
    ) INTO v_has_transactions;

    SELECT EXISTS (
      SELECT 1 FROM public.categories c WHERE c.parent_id = OLD.id
    ) INTO v_has_children;

    IF NEW.type IS DISTINCT FROM OLD.type AND (v_has_transactions OR v_has_children) THEN
      RAISE EXCEPTION 'No se puede cambiar el tipo de una categoría utilizada o con subcategorías.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.parent_id IS DISTINCT FROM OLD.parent_id AND v_has_transactions THEN
      RAISE EXCEPTION 'No se puede cambiar la categoría padre de una categoría que ya fue utilizada.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF OLD.parent_id IS NULL AND NEW.parent_id IS NOT NULL AND v_has_children THEN
      RAISE EXCEPTION 'Una categoría raíz con subcategorías no puede convertirse en subcategoría.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_categories_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_categories_lifecycle
  BEFORE INSERT OR UPDATE OR DELETE ON public.categories
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_categories_lifecycle();

-- -----------------------------------------------------------------------------
-- 6. Inmutabilidad de transacciones (sección 7.6)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_transactions_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF current_user <> 'app_user_purger' THEN
      RAISE EXCEPTION 'Las transacciones no pueden eliminarse físicamente durante la operación normal.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;

  -- Campos financieros e identificadores inmutables
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.client_request_id IS DISTINCT FROM OLD.client_request_id
     OR NEW.type IS DISTINCT FROM OLD.type
     OR NEW.currency_id IS DISTINCT FROM OLD.currency_id
     OR NEW.amount IS DISTINCT FROM OLD.amount
     OR NEW.category_id IS DISTINCT FROM OLD.category_id
     OR NEW.related_transaction_id IS DISTINCT FROM OLD.related_transaction_id
     OR NEW.replaces_transaction_id IS DISTINCT FROM OLD.replaces_transaction_id
     OR NEW.occurred_at IS DISTINCT FROM OLD.occurred_at
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Los campos financieros e identificadores de una transacción son inmutables.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Una transacción anulada no admite ningún cambio posterior
  IF OLD.status = 'voided' THEN
    RAISE EXCEPTION 'Una transacción anulada no puede reactivarse ni modificarse.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Al pasar de posted a voided, si es un gasto no debe tener devoluciones posted
  IF OLD.status = 'posted' AND NEW.status = 'voided' THEN
    IF OLD.type = 'expense' AND EXISTS (
      SELECT 1
        FROM public.transactions r
       WHERE r.related_transaction_id = OLD.id
         AND r.type = 'refund'
         AND r.status = 'posted'
    ) THEN
      RAISE EXCEPTION 'No se puede anular un gasto mientras tenga devoluciones contabilizadas.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_transactions_immutability() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_transactions_immutability
  BEFORE UPDATE OR DELETE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_transactions_immutability();

-- -----------------------------------------------------------------------------
-- 7. Inmutabilidad de movimientos de cuenta (sección 7.7)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_account_movements_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Los movimientos de cuenta son inmutables.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF current_user <> 'app_user_purger' THEN
      RAISE EXCEPTION 'Los movimientos de cuenta no pueden eliminarse durante la operación normal.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_account_movements_immutability() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_account_movements_immutability
  BEFORE UPDATE OR DELETE ON public.account_movements
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_account_movements_immutability();

-- -----------------------------------------------------------------------------
-- 8. Validación diferida de movimientos e invariantes financieras (sección 7.8)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_validate_transaction_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_tx_id uuid;
  v_tx public.transactions%ROWTYPE;
  v_decimal_places smallint;
  v_cat_type text;
  v_orig_tx public.transactions%ROWTYPE;
  v_replaced_tx public.transactions%ROWTYPE;
  v_total_refunded numeric(18,4);
  v_mov_count integer;
  v_mov_sum numeric(18,4);
  v_pos_count integer;
  v_neg_count integer;
  v_single_amount numeric(18,4);
  v_single_acc_type text;
  v_origin_acc_type text;
  v_dest_acc_type text;
  v_bad_account_name text;
BEGIN
  IF TG_TABLE_NAME = 'transactions' THEN
    v_tx_id := COALESCE(NEW.id, OLD.id);
  ELSE
    v_tx_id := COALESCE(NEW.transaction_id, OLD.transaction_id);
  END IF;

  SELECT t.*
    INTO v_tx
    FROM public.transactions t
   WHERE t.id = v_tx_id;

  -- Si la transacción ya no existe (eliminada durante la purga de usuario), no validar
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- 1. Validar precisión decimal según la moneda de la transacción
  SELECT c.decimal_places
    INTO v_decimal_places
    FROM public.currencies c
   WHERE c.id = v_tx.currency_id;

  IF round(v_tx.amount, v_decimal_places) <> v_tx.amount THEN
    RAISE EXCEPTION 'El importe de la transacción excede los decimales permitidos para la moneda.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- 2. Validar coherencia de reemplazo cuando replaces_transaction_id no es NULL
  IF v_tx.replaces_transaction_id IS NOT NULL THEN
    SELECT t.*
      INTO v_replaced_tx
      FROM public.transactions t
     WHERE t.id = v_tx.replaces_transaction_id;

    IF NOT FOUND
       OR v_replaced_tx.user_id IS DISTINCT FROM v_tx.user_id
       OR v_replaced_tx.type IS DISTINCT FROM v_tx.type
       OR v_replaced_tx.status <> 'voided' THEN
      RAISE EXCEPTION 'La transacción reemplazada debe pertenecer al mismo usuario, ser del mismo tipo y estar anulada.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- 3. Validar correspondencia de usuario, moneda, fecha y precisión en sus movimientos
  IF EXISTS (
    SELECT 1
      FROM public.account_movements m
     WHERE m.transaction_id = v_tx.id
       AND (
         m.user_id IS DISTINCT FROM v_tx.user_id
         OR m.currency_id IS DISTINCT FROM v_tx.currency_id
         OR m.occurred_at IS DISTINCT FROM v_tx.occurred_at
         OR round(m.signed_amount, v_decimal_places) <> m.signed_amount
       )
  ) THEN
    RAISE EXCEPTION 'Los movimientos deben coincidir en usuario, moneda, fecha y precisión con la transacción.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- 4. Validar cantidad y signos de movimientos según tipo de operación
  SELECT
    COUNT(*),
    COALESCE(SUM(m.signed_amount), 0),
    COUNT(*) FILTER (WHERE m.signed_amount = v_tx.amount),
    COUNT(*) FILTER (WHERE m.signed_amount = -v_tx.amount)
    INTO v_mov_count, v_mov_sum, v_pos_count, v_neg_count
    FROM public.account_movements m
   WHERE m.transaction_id = v_tx.id;

  IF v_tx.type IN ('income', 'expense', 'refund', 'adjustment') THEN
    IF v_mov_count <> 1 THEN
      RAISE EXCEPTION 'La transacción de tipo % debe tener exactamente 1 movimiento (tiene %).', v_tx.type, v_mov_count
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT m.signed_amount, a.type
      INTO v_single_amount, v_single_acc_type
      FROM public.account_movements m
      JOIN public.accounts a ON a.id = m.account_id
     WHERE m.transaction_id = v_tx.id;
  END IF;

  IF v_tx.type = 'income' THEN
    IF v_single_amount <> v_tx.amount THEN
      RAISE EXCEPTION 'Un ingreso debe generar un movimiento positivo igual al importe.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_single_acc_type NOT IN ('cash', 'bank', 'e_wallet') THEN
      RAISE EXCEPTION 'Los ingresos solo pueden registrarse en cuentas líquidas.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT c.type INTO v_cat_type FROM public.categories c WHERE c.id = v_tx.category_id;
    IF v_cat_type IS DISTINCT FROM 'income' THEN
      RAISE EXCEPTION 'Un ingreso requiere una categoría de tipo income.'
        USING ERRCODE = 'check_violation';
    END IF;

  ELSIF v_tx.type = 'expense' THEN
    IF v_single_amount <> -v_tx.amount THEN
      RAISE EXCEPTION 'Un gasto debe generar un movimiento negativo igual al importe.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT c.type INTO v_cat_type FROM public.categories c WHERE c.id = v_tx.category_id;
    IF v_cat_type IS DISTINCT FROM 'expense' THEN
      RAISE EXCEPTION 'Un gasto requiere una categoría de tipo expense.'
        USING ERRCODE = 'check_violation';
    END IF;

  ELSIF v_tx.type = 'refund' THEN
    IF v_single_amount <> v_tx.amount THEN
      RAISE EXCEPTION 'Una devolución debe generar un movimiento positivo igual al importe.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT t.*
      INTO v_orig_tx
      FROM public.transactions t
     WHERE t.id = v_tx.related_transaction_id;

    IF NOT FOUND
       OR v_orig_tx.type <> 'expense'
       OR v_orig_tx.user_id IS DISTINCT FROM v_tx.user_id
       OR v_orig_tx.currency_id IS DISTINCT FROM v_tx.currency_id
       OR v_orig_tx.category_id IS DISTINCT FROM v_tx.category_id THEN
      RAISE EXCEPTION 'La devolución debe referenciar un gasto del mismo usuario, moneda y categoría.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_tx.status = 'posted' THEN
      IF v_orig_tx.status <> 'posted' THEN
        RAISE EXCEPTION 'El gasto original de una devolución contabilizada debe estar en estado posted.'
          USING ERRCODE = 'check_violation';
      END IF;

      SELECT COALESCE(SUM(r.amount), 0)
        INTO v_total_refunded
        FROM public.transactions r
       WHERE r.related_transaction_id = v_orig_tx.id
         AND r.type = 'refund'
         AND r.status = 'posted';

      IF v_total_refunded > v_orig_tx.amount THEN
        RAISE EXCEPTION 'La suma de devoluciones contabilizadas supera el importe del gasto original.'
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;

  ELSIF v_tx.type = 'adjustment' THEN
    IF abs(v_single_amount) <> v_tx.amount THEN
      RAISE EXCEPTION 'El movimiento de un ajuste debe coincidir en valor absoluto con el importe.'
        USING ERRCODE = 'check_violation';
    END IF;

  ELSIF v_tx.type = 'transfer' THEN
    IF v_mov_count <> 2 OR v_mov_sum <> 0 OR v_pos_count <> 1 OR v_neg_count <> 1 THEN
      RAISE EXCEPTION 'Una transferencia debe tener exactamente dos movimientos opuestos que sumen cero.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT a.type
      INTO v_origin_acc_type
      FROM public.account_movements m
      JOIN public.accounts a ON a.id = m.account_id
     WHERE m.transaction_id = v_tx.id
       AND m.signed_amount < 0;

    SELECT a.type
      INTO v_dest_acc_type
      FROM public.account_movements m
      JOIN public.accounts a ON a.id = m.account_id
     WHERE m.transaction_id = v_tx.id
       AND m.signed_amount > 0;

    IF v_origin_acc_type NOT IN ('cash', 'bank', 'e_wallet') THEN
      RAISE EXCEPTION 'La cuenta de origen de una transferencia debe ser una cuenta líquida.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_dest_acc_type NOT IN ('cash', 'bank', 'e_wallet', 'credit_card') THEN
      RAISE EXCEPTION 'La cuenta de destino de una transferencia no tiene un tipo válido.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- 5. Validar que ninguna cuenta líquida involucrada quede con saldo negativo
  SELECT a.name
    INTO v_bad_account_name
    FROM public.accounts a
   WHERE a.id IN (
           SELECT m.account_id
             FROM public.account_movements m
            WHERE m.transaction_id = v_tx.id
         )
     AND a.type IN ('cash', 'bank', 'e_wallet')
     AND (
       a.initial_balance + COALESCE((
         SELECT SUM(m2.signed_amount)
           FROM public.account_movements m2
           JOIN public.transactions t2 ON t2.id = m2.transaction_id
          WHERE m2.account_id = a.id
            AND t2.status = 'posted'
       ), 0)
     ) < 0
   LIMIT 1;

  IF v_bad_account_name IS NOT NULL THEN
    RAISE EXCEPTION 'La operación no es válida porque dejaría la cuenta líquida "%" con saldo negativo.', v_bad_account_name
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_validate_transaction_ledger() FROM PUBLIC, anon, authenticated;

CREATE CONSTRAINT TRIGGER trg_transactions_validate_ledger
  AFTER INSERT OR UPDATE ON public.transactions
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_validate_transaction_ledger();

CREATE CONSTRAINT TRIGGER trg_account_movements_validate_ledger
  AFTER INSERT OR UPDATE OR DELETE ON public.account_movements
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_validate_transaction_ledger();

-- -----------------------------------------------------------------------------
-- 9. Purga controlada de datos al eliminar el perfil de un usuario (sección 12)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_profiles_purge_user_data()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  -- Orden de eliminación según sección 12 de DATA_MODEL.md v1.3:
  -- 1. Movimientos de cuenta
  DELETE FROM public.account_movements
   WHERE user_id = OLD.id;

  -- 2. Transacciones (devoluciones, reemplazos y demás en una sola sentencia)
  DELETE FROM public.transactions
   WHERE user_id = OLD.id;

  -- 3. Cuentas
  DELETE FROM public.accounts
   WHERE user_id = OLD.id;

  -- 4. Categorías (raíz y subcategorías en una sola sentencia)
  DELETE FROM public.categories
   WHERE user_id = OLD.id;

  RETURN OLD;
END;
$$;

-- En PostgreSQL, cambiar el propietario (OWNER TO) de una función en un esquema
-- requiere que el nuevo propietario tenga CREATE sobre ese esquema.
-- Se revoca al finalizar las migraciones de funciones (Migración 04).
GRANT CREATE ON SCHEMA public TO app_ledger_writer, app_user_purger;

ALTER FUNCTION public.trg_profiles_purge_user_data() OWNER TO app_user_purger;
REVOKE ALL ON FUNCTION public.trg_profiles_purge_user_data() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_profiles_purge_user_data
  BEFORE DELETE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_profiles_purge_user_data();
