-- =============================================================================
-- Rol ASISTENTE ADMINISTRATIVO.
--
-- Usa el sistema de acceso por módulo que ya existe (`modulos` → `empresa_modulos`
-- → `usuario_modulos`). No se crea un esquema de permisos paralelo y no se toca
-- la capa de permisos por acción (`roles` / `rol_permisos`), que queda intacta.
--
-- Problema previo: cuatro ítems del menú no tenían módulo propio y pedían
-- prestado el de otro, así que era imposible expresar la matriz pedida:
--   Entidades bancarias → 'ventas'   (y por ruta caía en 'configuracion')
--   Cobranzas           → 'pagos'
--   Recibos             → 'pagos'
--   Otros ingresos      → 'ventas'
-- Con eso, dar Pagos regalaba Cobranzas y Recibos, y dar Cuentas bancarias
-- obligaba a abrir toda Configuración (timbrado, certificado SIFEN, roles).
-- Se les da módulo propio.
--
-- El administrador NO se ve afectado: su acceso se resuelve como "todos los
-- módulos activos de empresa_modulos", y los nuevos se insertan activos.
--
-- Aditiva e idempotente. Respeta `neura.solo_schema`. No toca `public`.
-- =============================================================================

BEGIN;

DO $mig$
DECLARE
  sch        text;
  v_empresa  uuid;
  v_modulo   uuid;
  v_usuario  uuid;
  r          record;
  -- Módulos nuevos: separan lo que antes viajaba prestado.
  nuevos     text[][] := ARRAY[
    ARRAY['entidades_bancarias', 'Entidades bancarias'],
    ARRAY['cobranzas',           'Cobranzas'],
    ARRAY['recibos',             'Recibos'],
    ARRAY['otros_ingresos',      'Otros ingresos']
  ];
  -- Matriz del rol. Comercial completo MENOS comisiones; de Finanzas solo lo
  -- pedido; Inventario y Compras completos.
  otorgados  text[] := ARRAY[
    -- Comercial
    'clientes', 'crm', 'gestion-clientes', 'ventas', 'presupuestos', 'planes',
    -- Finanzas (solo lo listado)
    'pagos', 'gastos', 'entidades_bancarias',
    -- Inventario (productos, movimientos, categorías, notas de salida, alertas)
    'inventario',
    -- Compras (órdenes, proveedores, cuentas por pagar)
    'compras'
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

    -- 1) Módulos nuevos + habilitación para la empresa (activos, para no quitarle
    --    nada al administrador).
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

    -- 2) Ficha ERP del asistente. La cuenta ya existe en auth.users; sin fila en
    --    `usuarios` el ERP no la reconoce (queda sin empresa, rol ni módulos).
    EXECUTE format(
      'SELECT id FROM %I.usuarios WHERE auth_user_id = $1::uuid', sch)
      INTO v_usuario USING 'fa5dcbba-5675-4a4a-b574-648dc754e9bd';

    IF v_usuario IS NULL THEN
      EXECUTE format(
        'INSERT INTO %I.usuarios (email, nombre, rol, empresa_id, auth_user_id, activo, area)
         VALUES ($1, $2, $3, $4, $5::uuid, true, $6) RETURNING id', sch)
        INTO v_usuario
        USING 'admin@admintecnolabo.com.py', 'Asistente Administrativo', 'usuario',
              v_empresa, 'fa5dcbba-5675-4a4a-b574-648dc754e9bd', 'administracion';
      RAISE NOTICE 'usuario asistente creado en %', sch;
    ELSE
      -- Idempotente: si ya existe, se asegura que no quede como admin.
      EXECUTE format(
        'UPDATE %I.usuarios SET rol = $2, activo = true WHERE id = $1', sch)
        USING v_usuario, 'usuario';
    END IF;

    -- 3) Módulos del asistente. Se reemplaza el set completo para que la
    --    migración sea idempotente y refleje exactamente la matriz.
    EXECUTE format('DELETE FROM %I.usuario_modulos WHERE usuario_id = $1', sch) USING v_usuario;

    FOR r IN
      EXECUTE format(
        'SELECT m.id FROM %I.modulos m
          JOIN %I.empresa_modulos em ON em.modulo_id = m.id AND em.empresa_id = $2 AND em.activo
         WHERE m.slug = ANY($1::text[])', sch, sch)
      USING otorgados, v_empresa
    LOOP
      EXECUTE format(
        'INSERT INTO %I.usuario_modulos (usuario_id, modulo_id) VALUES ($1, $2)', sch)
        USING v_usuario, r.id;
    END LOOP;

    RAISE NOTICE 'asistente administrativo configurado en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
