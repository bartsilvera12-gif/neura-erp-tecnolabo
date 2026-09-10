-- =============================================================================
-- Anulación de recibos de dinero (con reversión del cobro subyacente).
--
-- `recibos_dinero.anulado boolean` ya existía (el listado y la suma ya lo
-- respetan), pero NO había forma de anular ni se guardaba la trazabilidad de la
-- anulación. Se agregan los campos de auditoría de anulación que ya usan el
-- resto de los documentos del sistema (ventas, pagos_proveedor, devoluciones):
--   - recibos_dinero:  anulado_at / anulado_por / anulado_motivo
--
-- Además, como el recibo de origen 'cobro_cxc' es solo el COMPROBANTE de un
-- `cobros_clientes` (que es quien realmente bajó el saldo de la cuenta por
-- cobrar y sincronizó la factura), al anular el recibo hay que revertir ese
-- cobro. Para que el cobro revertido deje de contar como cobranza válida en
-- reportes/estado de cuenta, se agrega el mismo trío de anulación a:
--   - cobros_clientes: anulado_at / anulado_por / anulado_motivo
--
-- Aditiva e idempotente. No toca datos existentes (las columnas nacen NULL =
-- vigente). Respeta `neura.solo_schema`. No toca `public`.
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
    WHERE c.relname = 'recibos_dinero'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    -- Trazabilidad de la anulación del recibo (la columna `anulado boolean`
    -- ya existe desde la migración de provisión).
    EXECUTE format('ALTER TABLE %I.recibos_dinero ADD COLUMN IF NOT EXISTS anulado_at timestamptz', sch);
    EXECUTE format('ALTER TABLE %I.recibos_dinero ADD COLUMN IF NOT EXISTS anulado_por uuid', sch);
    EXECUTE format('ALTER TABLE %I.recibos_dinero ADD COLUMN IF NOT EXISTS anulado_motivo text', sch);

    -- Trazabilidad de la anulación del cobro subyacente (para excluirlo de
    -- reportes de cobranza y estado de cuenta sin borrarlo).
    IF to_regclass(format('%I.cobros_clientes', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.cobros_clientes ADD COLUMN IF NOT EXISTS anulado_at timestamptz', sch);
      EXECUTE format('ALTER TABLE %I.cobros_clientes ADD COLUMN IF NOT EXISTS anulado_por uuid', sch);
      EXECUTE format('ALTER TABLE %I.cobros_clientes ADD COLUMN IF NOT EXISTS anulado_motivo text', sch);
    END IF;

    RAISE NOTICE 'recibos_dinero/cobros_clientes: campos de anulación en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
