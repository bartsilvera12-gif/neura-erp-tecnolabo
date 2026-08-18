-- =============================================================================
-- Notas de remisión sobre VENTAS (entregas parciales del flujo POS).
--
-- Problema: en el flujo real (presupuesto → venta → factura autoimpresor) la
-- nota de remisión no era un registro: era un número en `ventas.nota_remision_numero`
-- y un HTML dibujado al vuelo con TODOS los ítems de la venta. Si no había stock
-- y se entregaba de menos, no había forma de reflejarlo ni de saber qué quedaba
-- pendiente.
--
-- Solución: se generaliza `notas_remision` para que cuelgue de una factura O de
-- una venta, en lugar de duplicar toda la maquinaria. Se agrega el seguimiento
-- de entregado/pendiente sobre `ventas_items` y `ventas`.
--
-- IMPORTANTE — stock: en el flujo POS el stock YA se descuenta al registrar la
-- venta (movimiento origen 'venta'). Por lo tanto las remisiones de venta NO
-- mueven inventario: son un registro de ENTREGA. Esto es distinto de la rama de
-- facturas, donde el stock sale al confirmar la remisión.
--
-- Aditiva e idempotente. Respeta `neura.solo_schema`. No toca `public`.
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
    WHERE c.relname = 'notas_remision'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    -- 1) La remisión puede nacer de una factura o de una venta.
    EXECUTE format('ALTER TABLE %I.notas_remision ALTER COLUMN factura_id DROP NOT NULL', sch);
    EXECUTE format('ALTER TABLE %I.notas_remision ADD COLUMN IF NOT EXISTS venta_id uuid', sch);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS notas_remision_venta_id_idx ON %I.notas_remision (venta_id)', sch);

    -- Exactamente uno de los dos orígenes. Se crea solo si no existe todavía.
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'notas_remision_origen_chk'
        AND conrelid = format('%I.notas_remision', sch)::regclass
    ) THEN
      EXECUTE format(
        'ALTER TABLE %I.notas_remision ADD CONSTRAINT notas_remision_origen_chk
           CHECK ((factura_id IS NOT NULL) <> (venta_id IS NOT NULL))', sch);
    END IF;

    -- 2) Ítem de remisión ligado al ítem de venta.
    EXECUTE format('ALTER TABLE %I.notas_remision_items ADD COLUMN IF NOT EXISTS venta_item_id uuid', sch);

    -- 3) Seguimiento de entregado/pendiente en la venta.
    EXECUTE format(
      'ALTER TABLE %I.ventas_items ADD COLUMN IF NOT EXISTS cantidad_entregada numeric NOT NULL DEFAULT 0', sch);
    EXECUTE format(
      'ALTER TABLE %I.ventas ADD COLUMN IF NOT EXISTS estado_entrega text NOT NULL DEFAULT ''pendiente''', sch);

    RAISE NOTICE 'notas_remision sobre ventas en schema %', sch;
  END LOOP;
END
$mig$;

-- 4) Backfill histórico: las ventas anteriores a esta migración ya entregaron la
--    mercadería en el mostrador. Marcarlas como entregadas evita mostrar un
--    backlog de entregas pendientes que no existe. Solo afecta filas en 0.
DO $bf$
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
    EXECUTE format(
      'UPDATE %I.ventas_items SET cantidad_entregada = cantidad WHERE cantidad_entregada = 0', sch);
    EXECUTE format(
      'UPDATE %I.ventas SET estado_entrega = ''entregada'' WHERE estado_entrega = ''pendiente''', sch);
  END LOOP;
END
$bf$;

COMMIT;
