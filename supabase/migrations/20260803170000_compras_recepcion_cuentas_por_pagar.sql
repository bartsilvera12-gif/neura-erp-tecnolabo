-- =============================================================================
-- FASE 2 — Compras · Recepción de mercadería · Cuentas por pagar
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
-- Reutiliza `compras` (modelo plano) y el ledger `movimientos_inventario` (F0).
-- NO implementa un flujo complejo de orden de compra (ese motor ya existe aparte).
--
--   1. compras += cantidad_recibida (control comprado vs recibido por línea).
--   2. recepciones + recepcion_items (nota de recepción; estados borrador/confirmada/anulada).
--   3. cuentas_por_pagar + pagos_proveedor (obligación financiera desde compras).
--   4. empresa_config += compra_ingresa_por_recepcion (flag: la compra no sube stock
--      hasta confirmar la recepción). Default false = comportamiento legado intacto.
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
    WHERE c.relname = 'compras'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    -- ── 1) compras: cantidad recibida acumulada por línea ────────────────────
    EXECUTE format('ALTER TABLE %I.compras ADD COLUMN IF NOT EXISTS cantidad_recibida numeric NOT NULL DEFAULT 0', sch);

    -- ── 4) flag per-empresa ──────────────────────────────────────────────────
    IF to_regclass(format('%I.empresa_config', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.empresa_config ADD COLUMN IF NOT EXISTS compra_ingresa_por_recepcion boolean NOT NULL DEFAULT false', sch);
    END IF;

    -- ── 2) Nota de recepción (cabecera + detalle) ────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.recepciones (
        id                     uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id             uuid NOT NULL,
        numero                 text NOT NULL,
        compra_numero_control  text NOT NULL,
        proveedor_id           uuid,
        proveedor_nombre       text,
        deposito_id            uuid,
        sucursal_id            uuid,
        fecha                  timestamptz NOT NULL DEFAULT now(),
        estado                 text NOT NULL DEFAULT 'borrador',
        observacion            text,
        documento_url          text,
        documento_storage_path text,
        documento_nombre       text,
        documento_mime_type    text,
        firma_entrega          text,
        firma_recepcion        text,
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
        CONSTRAINT recepciones_estado_check CHECK (estado = ANY (ARRAY['borrador','confirmada','anulada']))
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_recepciones_compra ON %I.recepciones (empresa_id, compra_numero_control)', sch);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_recepciones_numero ON %I.recepciones (empresa_id, numero)', sch);

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.recepcion_items (
        id                 uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id         uuid NOT NULL,
        recepcion_id       uuid NOT NULL,
        compra_id          uuid,
        producto_id        uuid NOT NULL,
        producto_nombre    text NOT NULL,
        sku                text,
        cantidad_recibida  numeric NOT NULL DEFAULT 0,
        cantidad_rechazada numeric NOT NULL DEFAULT 0,
        costo_unitario     numeric NOT NULL DEFAULT 0,
        observacion        text,
        created_at         timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_recepcion_items_recepcion ON %I.recepcion_items (recepcion_id)', sch);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'recepcion_items_recepcion_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format(
        'ALTER TABLE %I.recepcion_items ADD CONSTRAINT recepcion_items_recepcion_fk
           FOREIGN KEY (recepcion_id) REFERENCES %I.recepciones(id) ON DELETE CASCADE',
        sch, sch);
    END IF;

    -- ── 3) Cuentas por pagar + pagos a proveedor ─────────────────────────────
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.cuentas_por_pagar (
        id                    uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id            uuid NOT NULL,
        proveedor_id          uuid,
        proveedor_nombre      text,
        compra_numero_control text,
        moneda                text NOT NULL DEFAULT 'PYG',
        tipo_cambio           numeric NOT NULL DEFAULT 1,
        total                 numeric NOT NULL DEFAULT 0,
        saldo                 numeric NOT NULL DEFAULT 0,
        fecha_emision         date NOT NULL DEFAULT CURRENT_DATE,
        fecha_vencimiento     date,
        estado                text NOT NULL DEFAULT 'pendiente',
        observacion           text,
        created_at            timestamptz NOT NULL DEFAULT now(),
        updated_at            timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT cxp_estado_check CHECK (estado = ANY (ARRAY['pendiente','parcial','pagado','anulado']))
      )
    $ddl$, sch);
    -- Idempotencia: 1 CxP por compra (numero_control).
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_cxp_compra ON %I.cuentas_por_pagar (empresa_id, compra_numero_control) WHERE compra_numero_control IS NOT NULL', sch);

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.pagos_proveedor (
        id                     uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id             uuid NOT NULL,
        cuenta_por_pagar_id    uuid NOT NULL,
        proveedor_id           uuid,
        fecha_pago             date NOT NULL DEFAULT CURRENT_DATE,
        monto                  numeric NOT NULL,
        metodo_pago            text NOT NULL DEFAULT 'efectivo',
        referencia             text,
        comprobante_url        text,
        comprobante_storage_path text,
        comprobante_nombre     text,
        comprobante_mime_type  text,
        usuario_id             uuid,
        usuario_nombre         text,
        observacion            text,
        anulado_at             timestamptz,
        anulado_por            uuid,
        anulado_motivo         text,
        created_at             timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_pagos_proveedor_cxp ON %I.pagos_proveedor (cuenta_por_pagar_id)', sch);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pagos_proveedor_cxp_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format(
        'ALTER TABLE %I.pagos_proveedor ADD CONSTRAINT pagos_proveedor_cxp_fk
           FOREIGN KEY (cuenta_por_pagar_id) REFERENCES %I.cuentas_por_pagar(id) ON DELETE CASCADE',
        sch, sch);
    END IF;

    -- ── RLS coherente con el resto del ERP ───────────────────────────────────
    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.recepciones ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS recepciones_all ON %I.recepciones', sch);
      EXECUTE format('CREATE POLICY recepciones_all ON %I.recepciones USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);

      EXECUTE format('ALTER TABLE %I.recepcion_items ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS recepcion_items_all ON %I.recepcion_items', sch);
      EXECUTE format('CREATE POLICY recepcion_items_all ON %I.recepcion_items USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);

      EXECUTE format('ALTER TABLE %I.cuentas_por_pagar ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS cuentas_por_pagar_all ON %I.cuentas_por_pagar', sch);
      EXECUTE format('CREATE POLICY cuentas_por_pagar_all ON %I.cuentas_por_pagar USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);

      EXECUTE format('ALTER TABLE %I.pagos_proveedor ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS pagos_proveedor_all ON %I.pagos_proveedor', sch);
      EXECUTE format('CREATE POLICY pagos_proveedor_all ON %I.pagos_proveedor USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 2 (compras/recepción/CxP) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;
