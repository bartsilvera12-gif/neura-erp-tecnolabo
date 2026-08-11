-- =============================================================================
-- Facturas: N.º de Orden de Compra del cliente (campo opcional, alfanumérico).
--
-- Aditivo e idempotente. Solo agrega la columna `numero_orden_compra` a la tabla
-- `facturas`. NO toca datos existentes, NO modifica el XML/SIFEN ni el KuDE (el
-- número queda disponible en el ERP y en la representación impresa de la factura).
-- Respeta `neura.solo_schema` para aplicar a un único schema. No toca `public`.
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
    EXECUTE format('ALTER TABLE %I.facturas ADD COLUMN IF NOT EXISTS numero_orden_compra text', sch);
    RAISE NOTICE 'facturas.numero_orden_compra en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
