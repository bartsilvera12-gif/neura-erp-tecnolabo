-- =============================================================================
-- INSTALADOR de las 9 fases del alcance, ACOTADO al schema 'tecnolabo'.
-- Compatible con PgBouncer (6432): usa SET LOCAL dentro de cada transacción.
-- Requiere el baseline previo: 20260803120000/123000/140000_*tecnolabo*.sql
-- Idempotente. NO toca otros schemas (p.ej. abhuevos).
-- =============================================================================

-- ===================== 20260803150000_nucleo_inventario_correlativo_config_auditoria =====================
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
SET LOCAL neura.solo_schema = 'tecnolabo';
SET LOCAL check_function_bodies = off;

DO $mig$
DECLARE
  sch text;
  origen_vals text;
BEGIN
  FOR sch IN
    SELECT n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'empresas'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
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

      -- ── 2) Ampliar CHECK de origen: UNIÓN de los valores ya presentes en los
      --        datos + los nuevos orígenes operativos. Data-safe: nunca viola
      --        filas existentes (aunque el schema tenga orígenes propios).
      EXECUTE format(
        'SELECT string_agg(DISTINCT quote_literal(o), '','') FROM (
           SELECT origen AS o FROM %I.movimientos_inventario WHERE origen IS NOT NULL
           UNION
           SELECT unnest($1::text[]) AS o
         ) s',
        sch)
      INTO origen_vals
      USING ARRAY[
        'compra','venta','ajuste_manual','inventario_inicial','produccion','devolucion_venta',
        'recepcion','remision','nota_salida','ajuste','transferencia','anulacion'
      ];

      IF origen_vals IS NOT NULL THEN
        EXECUTE format('ALTER TABLE %I.movimientos_inventario DROP CONSTRAINT IF EXISTS movimientos_inventario_origen_check', sch);
        EXECUTE format(
          'ALTER TABLE %I.movimientos_inventario ADD CONSTRAINT movimientos_inventario_origen_check CHECK (origen = ANY (ARRAY[%s]::text[]))',
          sch, origen_vals);
      END IF;
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

-- ===================== 20260803160000_presupuestos_ampliacion_conversion =====================
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
SET LOCAL neura.solo_schema = 'tecnolabo';
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
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
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

-- ===================== 20260803170000_compras_recepcion_cuentas_por_pagar =====================
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
SET LOCAL neura.solo_schema = 'tecnolabo';
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

-- ===================== 20260803180000_inventario_vistas_usuario =====================
-- =============================================================================
-- FASE 3 — Inventario: vistas configurables por usuario
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
-- `usuario_vistas` guarda, por usuario y por pantalla (clave), la configuración
-- de columnas visibles/orden, filtros guardados y ordenamiento. Genérico:
-- reutilizable por inventario, movimientos y reportes tabulares (Fase 10).
-- =============================================================================

BEGIN;
SET LOCAL neura.solo_schema = 'tecnolabo';
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

-- ===================== 20260803190000_notas_salida =====================
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
SET LOCAL neura.solo_schema = 'tecnolabo';
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

-- ===================== 20260803200000_notas_remision_entregas =====================
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
SET LOCAL neura.solo_schema = 'tecnolabo';
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
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
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

-- ===================== 20260803210000_cobranzas_tramos_promesas_gestiones =====================
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
SET LOCAL neura.solo_schema = 'tecnolabo';
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
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
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

-- ===================== 20260803220000_roles_permisos_por_accion =====================
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
SET LOCAL neura.solo_schema = 'tecnolabo';
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

-- ===================== 20260803230000_fiscal_provider_abstraction =====================
-- =============================================================================
-- FASE 11 — Abstracción de proveedores fiscales por país
--
-- Aditivo e idempotente. Resuelve el schema dinámicamente (sin hardcode).
-- NO toca SIFEN (tablas empresa_sifen_config / factura_electronica / eventos)
-- ni su máquina de estados. Agrega una dimensión de PROVEEDOR fiscal:
--   - empresa_config += proveedor_fiscal ('none'|'sifen_py'|'sin_bo') + pais + fiscal_habilitado
--   - empresa_sin_config (Bolivia SIN): credenciales/token/certificado CIFRADOS server-side,
--     modalidad, CUIS/CUFD, ambiente. NUNCA se exponen al navegador.
--   - documento_fiscal (documento fiscal genérico neutral por proveedor) + eventos.
--
-- Bolivia queda detrás de feature flag (fiscal_habilitado=false por defecto).
-- No se afirma integración habilitada hasta pruebas y autorización del SIN.
-- =============================================================================

BEGIN;
SET LOCAL neura.solo_schema = 'tecnolabo';
SET LOCAL check_function_bodies = off;

DO $mig$
DECLARE
  sch text;
