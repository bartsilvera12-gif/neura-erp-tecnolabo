-- =============================================================================
-- Corrige el backfill de 20260818140000 y fija la semántica de `estado_entrega`.
--
-- Aquella migración asumió que toda venta anterior ya estaba entregada y marcó
-- `cantidad_entregada = cantidad`. Consecuencia práctica: una venta de días atrás
-- quedaba con pendiente 0 y no se le podía emitir la nota de remisión, que es
-- justo lo que se necesita.
--
-- Semántica correcta: `ventas_items.cantidad_entregada` y `ventas.estado_entrega`
-- reflejan lo REMITIDO (documentado en una nota de remisión), no lo que el
-- cliente se llevó del mostrador. Así:
--   - toda venta sin remisiones queda disponible para remitir, cualquier día;
--   - el estado se deriva siempre de las remisiones reales, sin suposiciones.
--
-- Solo toca ventas que NO tienen ninguna nota de remisión asociada, de modo que
-- si ya se registraron entregas reales, no se pisan.
--
-- Idempotente. Respeta `neura.solo_schema`. No toca `public`.
-- =============================================================================

BEGIN;

DO $mig$
DECLARE
  sch text;
BEGIN
  FOR sch IN
    SELECT n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'ventas'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    -- Ítems de ventas sin remisiones: vuelven a 0 remitido.
    EXECUTE format(
      'UPDATE %I.ventas_items vi
          SET cantidad_entregada = 0
        WHERE vi.cantidad_entregada <> 0
          AND NOT EXISTS (
                SELECT 1 FROM %I.notas_remision nr
                 WHERE nr.venta_id = vi.venta_id
                   AND nr.estado <> ''anulada'')',
      sch, sch);

    -- Recalcular el estado de todas las ventas a partir de sus ítems.
    EXECUTE format(
      'UPDATE %I.ventas v
          SET estado_entrega = CASE
                WHEN t.entr <= 0 THEN ''pendiente''
                WHEN t.entr >= t.vend THEN ''entregada''
                ELSE ''parcialmente_entregada''
              END
         FROM (
           SELECT venta_id,
                  COALESCE(SUM(cantidad), 0)            AS vend,
                  COALESCE(SUM(cantidad_entregada), 0)  AS entr
             FROM %I.ventas_items
            GROUP BY venta_id
         ) t
        WHERE t.venta_id = v.id',
      sch, sch);

    RAISE NOTICE 'estado_entrega recalculado desde remisiones en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
