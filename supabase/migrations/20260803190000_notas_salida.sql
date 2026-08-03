-- =============================================================================
-- FASE 4 — Nota de salida
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
-- Salida de inventario no necesariamente ligada a una factura. Reutiliza el
-- ledger `movimientos_inventario` (F0): el stock se descuenta SOLO al confirmar.
--   notas_salida        (cabecera; estados borrador/confirmada/anulada; motivo, depósito)
--   notas_salida_items  (detalle: producto, cantidad, observación)
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
    ORDER BY 1
  LOOP
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.notas_salida (
        id                     uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id             uuid NOT NULL,
        numero                 text NOT NULL,
        motivo                 text NOT NULL DEFAULT 'otro',
        deposito_id            uuid,
        sucursal_id            uuid,
        fecha                  timestamptz NOT NULL DEFAULT now(),
        estado                 text NOT NULL DEFAULT 'borrador',
        observacion            text,
        usuario_creador_id     uuid,
        usuario_creador_nombre text,
        usuario_confirmador_id uuid,
        usuario_confirmador_nombre text,
        confirmada_at          timestamptz,
        anulada_at             timestamptz,
        anulada_por            uuid,
        anulada_motivo         text,
        created_at             timestamptz NOT NULL DEFAULT now(),
        updated_at             timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT notas_salida_estado_check CHECK (estado = ANY (ARRAY['borrador','confirmada','anulada']))
      )
    $ddl$, sch);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_notas_salida_numero ON %I.notas_salida (empresa_id, numero)', sch);

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.notas_salida_items (
        id              uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id      uuid NOT NULL,
        nota_salida_id  uuid NOT NULL,
        producto_id     uuid NOT NULL,
        producto_nombre text NOT NULL,
        sku             text,
        cantidad        numeric NOT NULL DEFAULT 0,
        costo_unitario  numeric NOT NULL DEFAULT 0,
        observacion     text,
        created_at      timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_notas_salida_items_ns ON %I.notas_salida_items (nota_salida_id)', sch);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notas_salida_items_ns_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format(
        'ALTER TABLE %I.notas_salida_items ADD CONSTRAINT notas_salida_items_ns_fk
           FOREIGN KEY (nota_salida_id) REFERENCES %I.notas_salida(id) ON DELETE CASCADE',
        sch, sch);
    END IF;

    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.notas_salida ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS notas_salida_all ON %I.notas_salida', sch);
      EXECUTE format('CREATE POLICY notas_salida_all ON %I.notas_salida USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.notas_salida_items ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS notas_salida_items_all ON %I.notas_salida_items', sch);
      EXECUTE format('CREATE POLICY notas_salida_items_all ON %I.notas_salida_items USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 4 (notas_salida) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
