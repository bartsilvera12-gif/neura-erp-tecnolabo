-- =============================================================================
-- FASE 3 — Inventario: vistas configurables por usuario
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
-- `usuario_vistas` guarda, por usuario y por pantalla (clave), la configuración
-- de columnas visibles/orden, filtros guardados y ordenamiento. Genérico:
-- reutilizable por inventario, movimientos y reportes tabulares (Fase 10).
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
    WHERE c.relname = 'productos'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.usuario_vistas (
        id              uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id      uuid NOT NULL,
        usuario_id      uuid,
        usuario_email   text,
        clave           text NOT NULL,
        nombre          text NOT NULL DEFAULT 'Mi vista',
        config          jsonb NOT NULL DEFAULT '{}'::jsonb,
        es_predeterminada boolean NOT NULL DEFAULT false,
        created_at      timestamptz NOT NULL DEFAULT now(),
        updated_at      timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_usuario_vistas_lookup ON %I.usuario_vistas (empresa_id, usuario_email, clave)', sch);

    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.usuario_vistas ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS usuario_vistas_all ON %I.usuario_vistas', sch);
      EXECUTE format('CREATE POLICY usuario_vistas_all ON %I.usuario_vistas USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 3 (usuario_vistas) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
