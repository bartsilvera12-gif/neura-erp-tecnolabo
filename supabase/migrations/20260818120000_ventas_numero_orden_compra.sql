-- =============================================================================
-- Ventas: N.º de Orden de Compra del cliente (campo opcional, alfanumérico).
--
-- Cierra la cadena presupuesto → venta → factura autoimpresor / nota de remisión.
-- Hasta ahora la OC solo viajaba por la rama presupuesto → factura (crédito/CxC);
-- la rama de POS (`ventas`) la perdía, que es justamente la que se usa en
-- producción.
--
-- Aditiva e idempotente. Solo agrega `numero_orden_compra` a la tabla `ventas`.
-- NO toca datos existentes, NO toca el XML/SIFEN ni el KuDE. Respeta
-- `neura.solo_schema` para aplicar a un único schema. No toca `public`.
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
    EXECUTE format('ALTER TABLE %I.ventas ADD COLUMN IF NOT EXISTS numero_orden_compra text', sch);
    RAISE NOTICE 'ventas.numero_orden_compra en schema %', sch;

    -- Backfill: ventas ya creadas desde un presupuesto que tenía OC cargada.
    -- Solo completa las que están en NULL; no pisa nada cargado a mano.
    EXECUTE format(
      'UPDATE %I.ventas v
          SET numero_orden_compra = p.numero_orden_compra
         FROM %I.presupuestos p
        WHERE v.presupuesto_id = p.id
          AND v.numero_orden_compra IS NULL
          AND p.numero_orden_compra IS NOT NULL',
      sch, sch);
  END LOOP;
END
$mig$;

COMMIT;
