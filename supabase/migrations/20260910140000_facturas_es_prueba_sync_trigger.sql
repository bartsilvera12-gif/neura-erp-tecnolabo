-- =============================================================================
-- Consistencia ATÓMICA de es_prueba entre factura_electronica y facturas.
--
-- La app setea `factura_electronica.es_prueba` (borrador/firma) y denormaliza a
-- `facturas.es_prueba` con un update aparte (best-effort). Si ese segundo update
-- fallara de forma silenciosa, una factura de test podría quedar como real en
-- las vistas/totales (que filtran por facturas.es_prueba).
--
-- Este trigger elimina esa ventana: cada vez que se inserta o cambia
-- `factura_electronica.es_prueba`, se sincroniza `facturas.es_prueba` DENTRO de
-- la misma transacción del write del documento electrónico. Si el write del DE
-- commitea, la factura queda consistente sí o sí; si hace rollback, ninguno
-- cambia. La denormalización a nivel app queda como fast-path redundante y ya no
-- es la garantía.
--
-- Aditivo e idempotente (CREATE OR REPLACE + DROP/CREATE TRIGGER). No modifica
-- datos ni RLS. Respeta `neura.solo_schema`. No toca `public`.
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
    IF to_regclass(format('%I.facturas', sch)) IS NULL THEN
      CONTINUE;
    END IF;

    -- Función de sincronización (corre con el search_path del schema del tenant).
    EXECUTE format($fn$
      CREATE OR REPLACE FUNCTION %I.sync_facturas_es_prueba() RETURNS trigger
      LANGUAGE plpgsql
      SET search_path = %I, public
      AS $body$
      BEGIN
        IF NEW.factura_id IS NOT NULL THEN
          UPDATE facturas
             SET es_prueba = NEW.es_prueba
           WHERE id = NEW.factura_id
             AND empresa_id = NEW.empresa_id
             AND es_prueba IS DISTINCT FROM NEW.es_prueba;
        END IF;
        RETURN NEW;
      END;
      $body$;
    $fn$, sch, sch);

    EXECUTE format('DROP TRIGGER IF EXISTS trg_sync_facturas_es_prueba ON %I.factura_electronica', sch);
    EXECUTE format($tg$
      CREATE TRIGGER trg_sync_facturas_es_prueba
      AFTER INSERT OR UPDATE OF es_prueba ON %I.factura_electronica
      FOR EACH ROW EXECUTE FUNCTION %I.sync_facturas_es_prueba();
    $tg$, sch, sch);

    -- Backfill de consistencia: alinear cualquier factura que hoy difiera de su DE.
    EXECUTE format(
      'UPDATE %I.facturas f
          SET es_prueba = fe.es_prueba
         FROM %I.factura_electronica fe
        WHERE fe.factura_id = f.id
          AND fe.empresa_id = f.empresa_id
          AND f.es_prueba IS DISTINCT FROM fe.es_prueba', sch, sch);

    RAISE NOTICE 'trigger de consistencia es_prueba en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
