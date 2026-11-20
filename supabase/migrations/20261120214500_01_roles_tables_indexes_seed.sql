-- =============================================================================
-- Migración 01: Roles de ejecución, tablas de dominio, índices y monedas base
-- Referencia: docs/DATA_MODEL.md v1.3 (secciones 3, 4, 5, 7.1, 8.2, 8.3 y 11)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Roles dedicados de ejecución (sin login y sin BYPASSRLS)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_ledger_writer') THEN
    CREATE ROLE app_ledger_writer
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user_purger') THEN
    CREATE ROLE app_user_purger
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOBYPASSRLS;
  END IF;
END
$$;

-- El rol administrativo de migraciones necesita membresía para asignar
-- la propiedad (OWNER TO) de las funciones SECURITY DEFINER en Supabase.
GRANT app_ledger_writer TO CURRENT_USER;
GRANT app_user_purger TO CURRENT_USER;

-- Acceso de uso a los esquemas public y auth para poder invocar auth.uid()
GRANT USAGE ON SCHEMA public TO app_ledger_writer, app_user_purger;
GRANT USAGE ON SCHEMA auth TO app_ledger_writer, app_user_purger;
GRANT EXECUTE ON FUNCTION auth.uid() TO app_ledger_writer, app_user_purger;

-- -----------------------------------------------------------------------------
-- 2. Tabla: currencies (catálogo global de monedas)
-- -----------------------------------------------------------------------------
CREATE TABLE public.currencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  name text NOT NULL,
  symbol text NOT NULL,
  decimal_places smallint NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT currencies_code_unique UNIQUE (code),
  CONSTRAINT currencies_code_format_check CHECK (code ~ '^[A-Z]{3}$'),
  CONSTRAINT currencies_name_not_empty_check CHECK (btrim(name) <> ''),
  CONSTRAINT currencies_symbol_not_empty_check CHECK (btrim(symbol) <> ''),
  CONSTRAINT currencies_decimal_places_check CHECK (decimal_places BETWEEN 0 AND 4)
);

-- Carga inicial de monedas soportadas en V1 (PYG y USD)
INSERT INTO public.currencies (code, name, symbol, decimal_places, is_active)
VALUES
  ('PYG', 'Guaraní paraguayo', '₲', 0, true),
  ('USD', 'Dólar estadounidense', '$', 2, true)
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. Tabla: profiles (raíz de dominio del usuario autenticado)
-- -----------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NULL,
  default_currency_id uuid NOT NULL REFERENCES public.currencies(id) ON DELETE NO ACTION,
  timezone text NOT NULL DEFAULT 'America/Asuncion',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT profiles_display_name_not_empty_check
    CHECK (display_name IS NULL OR btrim(display_name) <> ''),
  CONSTRAINT profiles_timezone_not_empty_check
    CHECK (btrim(timezone) <> '')
);

-- -----------------------------------------------------------------------------
-- 4. Tabla: accounts (cuentas financieras del usuario)
-- -----------------------------------------------------------------------------
CREATE TABLE public.accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE NO ACTION,
  currency_id uuid NOT NULL REFERENCES public.currencies(id) ON DELETE NO ACTION,
  name text NOT NULL,
  type text NOT NULL,
  initial_balance numeric(18,4) NOT NULL DEFAULT 0,
  credit_limit numeric(18,4) NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT accounts_id_user_currency_unique UNIQUE (id, user_id, currency_id),
  CONSTRAINT accounts_name_not_empty_check CHECK (btrim(name) <> ''),
  CONSTRAINT accounts_type_check
    CHECK (type IN ('cash', 'bank', 'e_wallet', 'credit_card')),
  CONSTRAINT accounts_initial_balance_sign_check
    CHECK (
      (type IN ('cash', 'bank', 'e_wallet') AND initial_balance >= 0)
      OR (type = 'credit_card' AND initial_balance <= 0)
    ),
  CONSTRAINT accounts_credit_limit_check
    CHECK (
      (type = 'credit_card' AND credit_limit IS NOT NULL AND credit_limit > 0)
      OR (type IN ('cash', 'bank', 'e_wallet') AND credit_limit IS NULL)
    )
);

-- -----------------------------------------------------------------------------
-- 5. Tabla: categories (categorías y subcategorías personalizables)
-- -----------------------------------------------------------------------------
CREATE TABLE public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE NO ACTION,
  parent_id uuid NULL,
  name text NOT NULL,
  type text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT categories_id_user_unique UNIQUE (id, user_id),
  CONSTRAINT categories_id_user_type_unique UNIQUE (id, user_id, type),
  CONSTRAINT categories_name_not_empty_check CHECK (btrim(name) <> ''),
  CONSTRAINT categories_type_check CHECK (type IN ('income', 'expense')),
  CONSTRAINT categories_no_self_parent_check
    CHECK (parent_id IS NULL OR parent_id <> id),
  CONSTRAINT categories_parent_fk
    FOREIGN KEY (parent_id, user_id, type)
    REFERENCES public.categories(id, user_id, type)
    ON DELETE NO ACTION
);

