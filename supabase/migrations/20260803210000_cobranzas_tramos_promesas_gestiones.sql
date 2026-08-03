-- =============================================================================
-- FASE 7 — Cuentas por cobrar y cobranzas
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
--   1. cobros_clientes += idempotency_key (protección contra doble aplicación).
--   2. cuentas_por_cobrar: venta_id nullable + factura_id + numero_factura
--      (unifica orígenes venta/factura sin crear un segundo receivables).
--   3. aging_tramos      (tramos de cobranza CONFIGURABLES por empresa).
--   4. promesas_pago     (promesas con fecha/importe/responsable/estado/recordatorio).
--   5. gestiones_cobranza(historial de gestiones: llamada/whatsapp/correo/visita/nota/otro).
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
    WHERE c.relname = 'cuentas_por_cobrar'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
    ORDER BY 1
  LOOP
    -- ── 1) idempotencia de cobros ────────────────────────────────────────────
    IF to_regclass(format('%I.cobros_clientes', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.cobros_clientes ADD COLUMN IF NOT EXISTS idempotency_key text', sch);
      EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_cobros_idempotency ON %I.cobros_clientes (empresa_id, idempotency_key) WHERE idempotency_key IS NOT NULL', sch);
    END IF;

    -- ── 2) unificar orígenes de CxC (venta o factura) ────────────────────────
    EXECUTE format('ALTER TABLE %I.cuentas_por_cobrar ALTER COLUMN venta_id DROP NOT NULL', sch);
    EXECUTE format('ALTER TABLE %I.cuentas_por_cobrar ADD COLUMN IF NOT EXISTS factura_id uuid', sch);
    EXECUTE format('ALTER TABLE %I.cuentas_por_cobrar ADD COLUMN IF NOT EXISTS numero_factura text', sch);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_cxc_factura ON %I.cuentas_por_cobrar (empresa_id, factura_id) WHERE factura_id IS NOT NULL', sch);

    -- ── 3) tramos de cobranza configurables ──────────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.aging_tramos (
        id           uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id   uuid NOT NULL,
        nombre       text NOT NULL,
        dias_desde   integer,
        dias_hasta   integer,
        orden        integer NOT NULL DEFAULT 0,
        color        text,
        activo       boolean NOT NULL DEFAULT true,
        created_at   timestamptz NOT NULL DEFAULT now(),
        updated_at   timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_aging_tramos_empresa ON %I.aging_tramos (empresa_id, orden)', sch);

    -- ── 4) promesas de pago ──────────────────────────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.promesas_pago (
        id                   uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id           uuid NOT NULL,
        cliente_id           uuid NOT NULL,
        cuenta_por_cobrar_id uuid,
        fecha_promesa        date NOT NULL,
        monto                numeric NOT NULL DEFAULT 0,
        observacion          text,
        responsable_id       uuid,
        responsable_nombre   text,
        estado               text NOT NULL DEFAULT 'pendiente',
        recordatorio_at      timestamptz,
        created_by           uuid,
        created_at           timestamptz NOT NULL DEFAULT now(),
        updated_at           timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT promesas_pago_estado_check CHECK (estado = ANY (ARRAY['pendiente','cumplida','incumplida','anulada']))
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_promesas_pago_cliente ON %I.promesas_pago (empresa_id, cliente_id, fecha_promesa)', sch);

    -- ── 5) gestiones de cobranza ─────────────────────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.gestiones_cobranza (
        id                   uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id           uuid NOT NULL,
        cliente_id           uuid NOT NULL,
        cuenta_por_cobrar_id uuid,
        tipo                 text NOT NULL DEFAULT 'nota',
        resultado            text,
        observacion          text,
        usuario_id           uuid,
        usuario_nombre       text,
        fecha                timestamptz NOT NULL DEFAULT now(),
        created_at           timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT gestiones_cobranza_tipo_check CHECK (tipo = ANY (ARRAY['llamada','whatsapp','correo','visita','nota','otro']))
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_gestiones_cobranza_cliente ON %I.gestiones_cobranza (empresa_id, cliente_id, fecha DESC)', sch);

    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.aging_tramos ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS aging_tramos_all ON %I.aging_tramos', sch);
      EXECUTE format('CREATE POLICY aging_tramos_all ON %I.aging_tramos USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.promesas_pago ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS promesas_pago_all ON %I.promesas_pago', sch);
      EXECUTE format('CREATE POLICY promesas_pago_all ON %I.promesas_pago USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.gestiones_cobranza ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS gestiones_cobranza_all ON %I.gestiones_cobranza', sch);
      EXECUTE format('CREATE POLICY gestiones_cobranza_all ON %I.gestiones_cobranza USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 7 (cobranzas) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
