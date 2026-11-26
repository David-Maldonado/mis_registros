-- =============================================================================
-- Suite pgTAP: Seguridad RLS, aislamiento multiusuario y reglas financieras
-- Referencia: docs/DATA_MODEL.md v1.3 (secciones 13.7 y 15)
-- Ejecutar localmente con: npx supabase test db
-- =============================================================================

BEGIN;

SELECT plan(14);

-- Preparar dos usuarios en auth.users (dispara handle_new_user -> profiles)
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'user_a@test.local', '{"display_name":"Usuario A"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'user_b@test.local', '{"display_name":"Usuario B"}'::jsonb);

-- Helper local de prueba para simular sesión autenticada JWT
CREATE OR REPLACE FUNCTION pg_temp.set_auth_user(p_uid uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
END;
$$;

-- 1. Verificar creación automática de perfiles con PYG y America/Asuncion
SELECT is(
  (SELECT count(*)::int FROM public.profiles
    WHERE id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
      AND timezone = 'America/Asuncion'),
  2,
  'Los perfiles de Usuario A y Usuario B se crean automáticamente con zona horaria America/Asuncion'
);

-- Cambiar al rol authenticated como Usuario A
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_auth_user('11111111-1111-1111-1111-111111111111');

-- 2. Bloqueo de DML directo sobre tablas de dominio
SELECT throws_ok(
  $$INSERT INTO public.categories (user_id, name, type) VALUES ('11111111-1111-1111-1111-111111111111', 'Directa', 'expense')$$,
  '42501',
  NULL,
  'authenticated no puede ejecutar INSERT directo sobre public.categories'
);

-- Crear cuentas y categorías vía RPC como Usuario A
DO $$
DECLARE
  v_pyg_id uuid;
  v_cash_acc public.accounts;
  v_card_acc public.accounts;
  v_inc_cat public.categories;
  v_exp_cat public.categories;
  v_tx_inc public.transactions;
  v_tx_exp public.transactions;
  v_tx_exp_dup public.transactions;
  v_tx_card public.transactions;
  v_tx_ref public.transactions;
  v_tx_rep public.transactions;
BEGIN
  SELECT id INTO v_pyg_id FROM public.currencies WHERE code = 'PYG';

  v_cash_acc := public.create_account(v_pyg_id, 'Efectivo A', 'cash', 100000, NULL);
  v_card_acc := public.create_account(v_pyg_id, 'Visa A', 'credit_card', 0, 500000);
  v_inc_cat := public.create_category('Salario', 'income', NULL);
  v_exp_cat := public.create_category('Supermercado', 'expense', NULL);

  -- Guardar IDs en variables de sesión temporales para las aserciones pgTAP
  PERFORM set_config('app.test_pyg_id', v_pyg_id::text, true);
  PERFORM set_config('app.test_cash_id', v_cash_acc.id::text, true);
  PERFORM set_config('app.test_card_id', v_card_acc.id::text, true);
  PERFORM set_config('app.test_inc_cat_id', v_inc_cat.id::text, true);
  PERFORM set_config('app.test_exp_cat_id', v_exp_cat.id::text, true);

  -- Ingreso de 400.000 -> saldo efectivo = 500.000
  v_tx_inc := public.create_income(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1',
    v_cash_acc.id,
    v_inc_cat.id,
    400000,
    '2026-11-10T15:00:00Z',
    'Cobro quincena'
  );
  PERFORM set_config('app.test_tx_inc_id', v_tx_inc.id::text, true);

  -- Gasto de 200.000 -> saldo efectivo = 300.000
  v_tx_exp := public.create_expense(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2',
    v_cash_acc.id,
    v_exp_cat.id,
    200000,
    '2026-11-11T15:00:00Z',
    'Compra super'
  );
  PERFORM set_config('app.test_tx_exp_id', v_tx_exp.id::text, true);

  -- Reintento idempotente con el mismo client_request_id
  v_tx_exp_dup := public.create_expense(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2',
    v_cash_acc.id,
    v_exp_cat.id,
    200000,
    '2026-11-11T15:00:00Z',
    'Compra super'
  );
  PERFORM set_config('app.test_tx_exp_dup_id', v_tx_exp_dup.id::text, true);

  -- Gasto con tarjeta superando límite de crédito (600.000 > 500.000): permitido
  v_tx_card := public.create_expense(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3',
    v_card_acc.id,
    v_exp_cat.id,
    600000,
    '2026-11-12T15:00:00Z',
    'Compra con tarjeta'
  );
  PERFORM set_config('app.test_tx_card_id', v_tx_card.id::text, true);

  -- Devolución parcial de 50.000 sobre el gasto de 200.000 -> saldo efectivo = 350.000
  v_tx_ref := public.create_refund(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4',
    v_tx_exp.id,
    v_cash_acc.id,
    50000,
    '2026-11-13T15:00:00Z',
    'Devolución parcial'
  );
  PERFORM set_config('app.test_tx_ref_id', v_tx_ref.id::text, true);

  -- Reemplazo atómico del gasto de tarjeta (600.000 -> 550.000)
  v_tx_rep := public.replace_transaction(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5',
    v_tx_card.id,
    v_card_acc.id,
    550000,
    '2026-11-12T16:00:00Z',
    v_exp_cat.id,
    NULL,
    'Compra corregida'
  );
  PERFORM set_config('app.test_tx_rep_id', v_tx_rep.id::text, true);
END;
$$;

-- 3. Saldo calculado de cuenta líquida correcto (100k + 400k - 200k + 50k = 350k)
SELECT is(
  (SELECT current_balance FROM public.account_balances WHERE account_id = current_setting('app.test_cash_id')::uuid),
  350000.0000::numeric(18,4),
  'El saldo calculado de Efectivo A refleja saldo inicial + ingresos - gastos + devoluciones'
);

-- 4. Idempotencia devuelve exactamente la misma transacción
SELECT is(
  current_setting('app.test_tx_exp_dup_id'),
  current_setting('app.test_tx_exp_id'),
  'Un reintento con el mismo client_request_id devuelve la transacción existente sin duplicar'
);

-- 5. Tarjeta de crédito permite superar el límite (límite informativo) y reemplazo actualizó saldo a -550.000
SELECT is(
  (SELECT current_balance FROM public.account_balances WHERE account_id = current_setting('app.test_card_id')::uuid),
  -550000.0000::numeric(18,4),
  'Tarjeta de crédito permite saldo negativo sobre el límite y refleja el reemplazo atómico (-550.000)'
);

-- 6. Transacción original reemplazada quedó en estado voided con void_reason = replaced
SELECT is(
  (SELECT status || ':' || void_reason FROM public.transactions WHERE id = current_setting('app.test_tx_card_id')::uuid),
  'voided:replaced',
  'replace_transaction anula la operación original con void_reason = replaced'
);

-- 7. Cuenta líquida rechaza gasto que la dejaría en negativo (350k - 400k < 0)
SELECT throws_ok(
  format(
    $$SELECT public.create_expense('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', %L, %L, 400000, '2026-11-14T15:00:00Z', 'Sobregiro')$$,
    current_setting('app.test_cash_id'),
    current_setting('app.test_exp_cat_id')
  ),
  '23514',
  NULL,
  'Una cuenta líquida rechaza un gasto que dejaría saldo negativo'
);

-- 8. Precisión decimal: PYG rechaza fracciones (100.5)
SELECT throws_ok(
  format(
    $$SELECT public.create_expense('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', %L, %L, 100.5, '2026-11-14T15:00:00Z', 'Decimal inválido')$$,
    current_setting('app.test_cash_id'),
    current_setting('app.test_exp_cat_id')
  ),
  '23514',
  NULL,
  'PYG rechaza importes con decimales antes de almacenarlos'
);

-- 9. Devoluciones acumuladas no pueden superar el gasto original (ya se devolvió 50k de 200k; 160k supera)
SELECT throws_ok(
  format(
    $$SELECT public.create_refund('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3', %L, %L, 160000, '2026-11-14T15:00:00Z', 'Exceso devolución')$$,
    current_setting('app.test_tx_exp_id'),
    current_setting('app.test_cash_id')
  ),
  '23514',
  NULL,
  'La suma de devoluciones contabilizadas nunca puede superar el gasto original'
);

-- 10. No se puede anular un gasto mientras tenga devoluciones contabilizadas
SELECT throws_ok(
  format(
    $$SELECT public.void_transaction(%L, 'intento anular con devolucion')$$,
    current_setting('app.test_tx_exp_id')
  ),
  '23514',
  NULL,
  'No se permite anular un gasto que tiene devoluciones contabilizadas'
);

-- 11. No se puede anular un ingreso si dejaría la cuenta líquida en negativo (350k - 400k < 0)
SELECT throws_ok(
  format(
    $$SELECT public.void_transaction(%L, 'intento anular ingreso gastado')$$,
    current_setting('app.test_tx_inc_id')
  ),
  '23514',
  NULL,
  'No se permite anular un ingreso si la cuenta líquida quedaría con saldo negativo'
);

-- Cambiar a Usuario B para verificar aislamiento multiusuario (RLS)
SELECT pg_temp.set_auth_user('22222222-2222-2222-2222-222222222222');

-- 12. Usuario B no ve ninguna cuenta de Usuario A
SELECT is(
  (SELECT count(*)::int FROM public.accounts),
  0,
  'Aislamiento RLS: Usuario B no puede consultar las cuentas de Usuario A'
);

-- 13. Usuario B no ve ninguna transacción de Usuario A
SELECT is(
  (SELECT count(*)::int FROM public.transactions),
  0,
  'Aislamiento RLS: Usuario B no puede consultar las transacciones de Usuario A'
);

-- 14. Usuario B no puede anular una transacción perteneciente a Usuario A
SELECT throws_ok(
  format(
    $$SELECT public.void_transaction(%L, 'ataque cross-user')$$,
    current_setting('app.test_tx_rep_id')
  ),
  'P0002',
  NULL,
  'Aislamiento RPC: Usuario B no puede anular transacciones de Usuario A'
);

SELECT * FROM finish();

ROLLBACK;
