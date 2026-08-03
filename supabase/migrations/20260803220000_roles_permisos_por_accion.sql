-- =============================================================================
-- FASE 9 — Roles y permisos por acción · Límite de usuarios
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
-- No reemplaza el gating por módulo existente (empresa_modulos/usuario_modulos);
-- agrega una capa de permisos por ACCIÓN, opcional y retrocompatible:
--   - Si un usuario no tiene roles asignados → comportamiento legado (permitido).
--   - Si tiene roles → se exige el permiso puntual (crear/aprobar/confirmar/anular/…).
--   roles, rol_permisos, usuario_roles + empresa_config.max_usuarios.
-- =============================================================================

BEGIN;
SET LOCAL check_function_bodies = off;

DO $mig$
DECLARE
  sch text;
BEGIN
  FOR sch IN
    SELECT n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'usuarios'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    IF to_regclass(format('%I.empresa_config', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.empresa_config ADD COLUMN IF NOT EXISTS max_usuarios integer', sch);
    END IF;

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.roles (
        id          uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id  uuid NOT NULL,
        nombre      text NOT NULL,
        codigo      text NOT NULL,
        descripcion text,
        activo      boolean NOT NULL DEFAULT true,
        created_at  timestamptz NOT NULL DEFAULT now(),
        updated_at  timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT uq_roles_empresa_codigo UNIQUE (empresa_id, codigo)
      )
    $ddl$, sch);

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.rol_permisos (
        id         uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id uuid NOT NULL,
        rol_id     uuid NOT NULL,
        permiso    text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT uq_rol_permiso UNIQUE (rol_id, permiso)
      )
    $ddl$, sch);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rol_permisos_rol_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format('ALTER TABLE %I.rol_permisos ADD CONSTRAINT rol_permisos_rol_fk FOREIGN KEY (rol_id) REFERENCES %I.roles(id) ON DELETE CASCADE', sch, sch);
    END IF;

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.usuario_roles (
        id            uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id    uuid NOT NULL,
        usuario_id    uuid,
        usuario_email text,
        rol_id        uuid NOT NULL,
        created_at    timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT uq_usuario_rol UNIQUE (usuario_email, rol_id)
      )
    $ddl$, sch);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'usuario_roles_rol_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format('ALTER TABLE %I.usuario_roles ADD CONSTRAINT usuario_roles_rol_fk FOREIGN KEY (rol_id) REFERENCES %I.roles(id) ON DELETE CASCADE', sch, sch);
    END IF;
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_usuario_roles_email ON %I.usuario_roles (empresa_id, usuario_email)', sch);

    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.roles ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS roles_all ON %I.roles', sch);
      EXECUTE format('CREATE POLICY roles_all ON %I.roles USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.rol_permisos ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS rol_permisos_all ON %I.rol_permisos', sch);
      EXECUTE format('CREATE POLICY rol_permisos_all ON %I.rol_permisos USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.usuario_roles ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS usuario_roles_all ON %I.usuario_roles', sch);
      EXECUTE format('CREATE POLICY usuario_roles_all ON %I.usuario_roles USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 9 (roles/permisos) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
