-- =============================================================================
-- Corrige el alcance del módulo `recibos`: corresponde SOLO al Asistente
-- Administrativo, no al Vendedor.
--
-- La migración anterior (20260823160000) se lo otorgó a los dos. Acá se le quita
-- al vendedor y se confirma en el asistente.
--
-- Idempotente y acotada a esos dos usuarios: no toca al administrador ni ningún
-- otro módulo. Respeta `neura.solo_schema`. No toca `public`.
-- =============================================================================

BEGIN;

DO $mig$
DECLARE
  sch       text;
  v_empresa uuid;
  v_modulo  uuid;
  v_usuario uuid;

  AUTH_ASISTENTE constant text := 'fa5dcbba-5675-4a4a-b574-648dc754e9bd';
  AUTH_VENDEDOR  constant text := '363904e6-8fd3-458f-996d-423f2b83c1a2';
BEGIN
  FOR sch IN
    SELECT n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'usuario_modulos'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    EXECUTE format('SELECT empresa_id FROM %I.empresa_modulos LIMIT 1', sch) INTO v_empresa;
    CONTINUE WHEN v_empresa IS NULL;

    EXECUTE format('SELECT id FROM %I.modulos WHERE slug = ''recibos''', sch) INTO v_modulo;
    CONTINUE WHEN v_modulo IS NULL;

    -- Quitar al vendedor.
    EXECUTE format('SELECT id FROM %I.usuarios WHERE auth_user_id = $1::uuid', sch)
      INTO v_usuario USING AUTH_VENDEDOR;
    IF v_usuario IS NOT NULL THEN
      EXECUTE format(
        'DELETE FROM %I.usuario_modulos WHERE usuario_id = $1 AND modulo_id = $2', sch)
        USING v_usuario, v_modulo;
      RAISE NOTICE 'recibos quitado al vendedor en %', sch;
    END IF;

    -- Asegurar en el asistente.
    EXECUTE format('SELECT id FROM %I.usuarios WHERE auth_user_id = $1::uuid', sch)
      INTO v_usuario USING AUTH_ASISTENTE;
    IF v_usuario IS NOT NULL THEN
      EXECUTE format(
        'INSERT INTO %I.usuario_modulos (usuario_id, modulo_id)
         SELECT $1, $2
          WHERE NOT EXISTS (SELECT 1 FROM %I.usuario_modulos WHERE usuario_id = $1 AND modulo_id = $2)',
        sch, sch) USING v_usuario, v_modulo;
    END IF;
  END LOOP;
END
$mig$;

COMMIT;
