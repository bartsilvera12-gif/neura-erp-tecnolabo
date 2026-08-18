-- =============================================================================
-- Clientes: nombre a usar en el documento tributario (SIFEN).
--
-- Hoy el nombre del receptor sale de `empresa || nombre_contacto || nombre`
-- (ver nombreReceptor() en src/lib/sifen/build-payload.ts). Eso obliga a que el
-- nombre comercial del CRM sea también el nombre fiscal, que no siempre coincide
-- (persona física que factura a su RUC, razón social distinta del nombre de
-- fantasía, etc.).
--
-- `nombre_factura` pasa a ser la primera opción de esa cadena; si queda vacío el
-- comportamiento actual no cambia.
--
-- Aditiva e idempotente. NO toca datos existentes, NO cambia el XML ni la
-- estructura del DE: solo cambia de dónde se lee el nombre del receptor.
-- Respeta `neura.solo_schema`. No toca `public`.
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
    WHERE c.relname = 'clientes'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    EXECUTE format('ALTER TABLE %I.clientes ADD COLUMN IF NOT EXISTS nombre_factura text', sch);
    RAISE NOTICE 'clientes.nombre_factura en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
