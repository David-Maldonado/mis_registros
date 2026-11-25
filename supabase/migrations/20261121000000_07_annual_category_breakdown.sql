-- =============================================================================
-- Migración 07: Función de lectura anual por categoría para gráfico de torta
-- Referencia: docs/DATA_MODEL.md v1.3 (secciones 6.11 y 9.7)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_annual_category_breakdown(
  p_year integer,
  p_type text,
  p_currency_code text DEFAULT 'PYG'
)
RETURNS TABLE (
  category_id uuid,
  category_name text,
  total_amount numeric(18,4),
  percentage numeric(7,2)
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

  IF p_year IS NULL OR p_year < 1970 OR p_year > 2100 THEN
    RAISE EXCEPTION 'Año fuera de rango válido.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_type NOT IN ('income', 'expense') THEN
    RAISE EXCEPTION 'El tipo debe ser income o expense.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT COALESCE(p.timezone, 'America/Asuncion')
    INTO v_timezone
    FROM public.profiles p
   WHERE p.id = v_user_id;

  IF v_timezone IS NULL THEN
    v_timezone := 'America/Asuncion';
  END IF;

  v_start := make_timestamptz(p_year, 1, 1, 0, 0, 0, v_timezone);
  v_end := (make_timestamp(p_year, 1, 1, 0, 0, 0) + interval '1 year') AT TIME ZONE v_timezone;

  RETURN QUERY
  WITH cat_totals AS (
    SELECT
      t.category_id,
      COALESCE(c.name, 'Sin categoría') AS cat_name,
      SUM(
        CASE
          WHEN p_type = 'income' AND t.type = 'income' THEN t.amount
          WHEN p_type = 'expense' AND t.type = 'expense' THEN t.amount
          WHEN p_type = 'expense' AND t.type = 'refund' THEN -t.amount
          ELSE 0
        END
      )::numeric(18,4) AS net_amount
    FROM public.transactions t
    JOIN public.currencies cur ON cur.id = t.currency_id
    LEFT JOIN public.categories c ON c.id = t.category_id
    WHERE t.user_id = v_user_id
      AND t.status = 'posted'
      AND cur.code = COALESCE(NULLIF(btrim(p_currency_code), ''), 'PYG')
      AND t.occurred_at >= v_start
      AND t.occurred_at < v_end
      AND (
        (p_type = 'income' AND t.type = 'income')
        OR (p_type = 'expense' AND t.type IN ('expense', 'refund'))
      )
    GROUP BY t.category_id, c.name
    HAVING SUM(
      CASE
        WHEN p_type = 'income' AND t.type = 'income' THEN t.amount
        WHEN p_type = 'expense' AND t.type = 'expense' THEN t.amount
        WHEN p_type = 'expense' AND t.type = 'refund' THEN -t.amount
        ELSE 0
      END
    ) > 0
  ),
  grand AS (
    SELECT COALESCE(SUM(ct.net_amount), 0) AS grand_total
    FROM cat_totals ct
  )
  SELECT
    ct.category_id,
    ct.cat_name AS category_name,
    ct.net_amount AS total_amount,
    CASE
      WHEN g.grand_total > 0 THEN round((ct.net_amount * 100.0) / g.grand_total, 2)::numeric(7,2)
      ELSE 0::numeric(7,2)
    END AS percentage
  FROM cat_totals ct
  CROSS JOIN grand g
  ORDER BY ct.net_amount DESC, ct.cat_name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_annual_category_breakdown(integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_annual_category_breakdown(integer, text, text) TO authenticated;
