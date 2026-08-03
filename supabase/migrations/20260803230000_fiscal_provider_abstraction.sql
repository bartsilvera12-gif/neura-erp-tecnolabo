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