-- -----------------------------------------------------------------------------
-- 6. Tabla: transactions (operaciones financieras)
-- -----------------------------------------------------------------------------
CREATE TABLE public.transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE NO ACTION,
  client_request_id uuid NOT NULL,
  type text NOT NULL,
  status text NOT NULL DEFAULT 'posted',
  currency_id uuid NOT NULL REFERENCES public.currencies(id) ON DELETE NO ACTION,
  amount numeric(18,4) NOT NULL,
  category_id uuid NULL,
  related_transaction_id uuid NULL,
  replaces_transaction_id uuid NULL,
  occurred_at timestamptz NOT NULL,
  description text NULL,
  voided_at timestamptz NULL,
  void_reason text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT transactions_id_user_currency_unique UNIQUE (id, user_id, currency_id),
  CONSTRAINT transactions_id_user_type_unique UNIQUE (id, user_id, type),
  CONSTRAINT transactions_user_client_request_unique UNIQUE (user_id, client_request_id),
  CONSTRAINT transactions_type_check
    CHECK (type IN ('income', 'expense', 'transfer', 'refund', 'adjustment')),
  CONSTRAINT transactions_status_check
    CHECK (status IN ('posted', 'voided')),
  CONSTRAINT transactions_amount_positive_check
    CHECK (amount > 0),
  CONSTRAINT transactions_category_by_type_check
    CHECK (
      (type IN ('income', 'expense', 'refund') AND category_id IS NOT NULL)
      OR (type IN ('transfer', 'adjustment') AND category_id IS NULL)
    ),
  CONSTRAINT transactions_related_by_type_check
    CHECK (
      (type = 'refund' AND related_transaction_id IS NOT NULL AND related_transaction_id <> id)
      OR (type <> 'refund' AND related_transaction_id IS NULL)
    ),
  CONSTRAINT transactions_replaces_not_self_check
    CHECK (replaces_transaction_id IS NULL OR replaces_transaction_id <> id),
  CONSTRAINT transactions_void_fields_check
    CHECK (
      (status = 'posted' AND voided_at IS NULL AND void_reason IS NULL)
      OR (
        status = 'voided'
        AND voided_at IS NOT NULL
        AND (void_reason IS NULL OR btrim(void_reason) <> '')
      )
    ),
  CONSTRAINT transactions_category_fk
    FOREIGN KEY (category_id, user_id)
    REFERENCES public.categories(id, user_id)
    ON DELETE NO ACTION,
  CONSTRAINT transactions_related_fk
    FOREIGN KEY (related_transaction_id, user_id, currency_id)
    REFERENCES public.transactions(id, user_id, currency_id)
    ON DELETE NO ACTION,
  CONSTRAINT transactions_replaces_fk
    FOREIGN KEY (replaces_transaction_id, user_id, type)
    REFERENCES public.transactions(id, user_id, type)
    ON DELETE NO ACTION
);

-- -----------------------------------------------------------------------------
-- 7. Tabla: account_movements (impacto contable por cuenta)
-- -----------------------------------------------------------------------------
CREATE TABLE public.account_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  transaction_id uuid NOT NULL,
  account_id uuid NOT NULL,
  currency_id uuid NOT NULL,
  signed_amount numeric(18,4) NOT NULL,
  occurred_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT account_movements_signed_amount_nonzero_check
    CHECK (signed_amount <> 0),
  CONSTRAINT account_movements_tx_account_unique
    UNIQUE (transaction_id, account_id),
  CONSTRAINT account_movements_transaction_fk
    FOREIGN KEY (transaction_id, user_id, currency_id)
    REFERENCES public.transactions(id, user_id, currency_id)
    ON DELETE NO ACTION,
  CONSTRAINT account_movements_account_fk
    FOREIGN KEY (account_id, user_id, currency_id)
    REFERENCES public.accounts(id, user_id, currency_id)
    ON DELETE NO ACTION
);

-- -----------------------------------------------------------------------------
-- 8. Índices (sección 11 de DATA_MODEL.md)
-- -----------------------------------------------------------------------------
-- accounts
CREATE INDEX idx_accounts_user_active
  ON public.accounts (user_id, is_active);

-- categories
CREATE INDEX idx_categories_user_type_active
  ON public.categories (user_id, type, is_active);

CREATE INDEX idx_categories_parent_user_type
  ON public.categories (parent_id, user_id, type);

CREATE UNIQUE INDEX uq_categories_root_name
  ON public.categories (user_id, type, lower(btrim(name)))
  WHERE parent_id IS NULL;

CREATE UNIQUE INDEX uq_categories_child_name
  ON public.categories (user_id, parent_id, lower(btrim(name)))
  WHERE parent_id IS NOT NULL;

-- transactions
CREATE INDEX idx_transactions_user_occurred_id
  ON public.transactions (user_id, occurred_at DESC, id DESC);

CREATE INDEX idx_transactions_user_type_occurred
  ON public.transactions (user_id, type, occurred_at DESC);

CREATE INDEX idx_transactions_user_category_occurred
  ON public.transactions (user_id, category_id, occurred_at DESC);

CREATE INDEX idx_transactions_related_tx
  ON public.transactions (related_transaction_id)
  WHERE related_transaction_id IS NOT NULL;

CREATE UNIQUE INDEX uq_transactions_replaces_tx
  ON public.transactions (replaces_transaction_id)
  WHERE replaces_transaction_id IS NOT NULL;

-- account_movements
CREATE INDEX idx_account_movements_account_occurred_id
  ON public.account_movements (account_id, occurred_at DESC, id DESC);

CREATE INDEX idx_account_movements_user_tx
  ON public.account_movements (user_id, transaction_id);

CREATE INDEX idx_account_movements_user_account_occurred
  ON public.account_movements (user_id, account_id, occurred_at DESC);

-- -----------------------------------------------------------------------------
-- 9. Activación preventiva de RLS desde la creación de las tablas
--    (Las políticas y privilegios detallados se definen en la Migración 03)
-- -----------------------------------------------------------------------------
ALTER TABLE public.currencies ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts FORCE ROW LEVEL SECURITY;

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories FORCE ROW LEVEL SECURITY;

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions FORCE ROW LEVEL SECURITY;

ALTER TABLE public.account_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_movements FORCE ROW LEVEL SECURITY;
