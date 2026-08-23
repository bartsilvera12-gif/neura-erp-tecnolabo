-- =============================================================================
-- Rol VENDEDOR / ÁREA COMERCIAL.
--
-- Usa el sistema de acceso por módulo existente (`modulos` → `empresa_modulos`
-- → `usuario_modulos`). No se crea arquitectura paralela y no se toca la capa de
-- permisos por acción (`roles` / `rol_permisos`).
--
-- Problema a resolver: Inventario era UN solo módulo. El vendedor necesita
-- Productos y Categorías pero NO Movimientos, Notas de salida ni Alertas, así
-- que la matriz pedida era inexpresable. Se parte en submódulos:
--
--   inventario              → Productos y Categorías (lo que queda del original)
--   inventario_movimientos  → Movimientos de inventario
--   inventario_alertas      → Alertas de stock
--   notas_salida            → Notas de salida
--
-- IMPORTANTE — no romper lo existente:
--   * El administrador resuelve su acceso como "todos los módulos activos de
--     empresa_modulos": los nuevos se insertan ACTIVOS, así que no pierde nada.
--   * El Asistente Administrativo SÍ tenía Inventario completo por matriz. Al
--     partir el módulo perdería Movimientos, Notas de salida y Alertas, así que
--     se le otorgan explícitamente los tres submódulos nuevos. Su acceso queda
--     idéntico al de antes.
--
-- Aditiva e idempotente. Respeta `neura.solo_schema`. No toca `public`.
-- =============================================================================

BEGIN;

DO $mig$
DECLARE
  sch          text;
  v_empresa    uuid;
  v_modulo     uuid;
  v_vendedor   uuid;
  v_asistente  uuid;
  r            record;

  AUTH_VENDEDOR  constant text := '363904e6-8fd3-458f-996d-423f2b83c1a2';
  AUTH_ASISTENTE constant text := 'fa5dcbba-5675-4a4a-b574-648dc754e9bd';

  -- Submódulos que se desprenden de Inventario.
  nuevos    text[][] := ARRAY[
    ARRAY['inventario_movimientos', 'Movimientos de inventario'],
    ARRAY['inventario_alertas',     'Alertas de stock'],
    ARRAY['notas_salida',           'Notas de salida']
  ];

  -- Vendedor: Comercial completo MENOS comisiones, e Inventario solo productos
  -- y categorías. Nada de Finanzas ni Compras.
  mods_vendedor  text[] := ARRAY[
    'clientes', 'crm', 'gestion-clientes', 'ventas', 'presupuestos', 'planes',
    'inventario'
  ];

  -- Asistente: recupera lo que el split le habría quitado.
  mods_asistente_extra text[] := ARRAY[
    'inventario_movimientos', 'inventario_alertas', 'notas_salida'
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
    IF v_empresa IS NULL THEN
      RAISE NOTICE 'schema % sin empresa_modulos; se omite', sch;
      CONTINUE;
    END IF;

    -- 1) Submódulos nuevos, activos para la empresa.
    FOR i IN 1 .. array_length(nuevos, 1) LOOP
      EXECUTE format('SELECT id FROM %I.modulos WHERE slug = $1', sch)
        INTO v_modulo USING nuevos[i][1];
      IF v_modulo IS NULL THEN
        EXECUTE format('INSERT INTO %I.modulos (nombre, slug) VALUES ($1, $2) RETURNING id', sch)
          INTO v_modulo USING nuevos[i][2], nuevos[i][1];
      END IF;
      EXECUTE format(
        'INSERT INTO %I.empresa_modulos (empresa_id, modulo_id, activo)
         SELECT $1, $2, true
          WHERE NOT EXISTS (SELECT 1 FROM %I.empresa_modulos WHERE empresa_id = $1 AND modulo_id = $2)',
        sch, sch) USING v_empresa, v_modulo;
    END LOOP;

    -- 2) Ficha ERP del vendedor.
    EXECUTE format('SELECT id FROM %I.usuarios WHERE auth_user_id = $1::uuid', sch)
      INTO v_vendedor USING AUTH_VENDEDOR;

    IF v_vendedor IS NULL THEN
      EXECUTE format(
        'INSERT INTO %I.usuarios (email, nombre, rol, empresa_id, auth_user_id, activo, area)
         VALUES ($1, $2, $3, $4, $5::uuid, true, $6) RETURNING id', sch)
        INTO v_vendedor
        USING 'comercial@tecnolabo.com.py', 'Vendedor / Área Comercial', 'vendedor',
              v_empresa, AUTH_VENDEDOR, 'ventas';
      RAISE NOTICE 'usuario vendedor creado en %', sch;
    ELSE
      EXECUTE format('UPDATE %I.usuarios SET activo = true WHERE id = $1', sch) USING v_vendedor;
    END IF;

    -- 3) Módulos del vendedor (set completo, idempotente).
    EXECUTE format('DELETE FROM %I.usuario_modulos WHERE usuario_id = $1', sch) USING v_vendedor;
    FOR r IN
      EXECUTE format(
        'SELECT m.id FROM %I.modulos m
          JOIN %I.empresa_modulos em ON em.modulo_id = m.id AND em.empresa_id = $2 AND em.activo
         WHERE m.slug = ANY($1::text[])', sch, sch)
      USING mods_vendedor, v_empresa
    LOOP
      EXECUTE format('INSERT INTO %I.usuario_modulos (usuario_id, modulo_id) VALUES ($1, $2)', sch)
        USING v_vendedor, r.id;
    END LOOP;

    -- 4) Compensar al Asistente Administrativo por el split de Inventario.
    EXECUTE format('SELECT id FROM %I.usuarios WHERE auth_user_id = $1::uuid', sch)
      INTO v_asistente USING AUTH_ASISTENTE;

    IF v_asistente IS NOT NULL THEN
      FOR r IN
        EXECUTE format(
          'SELECT m.id FROM %I.modulos m
            JOIN %I.empresa_modulos em ON em.modulo_id = m.id AND em.empresa_id = $2 AND em.activo
           WHERE m.slug = ANY($1::text[])', sch, sch)
        USING mods_asistente_extra, v_empresa
      LOOP
        EXECUTE format(
          'INSERT INTO %I.usuario_modulos (usuario_id, modulo_id)
           SELECT $1, $2
            WHERE NOT EXISTS (SELECT 1 FROM %I.usuario_modulos WHERE usuario_id = $1 AND modulo_id = $2)',
          sch, sch) USING v_asistente, r.id;
      END LOOP;
      RAISE NOTICE 'asistente compensado por el split de inventario en %', sch;
    END IF;

    RAISE NOTICE 'vendedor comercial configurado en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