BEGIN
  FOR sch IN
    SELECT n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'empresa_config'
      AND c.relkind = 'r'
      AND n.nspname NOT IN ('public', 'pg_catalog', 'information_schema')
      AND (nullif(current_setting('neura.solo_schema', true), '') IS NULL
           OR n.nspname = current_setting('neura.solo_schema', true))
    ORDER BY 1
  LOOP
    EXECUTE format($q$ALTER TABLE %I.empresa_config ADD COLUMN IF NOT EXISTS proveedor_fiscal text NOT NULL DEFAULT 'none'$q$, sch);
    EXECUTE format($q$ALTER TABLE %I.empresa_config ADD COLUMN IF NOT EXISTS pais_fiscal text$q$, sch);
    EXECUTE format($q$ALTER TABLE %I.empresa_config ADD COLUMN IF NOT EXISTS fiscal_habilitado boolean NOT NULL DEFAULT false$q$, sch);
    -- Restringe valores conocidos (extensible a futuros proveedores).
    EXECUTE format('ALTER TABLE %I.empresa_config DROP CONSTRAINT IF EXISTS empresa_config_proveedor_fiscal_check', sch);
    EXECUTE format($q$ALTER TABLE %I.empresa_config ADD CONSTRAINT empresa_config_proveedor_fiscal_check
      CHECK (proveedor_fiscal = ANY (ARRAY['none','sifen_py','sin_bo']))$q$, sch);

    -- Configuración Bolivia (SIN). Secretos cifrados; jamás en texto plano ni al cliente.
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.empresa_sin_config (
        empresa_id             uuid PRIMARY KEY,
        ambiente               text NOT NULL DEFAULT 'test',
        modalidad              text,
        nit                    text,
        razon_social           text,
        sucursal_codigo        integer,
        punto_venta_codigo     integer,
        cuis                   text,
        cufd                   text,
        cufd_vigencia          timestamptz,
        token_encrypted        text,
        certificado_path       text,
        certificado_password_encrypted text,
        datos_extra            jsonb NOT NULL DEFAULT '{}'::jsonb,
        activo                 boolean NOT NULL DEFAULT false,
        created_at             timestamptz NOT NULL DEFAULT now(),
        updated_at             timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT empresa_sin_config_ambiente_check CHECK (ambiente = ANY (ARRAY['test','produccion']))
      )
    $ddl$, sch);

    -- Documento fiscal genérico (neutral por proveedor). SIFEN sigue en su propia tabla;
    -- esta es para sin_bo y futuros proveedores. Máquina de estados amplia.
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.documento_fiscal (
        id                   uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id           uuid NOT NULL,
        proveedor            text NOT NULL,
        factura_id           uuid,
        venta_id             uuid,
        estado               text NOT NULL DEFAULT 'borrador',
        numero_autorizacion  text,
        codigo_control        text,
        cuf                   text,
        xml_path             text,
        pdf_path             text,
        qr_data              text,
        respuesta            jsonb,
        error_mensaje        text,
        created_by           uuid,
        created_at           timestamptz NOT NULL DEFAULT now(),
        updated_at           timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT documento_fiscal_estado_check CHECK (estado = ANY (ARRAY[
          'borrador','generado','firmado','enviado','validado','rechazado','anulado','contingencia','error'
        ]))
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_documento_fiscal_factura ON %I.documento_fiscal (empresa_id, factura_id)', sch);

    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.documento_fiscal_evento (
        id                   uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
        empresa_id           uuid NOT NULL,
        documento_fiscal_id  uuid NOT NULL,
        tipo                 text NOT NULL,
        detalle              jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at           timestamptz NOT NULL DEFAULT now()
      )
    $ddl$, sch);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_documento_fiscal_evento_doc ON %I.documento_fiscal_evento (documento_fiscal_id, created_at)', sch);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documento_fiscal_evento_fk' AND connamespace = sch::regnamespace) THEN
      EXECUTE format('ALTER TABLE %I.documento_fiscal_evento ADD CONSTRAINT documento_fiscal_evento_fk FOREIGN KEY (documento_fiscal_id) REFERENCES %I.documento_fiscal(id) ON DELETE CASCADE', sch, sch);
    END IF;

    IF to_regprocedure(format('%I.puede_acceder_empresa(uuid)', sch)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I.empresa_sin_config ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS empresa_sin_config_all ON %I.empresa_sin_config', sch);
      EXECUTE format('CREATE POLICY empresa_sin_config_all ON %I.empresa_sin_config USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.documento_fiscal ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS documento_fiscal_all ON %I.documento_fiscal', sch);
      EXECUTE format('CREATE POLICY documento_fiscal_all ON %I.documento_fiscal USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
      EXECUTE format('ALTER TABLE %I.documento_fiscal_evento ENABLE ROW LEVEL SECURITY', sch);
      EXECUTE format('DROP POLICY IF EXISTS documento_fiscal_evento_all ON %I.documento_fiscal_evento', sch);
      EXECUTE format('CREATE POLICY documento_fiscal_evento_all ON %I.documento_fiscal_evento USING (%I.puede_acceder_empresa(empresa_id)) WITH CHECK (%I.puede_acceder_empresa(empresa_id))', sch, sch, sch);
    END IF;

    RAISE NOTICE 'Fase 11 (abstracción fiscal) aplicada en schema %', sch;
  END LOOP;
END
$mig$;

COMMIT;

