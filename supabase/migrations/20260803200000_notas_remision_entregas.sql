-- =============================================================================
-- FASE 5+6 — Facturación con entregas parciales · Notas de remisión
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
-- Separa emitir factura de entregar mercadería: el stock sale al CONFIRMAR cada
-- nota de remisión (helper F0), no al crear la factura. Reutiliza `facturas` y
-- `factura_items` (F1).
--   facturas       += estado_entrega
--   factura_items  += cantidad_entregada
--   notas_remision + notas_remision_items (estados borrador/confirmada/anulada)
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
    WHERE c.relname = 'facturas'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
    ORDER BY 1
  LOOP
    EXECUTE format($q$ALTER TABLE %I.facturas ADD COLUMN IF NOT EXISTS estado_entrega text NOT NULL DEFAULT 'pendiente'$q$, sch);
    EXECUTE format('ALTER TABLE %I.factura_items ADD COLUMN IF NOT EXISTS cantidad_entregada numeric NOT NULL DEFAULT 0', sch);

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.notas_remision (
        id                     uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id             uuid NOT NULL,
        numero                 text NOT NULL,
        factura_id             uuid NOT NULL,
        cliente_id             uuid,
        cliente_nombre         text,
        deposito_id            uuid,
        sucursal_id            uuid,
        fecha                  timestamptz NOT NULL DEFAULT now(),
        estado                 text NOT NULL DEFAULT 'borrador',
        observacion            text,
        firma_entrega          text,
        firma_recepcion        text,
        documento_url          text,
        documento_storage_path text,
        documento_nombre       text,
        documento_mime_type    text,
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
        CONSTRAINT notas_remision_estado_check CHECK (estado = ANY (ARRAY['borrador','confirmada','anulada']))
      )
    $ddl$, sch);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_notas_remision_numero ON %I.notas_remision (empresa_id, numero)', sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_notas_remision_factura ON %I.notas_remision (empresa_id, factura_id)', sch);

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.notas_remision_items (
        id                uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id        uuid NOT NULL,
        remision_id       uuid NOT NULL,
        factura_item_id   uuid,
        producto_id       uuid NOT NULL,
        producto_nombre   text NOT NULL,
        sku               text,
        cantidad          numeric NOT NULL DEFAULT 0,
        costo_unitario    numeric NOT NULL DEFAULT 0,
        observacion       text,
        created_at        timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_notas_remision_items_rem ON %I.notas_remision_items (remision_id)', sch);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notas_remision_items_rem_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format(
        'ALTER TABLE %I.notas_remision_items ADD CONSTRAINT notas_remision_items_rem_fk
           FOREIGN KEY (remision_id) REFERENCES %I.notas_remision(id) ON DELETE CASCADE',
        sch, sch);
    END IF;

    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.notas_remision ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS notas_remision_all ON %I.notas_remision', sch);
      EXECUTE format('CREATE POLICY notas_remision_all ON %I.notas_remision USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.notas_remision_items ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS notas_remision_items_all ON %I.notas_remision_items', sch);
      EXECUTE format('CREATE POLICY notas_remision_items_all ON %I.notas_remision_items USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 5+6 (notas_remision) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
