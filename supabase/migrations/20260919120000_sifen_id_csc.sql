-- =============================================================================
-- SIFEN — ID del CSC (IdCSC) por empresa
--
-- El SET entrega dos CSC por timbrado: CSC1 (IdCSC 0001) y CSC2 (IdCSC 0002).
-- El `cHashQR` del QR se valida del lado del SET concatenando a la cadena de la
-- URL el CSC registrado para ESE IdCSC. Si se envía IdCSC=0001 pero el CSC
-- cargado es el CSC2, el SET rechaza el DE con «El hash del código QR incluido
-- el de la cadena de caracteres es inválido». Por eso el IdCSC debe ser
-- configurable por empresa y no una constante global.
--
-- La columna es NULLABLE a propósito: `null` significa «no configurado», y el
-- código cae al fallback de entorno (SIFEN_ID_CSC) y luego a '0001'. Con un
-- DEFAULT '0001' la columna pisaría esa variable en instalaciones que hoy
-- dependen de ella, rompiendo la firma justo al deployar.
--
-- Aditiva, idempotente y NO destructiva. Respeta `neura.solo_schema`. No toca
-- `public`.
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
    WHERE c.relname = 'empresa_sifen_config'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    EXECUTE format(
      'ALTER TABLE %I.empresa_sifen_config ADD COLUMN IF NOT EXISTS id_csc text', sch);

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'empresa_sifen_config_id_csc_chk'
        AND connamespace = sch::regnamespace
    ) THEN
      EXECUTE format(
        'ALTER TABLE %I.empresa_sifen_config
           ADD CONSTRAINT empresa_sifen_config_id_csc_chk
             CHECK (id_csc IS NULL OR id_csc ~ ''^[0-9]{4}$'')', sch);
    END IF;

    EXECUTE format(
      'COMMENT ON COLUMN %I.empresa_sifen_config.id_csc IS %L', sch,
      'Identificador del CSC asignado por el SET (0001 = CSC1, 0002 = CSC2). Se envía como IdCSC en la URL del QR y debe coincidir con el CSC cargado. NULL = usar el fallback SIFEN_ID_CSC del entorno.');
    EXECUTE format(
      'COMMENT ON COLUMN %I.empresa_sifen_config.csc IS %L', sch,
      'Código de Seguridad del Contribuyente correspondiente al id_csc cargado (32 caracteres en producción).');

    RAISE NOTICE 'empresa_sifen_config.id_csc en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
