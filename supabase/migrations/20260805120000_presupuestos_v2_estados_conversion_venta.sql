-- =============================================================================
-- Presupuestos v2 — estados (borrador/vencido), referencia por ítem en factura,
-- conversión a venta trazada, idempotencia por tipo de destino, motivo en historial.
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode) y
-- respeta `neura.solo_schema` (aplicar solo a un schema). No toca `public`.
--   1. factura_items += presupuesto_item_id (referencia interna al ítem original).
--   2. ventas += presupuesto_id (relación presupuesto↔venta).
--   3. presupuesto_conversiones: UNIQUE(presupuesto_id) → UNIQUE(presupuesto_id, tipo_destino)
--      (permite convertir a factura Y venta sin duplicar cada una).
--   4. presupuesto_estado_historial += motivo.
-- =============================================================================

BEGIN;
SET LOCAL check_function_bodies = off;

DO $mig$
DECLARE
  sch text;
BEGIN
  FOR sch IN
    SELECT n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'presupuestos'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    -- 1) Referencia interna al ítem original del presupuesto (factura muestra solo nombre).
    EXECUTE format('ALTER TABLE %I.factura_items ADD COLUMN IF NOT EXISTS presupuesto_item_id uuid', sch);

    -- 2) Relación presupuesto ↔ venta.
    IF to_regclass(format('%I.ventas', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.ventas ADD COLUMN IF NOT EXISTS presupuesto_id uuid', sch);
      EXECUTE format('CREATE INDEX IF NOT EXISTS idx_ventas_presupuesto ON %I.ventas (empresa_id, presupuesto_id)', sch);
    END IF;

    -- 3) Idempotencia por (presupuesto_id, tipo_destino): factura y venta separadas.
    IF to_regclass(format('%I.presupuesto_conversiones', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.presupuesto_conversiones DROP CONSTRAINT IF EXISTS uq_presupuesto_conversion', sch);
      -- Índice único parcial equivalente (permite migrar sin chocar con filas previas).
      EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_presupuesto_conversion_tipo ON %I.presupuesto_conversiones (presupuesto_id, tipo_destino)', sch);
    END IF;

    -- 4) Motivo en el historial de estados.
    EXECUTE format('ALTER TABLE %I.presupuesto_estado_historial ADD COLUMN IF NOT EXISTS motivo text', sch);

    RAISE NOTICE 'Presupuestos v2 aplicado en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
