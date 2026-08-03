-- =============================================================================
-- FASE 1 — Presupuestos: ampliación + conversión idempotente a factura
--
-- Aditivo e idempotente. Reutiliza el módulo único de presupuestos (no crea uno
-- nuevo). Resuelve el schema dinámicamente (sin hardcode), igual que Fase 0.
--
--   1. presupuestos      += tipo_cambio, condiciones_comerciales, convertido_factura_id,
--                           convertido_at, convertido_por
--   2. presupuesto_items += imagen_url, imagen_path, descripcion_comercial,
--                           especificaciones_tecnicas, caracteristicas (jsonb)
--   3. presupuesto_estado_historial  (bitácora de cambios de estado)
--   4. presupuesto_conversiones      (relación presupuesto↔factura↔venta;
--                                     UNIQUE(presupuesto_id) = guard idempotencia)
--   5. facturas          += presupuesto_id (vínculo al presupuesto de origen)
--   6. factura_items      += producto_id, sku, descuento (para copiar la conversión;
--                           la descripción sigue siendo SOLO el nombre comercial)
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
    WHERE c.relname = 'presupuestos'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
    ORDER BY 1
  LOOP
    -- ── 1) presupuestos ──────────────────────────────────────────────────────
    EXECUTE format('ALTER TABLE %I.presupuestos ADD COLUMN IF NOT EXISTS tipo_cambio numeric NOT NULL DEFAULT 1', sch);
    EXECUTE format('ALTER TABLE %I.presupuestos ADD COLUMN IF NOT EXISTS condiciones_comerciales text', sch);
    EXECUTE format('ALTER TABLE %I.presupuestos ADD COLUMN IF NOT EXISTS convertido_factura_id uuid', sch);
    EXECUTE format('ALTER TABLE %I.presupuestos ADD COLUMN IF NOT EXISTS convertido_at timestamptz', sch);
    EXECUTE format('ALTER TABLE %I.presupuestos ADD COLUMN IF NOT EXISTS convertido_por uuid', sch);

    -- ── 2) presupuesto_items ─────────────────────────────────────────────────
    EXECUTE format('ALTER TABLE %I.presupuesto_items ADD COLUMN IF NOT EXISTS imagen_url text', sch);
    EXECUTE format('ALTER TABLE %I.presupuesto_items ADD COLUMN IF NOT EXISTS imagen_path text', sch);
    EXECUTE format('ALTER TABLE %I.presupuesto_items ADD COLUMN IF NOT EXISTS descripcion_comercial text', sch);
    EXECUTE format('ALTER TABLE %I.presupuesto_items ADD COLUMN IF NOT EXISTS especificaciones_tecnicas text', sch);
    EXECUTE format($ddl$ALTER TABLE %I.presupuesto_items ADD COLUMN IF NOT EXISTS caracteristicas jsonb NOT NULL DEFAULT '[]'::jsonb$ddl$, sch);

    -- ── 3) presupuesto_estado_historial ──────────────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.presupuesto_estado_historial (
        id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        empresa_id     uuid NOT NULL,
        presupuesto_id uuid NOT NULL,
        estado_anterior text,
        estado_nuevo    text NOT NULL,
        observacion     text,
        usuario_id      uuid,
        usuario_nombre  text,
        created_at      timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_pre_estado_hist ON %I.presupuesto_estado_historial (empresa_id, presupuesto_id, created_at)',
      sch);
    IF to_regclass(format('%I.presupuestos', sch)) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pre_estado_hist_presupuesto_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format(
        'ALTER TABLE %I.presupuesto_estado_historial ADD CONSTRAINT pre_estado_hist_presupuesto_fk
           FOREIGN KEY (presupuesto_id) REFERENCES %I.presupuestos(id) ON DELETE CASCADE',
        sch, sch);
    END IF;

    -- ── 4) presupuesto_conversiones (idempotencia por UNIQUE presupuesto_id) ──
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.presupuesto_conversiones (
        id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        empresa_id     uuid NOT NULL,
        presupuesto_id uuid NOT NULL,
        tipo_destino   text NOT NULL DEFAULT 'factura',
        factura_id     uuid,
        venta_id       uuid,
        created_by     uuid,
        created_at     timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT uq_presupuesto_conversion UNIQUE (presupuesto_id)
      )
    $ddl$, sch);

    -- ── 5) facturas += presupuesto_id ────────────────────────────────────────
    EXECUTE format('ALTER TABLE %I.facturas ADD COLUMN IF NOT EXISTS presupuesto_id uuid', sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_facturas_presupuesto ON %I.facturas (empresa_id, presupuesto_id)', sch);

    -- ── 6) factura_items += producto_id, sku, descuento ──────────────────────
    EXECUTE format('ALTER TABLE %I.factura_items ADD COLUMN IF NOT EXISTS producto_id uuid', sch);
    EXECUTE format('ALTER TABLE %I.factura_items ADD COLUMN IF NOT EXISTS sku text', sch);
    EXECUTE format('ALTER TABLE %I.factura_items ADD COLUMN IF NOT EXISTS descuento numeric NOT NULL DEFAULT 0', sch);

    -- ── RLS para tablas nuevas (si existe la función del schema) ──────────────
    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.presupuesto_estado_historial ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS pre_estado_hist_all ON %I.presupuesto_estado_historial', sch);
      EXECUTE format(
        'CREATE POLICY pre_estado_hist_all ON %I.presupuesto_estado_historial
           USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))',
        sch, sch, sch);

      EXECUTE format('ALTER TABLE %I.presupuesto_conversiones ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS pre_conversiones_all ON %I.presupuesto_conversiones', sch);
      EXECUTE format(
        'CREATE POLICY pre_conversiones_all ON %I.presupuesto_conversiones
           USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))',
        sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 1 (presupuestos) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
