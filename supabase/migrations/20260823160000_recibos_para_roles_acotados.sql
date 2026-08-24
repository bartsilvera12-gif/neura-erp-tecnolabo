-- =============================================================================
-- Otorga el módulo `recibos` al Asistente Administrativo y al Vendedor.
--
-- Los recibos se emiten al cobrar, y ambos roles operan Caja: sin este módulo
-- podían generar el recibo pero no consultarlo después en el listado.
--
-- Solo agrega; no quita nada ni toca al administrador. Aditiva e idempotente.
-- Respeta `neura.solo_schema`. No toca `public`.
-- =============================================================================

BEGIN;

DO $mig$
DECLARE
  sch       text;
  v_empresa uuid;
  v_modulo  uuid;
  v_usuario uuid;
  auth_ids  text[] := ARRAY[
    'fa5dcbba-5675-4a4a-b574-648dc754e9bd',  -- Asistente Administrativo
    '363904e6-8fd3-458f-996d-423f2b83c1a2'   -- Vendedor / Área Comercial
  ];
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

    EXECUTE format(
      'SELECT m.id FROM %I.modulos m
        JOIN %I.empresa_modulos em ON em.modulo_id = m.id AND em.empresa_id = $1 AND em.activo
       WHERE m.slug = ''recibos''', sch, sch)
      INTO v_modulo USING v_empresa;

    IF v_modulo IS NULL THEN
      RAISE NOTICE 'schema %: modulo recibos no disponible; se omite', sch;
      CONTINUE;
    END IF;

    FOR i IN 1 .. array_length(auth_ids, 1) LOOP
      EXECUTE format('SELECT id FROM %I.usuarios WHERE auth_user_id = $1::uuid', sch)
        INTO v_usuario USING auth_ids[i];

      IF v_usuario IS NOT NULL THEN
        EXECUTE format(
          'INSERT INTO %I.usuario_modulos (usuario_id, modulo_id)
           SELECT $1, $2
            WHERE NOT EXISTS (SELECT 1 FROM %I.usuario_modulos WHERE usuario_id = $1 AND modulo_id = $2)',
          sch, sch) USING v_usuario, v_modulo;
      END IF;
    END LOOP;

    RAISE NOTICE 'modulo recibos otorgado en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
