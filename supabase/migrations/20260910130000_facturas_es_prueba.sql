-- =============================================================================
-- Documentos electrónicos de PRUEBA (SIFEN ambiente 'test') — marca por documento.
--
-- Problema: los documentos emitidos en ambiente de prueba llevan dentro del XML
-- el literal "DOCUMENTO ELECTRÓNICO SIN VALOR COMERCIAL NI FISCAL - GENERADO EN
-- AMBIENTE DE PRUEBA" y contaminan vistas/totales operativos. El ambiente NO se
-- persistía por documento (solo estaba en `empresa_sifen_config.ambiente`, que
-- es por empresa y cambia con el tiempo), así que no había forma de excluir SOLO
-- las pruebas sin ocultar documentos reales.
--
-- Solución: se persiste `es_prueba` por documento.
--   - factura_electronica.es_prueba  → fuente de verdad (se setea al FIRMAR,
--     desde el ambiente vigente en ese momento).
--   - facturas.es_prueba             → denormalización para filtrar barato en las
--     vistas operativas (dashboard, listados, estado de cuenta, KPIs).
--
-- Backfill histórico: la señal fiable del flujo de test es el QR con sufijo
-- '-test' (…/consultas-test/qr?…). En este código ESE QR se guarda dentro del
-- XML firmado (xml_firmado_path), no en la columna `qr_data` (que no se puebla).
-- Por eso el backfill autoritativo de históricos es el script
-- `scripts/backfill-facturas-es-prueba.ts` (lee el XML firmado desde storage y
-- setea es_prueba), que debe correrse en un entorno seguro con acceso a BD.
-- Aquí sólo se hace un backfill SQL inofensivo por `qr_data` (por si algún
-- registro legado la tuviera poblada). No usa estado='anulada' ni el modo
-- 'sin_factura_fiscal' como proxy: esos NO significan prueba.
--
-- Aditiva, idempotente y NO destructiva (solo agrega columnas y marca un flag en
-- documentos realmente de prueba). Respeta `neura.solo_schema`. No toca `public`.
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
    WHERE c.relname = 'factura_electronica'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    EXECUTE format('ALTER TABLE %I.factura_electronica ADD COLUMN IF NOT EXISTS es_prueba boolean NOT NULL DEFAULT false', sch);
    IF to_regclass(format('%I.facturas', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.facturas ADD COLUMN IF NOT EXISTS es_prueba boolean NOT NULL DEFAULT false', sch);
    END IF;

    -- Backfill inofensivo por qr_data (normalmente NULL en este código; solo
    -- marca documentos cuyo QR persistido apunta al portal de PRUEBAS).
    EXECUTE format(
      'UPDATE %I.factura_electronica
          SET es_prueba = true
        WHERE es_prueba = false
          AND qr_data IS NOT NULL
          AND position(''/consultas-test/'' in qr_data) > 0', sch);

    -- Propagar la marca desde el documento electrónico a su factura.
    IF to_regclass(format('%I.facturas', sch)) IS NOT NULL THEN
      EXECUTE format(
        'UPDATE %I.facturas f
            SET es_prueba = true
           FROM %I.factura_electronica fe
          WHERE fe.factura_id = f.id
            AND fe.empresa_id = f.empresa_id
            AND fe.es_prueba = true
            AND f.es_prueba = false', sch, sch);
    END IF;

    RAISE NOTICE 'factura_electronica/facturas.es_prueba en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
