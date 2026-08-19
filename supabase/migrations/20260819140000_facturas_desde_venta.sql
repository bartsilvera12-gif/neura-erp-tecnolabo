-- =============================================================================
-- Puente venta → factura: habilita emitir FACTURA ELECTRÓNICA (SIFEN) desde una
-- venta del POS.
--
-- Hasta ahora `facturas` solo podía nacer de un presupuesto (`presupuesto_id`).
-- El pipeline SIFEN emite exclusivamente sobre `facturas`, asi que las ventas de
-- caja no tenian forma de convertirse en un documento electronico: se cobraba y
-- ahi terminaba. El unico documento fiscal disponible era el ticket autoimpresor,
-- que es OTRO regimen y en esta empresa esta apagado (modo = 'sifen').
--
-- Se agrega `facturas.venta_id` + indice unico parcial: una venta puede tener a
-- lo sumo UNA factura, para que reintentar la emision sea idempotente y no
-- consuma numeracion fiscal de mas.
--
-- Aditiva e idempotente. No toca datos existentes ni el XML. Respeta
-- `neura.solo_schema`. No toca `public`.
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
    WHERE c.relname = 'facturas'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    EXECUTE format('ALTER TABLE %I.facturas ADD COLUMN IF NOT EXISTS venta_id uuid', sch);

    -- Unico parcial: solo aplica a las facturas que vienen de una venta.
    EXECUTE format(
      'CREATE UNIQUE INDEX IF NOT EXISTS facturas_venta_id_uniq
         ON %I.facturas (venta_id) WHERE venta_id IS NOT NULL', sch);

    RAISE NOTICE 'facturas.venta_id en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
