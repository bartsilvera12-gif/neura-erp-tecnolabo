-- =============================================================================
-- FASE 0 — Núcleo operativo Tecnolabo
--
-- Aditivo e idempotente. NO altera datos ni comportamiento existente:
--   1. Amplía el ledger `movimientos_inventario` con depósito/sucursal/
--      observación y referencia de documento genérica (documento_tipo/documento_id).
--   2. Amplía el CHECK de `origen` con los nuevos orígenes operativos
--      (recepcion, remision, nota_salida, ajuste, transferencia, anulacion),
--      conservando los valores previos.
--   3. Crea `documento_correlativos` (numeración correlativa server-side genérica).
--   4. Crea `empresa_config` (feature flags per-empresa, incluida
--      stock_salida_por_remision) — sin tocar ConfigGlobal/localStorage.
--   5. Crea `auditoria_eventos` (bitácora genérica: usuario, fecha, empresa, origen).
--
-- El schema operativo NO se hardcodea: se resuelve como el/los schema(s) que
-- contienen la tabla `empresas` excluyendo `public` (una instancia dedicada
-- resuelve exactamente su propio schema). Mismo idiom que las migraciones
-- multi-schema del repo (DO $$ ... EXECUTE format('%I', sch) ... $$).
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
    WHERE c.relname = 'empresas'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
    ORDER BY 1
  LOOP
    -- ── 1) Ledger: columnas nuevas (aditivas, nullable) ──────────────────────
    IF to_regclass(format('%I.movimientos_inventario', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.movimientos_inventario ADD COLUMN IF NOT EXISTS deposito_id uuid', sch);
      EXECUTE format('ALTER TABLE %I.movimientos_inventario ADD COLUMN IF NOT EXISTS sucursal_id uuid', sch);
      EXECUTE format('ALTER TABLE %I.movimientos_inventario ADD COLUMN IF NOT EXISTS observacion text', sch);
      EXECUTE format('ALTER TABLE %I.movimientos_inventario ADD COLUMN IF NOT EXISTS documento_tipo text', sch);
      EXECUTE format('ALTER TABLE %I.movimientos_inventario ADD COLUMN IF NOT EXISTS documento_id uuid', sch);
      EXECUTE format('ALTER TABLE %I.movimientos_inventario ADD COLUMN IF NOT EXISTS anulado_motivo text', sch);

      -- FK opcional depósito → inventario_ubicaciones (si la tabla existe)
      IF to_regclass(format('%I.inventario_ubicaciones', sch)) IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'movimientos_inventario_deposito_id_fkey'
             AND connamespace = sch::regnamespace
         ) THEN
        EXECUTE format(
          'ALTER TABLE %I.movimientos_inventario
             ADD CONSTRAINT movimientos_inventario_deposito_id_fkey
             FOREIGN KEY (deposito_id) REFERENCES %I.inventario_ubicaciones(id) ON DELETE SET NULL',
          sch, sch);
      END IF;

      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS idx_mov_inv_documento ON %I.movimientos_inventario (empresa_id, documento_tipo, documento_id)',
        sch);
      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS idx_mov_inv_producto_fecha ON %I.movimientos_inventario (empresa_id, producto_id, fecha)',
        sch);

      -- ── 2) Ampliar CHECK de origen (conservando valores previos) ───────────
      EXECUTE format(
        'ALTER TABLE %I.movimientos_inventario DROP CONSTRAINT IF EXISTS movimientos_inventario_origen_check',
        sch);
      EXECUTE format(
        'ALTER TABLE %I.movimientos_inventario ADD CONSTRAINT movimientos_inventario_origen_check
           CHECK (origen = ANY (ARRAY[
             ''compra''::text, ''venta''::text, ''ajuste_manual''::text,
             ''inventario_inicial''::text, ''produccion''::text, ''devolucion_venta''::text,
             ''recepcion''::text, ''remision''::text, ''nota_salida''::text,
             ''ajuste''::text, ''transferencia''::text, ''anulacion''::text
           ]))',
        sch);
    END IF;

    -- ── 3) Correlativos genéricos server-side ────────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.documento_correlativos (
        id            uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id    uuid NOT NULL,
        tipo          text NOT NULL,
        prefijo       text NOT NULL DEFAULT '',
        ultimo_numero bigint NOT NULL DEFAULT 0,
        created_at    timestamptz NOT NULL DEFAULT now(),
        updated_at    timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT uq_documento_correlativos_empresa_tipo UNIQUE (empresa_id, tipo)
      )
    $ddl$, sch);

    -- ── 4) Config / feature flags per-empresa ────────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.empresa_config (
        empresa_id                     uuid PRIMARY KEY,
        stock_salida_por_remision      boolean NOT NULL DEFAULT false,
        permitir_stock_negativo        boolean NOT NULL DEFAULT false,
        permitir_excedente_recepcion   boolean NOT NULL DEFAULT false,
        extra                          jsonb   NOT NULL DEFAULT '{}'::jsonb,
        created_at                     timestamptz NOT NULL DEFAULT now(),
        updated_at                     timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);

    -- ── 5) Bitácora de auditoría genérica ────────────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.auditoria_eventos (
        id             uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id     uuid NOT NULL,
        entidad        text NOT NULL,
        entidad_id     uuid,
        accion         text NOT NULL,
        origen         text,
        usuario_id     uuid,
        usuario_email  text,
        usuario_nombre text,
        detalle        jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at     timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_auditoria_eventos_entidad ON %I.auditoria_eventos (empresa_id, entidad, entidad_id, created_at DESC)',
      sch);

    -- ── RLS + policies coherentes con el resto del ERP ───────────────────────
    -- FK empresa_id y política puede_acceder_empresa(empresa_id) sólo si la
    -- función existe en este schema (mismo criterio que tablas de negocio).
    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.documento_correlativos ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('ALTER TABLE %I.empresa_config ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('ALTER TABLE %I.auditoria_eventos ENABLE ROW LEVEL SECURITY', sch);

      EXECUTE format('DROP POLICY IF EXISTS documento_correlativos_all ON %I.documento_correlativos', sch);
      EXECUTE format(
        'CREATE POLICY documento_correlativos_all ON %I.documento_correlativos
           USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))',
        sch, sch, sch);

      EXECUTE format('DROP POLICY IF EXISTS empresa_config_all ON %I.empresa_config', sch);
      EXECUTE format(
        'CREATE POLICY empresa_config_all ON %I.empresa_config
           USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))',
        sch, sch, sch);

      EXECUTE format('DROP POLICY IF EXISTS auditoria_eventos_all ON %I.auditoria_eventos', sch);
      EXECUTE format(
        'CREATE POLICY auditoria_eventos_all ON %I.auditoria_eventos
           USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))',
        sch, sch, sch);
    END IF;

    RAISE NOTICE 'Núcleo Fase 0 aplicado en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
