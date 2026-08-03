-- =============================================================================
-- Provision del schema `tecnolabo` (instancia monocliente Tecnolabo).
--
-- Estructura derivada del baseline aprobado. NO contiene datos operativos:
-- ni clientes, productos, proveedores, ventas, compras, pagos, cajas,
-- comprobantes, facturas, conversaciones, documentos ni usuarios.
--
-- Toda referencia a schemas de otros clientes fue reapuntada a `tecnolabo`.
-- En el schema fuente varias policies llamaban a funciones de OTRO schema y
-- varias funciones tenian search_path hacia otro cliente; aca queda corregido.
--
-- Idempotente y reproducible: se puede re-ejecutar sin efectos adversos.
-- =============================================================================

BEGIN;

-- Las funciones se emiten en orden alfabetico y algunas se llaman entre si
-- (p. ej. empresa_id_actual -> jwt_email_normalized). Igual que pg_dump,
-- se difiere la validacion de cuerpos hasta el final de la transaccion.
SET LOCAL check_function_bodies = off;

CREATE SCHEMA IF NOT EXISTS "tecnolabo";
GRANT USAGE ON SCHEMA "tecnolabo" TO anon, authenticated, service_role;

-- ── TABLAS ───────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "tecnolabo"."caja_movimientos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "caja_id" uuid NOT NULL,
  "tipo" text NOT NULL,
  "concepto" text NOT NULL,
  "monto" numeric NOT NULL,
  "medio_pago" text DEFAULT 'efectivo'::text NOT NULL,
  "usuario_id" uuid,
  "observacion" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "anulado_at" timestamp with time zone,
  "anulado_por_id" uuid,
  "anulado_motivo" text,
  "usuario_email" text,
  "anulado_por" uuid,
  "venta_id" uuid,
  "devolucion_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."cajas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "estado" text DEFAULT 'abierta'::text NOT NULL,
  "abierta_por" uuid,
  "cerrada_por" uuid,
  "fecha_apertura" timestamp with time zone DEFAULT now() NOT NULL,
  "fecha_cierre" timestamp with time zone,
  "monto_apertura" numeric DEFAULT 0 NOT NULL,
  "monto_cierre_contado" numeric,
  "monto_esperado_efectivo" numeric,
  "diferencia" numeric,
  "observacion_apertura" text,
  "observacion_cierre" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "numero_caja" integer DEFAULT 1 NOT NULL,
  "arqueo_apertura_json" jsonb,
  "arqueo_cierre_json" jsonb
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."categorias_productos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "codigo" text,
  "descripcion" text,
  "parent_id" uuid,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "imagen_url" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_agents" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "usuario_id" uuid NOT NULL,
  "queue_id" uuid NOT NULL,
  "is_online" boolean DEFAULT false NOT NULL,
  "max_conversations" integer DEFAULT 5 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "receives_new_chats" boolean DEFAULT true NOT NULL,
  "priority_in_queue" integer DEFAULT 0 NOT NULL,
  "operational_status_changed_at" timestamp with time zone DEFAULT now() NOT NULL,
  "last_heartbeat_at" timestamp with time zone,
  "operational_status" text DEFAULT 'ready'::text NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_campaign_events" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "campaign_id" uuid NOT NULL,
  "recipient_id" uuid,
  "event_type" text NOT NULL,
  "event_payload_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_campaign_jobs" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "campaign_id" uuid NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "batch_size" integer DEFAULT 25 NOT NULL,
  "locked_at" timestamp with time zone,
  "locked_by" text,
  "attempts" integer DEFAULT 0 NOT NULL,
  "last_error" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_campaign_recipients" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "campaign_id" uuid NOT NULL,
  "row_number" integer NOT NULL,
  "phone_raw" text,
  "phone_e164" text NOT NULL,
  "contact_id" uuid,
  "conversation_id" uuid,
  "row_payload_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "mapped_variables_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "validation_error" text,
  "provider_message_id" text,
  "provider_payload_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "last_status_raw_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "error_code" text,
  "error_message" text,
  "queued_at" timestamp with time zone,
  "sent_at" timestamp with time zone,
  "failed_at" timestamp with time zone,
  "first_reply_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_campaign_templates" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "channel_id" uuid NOT NULL,
  "provider" text NOT NULL,
  "provider_template_id" text,
  "name" text NOT NULL,
  "language" text DEFAULT 'es'::text NOT NULL,
  "category" text,
  "status" text DEFAULT 'unknown'::text NOT NULL,
  "components_json" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "variable_schema_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "provider_payload_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "last_synced_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_campaigns" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "name" text NOT NULL,
  "channel_id" uuid NOT NULL,
  "queue_id" uuid,
  "provider" text NOT NULL,
  "template_id" uuid,
  "template_name" text NOT NULL,
  "template_language" text DEFAULT 'es'::text NOT NULL,
  "template_category" text,
  "template_components_json" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "variable_mapping_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "import_original_filename" text,
  "import_storage_bucket" text,
  "import_storage_path" text,
  "status" text DEFAULT 'draft'::text NOT NULL,
  "total_count" integer DEFAULT 0 NOT NULL,
  "valid_count" integer DEFAULT 0 NOT NULL,
  "invalid_count" integer DEFAULT 0 NOT NULL,
  "pending_count" integer DEFAULT 0 NOT NULL,
  "queued_count" integer DEFAULT 0 NOT NULL,
  "sent_count" integer DEFAULT 0 NOT NULL,
  "failed_count" integer DEFAULT 0 NOT NULL,
  "replied_count" integer DEFAULT 0 NOT NULL,
  "send_config_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_by" uuid,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_channel_quick_replies" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "channel_id" uuid NOT NULL,
  "title" text NOT NULL,
  "body" text NOT NULL,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_channels" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "type" text DEFAULT 'whatsapp'::text NOT NULL,
  "meta_phone_number_id" text,
  "config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "nombre" text,
  "provider" text DEFAULT 'meta'::text NOT NULL,
  "provider_channel_id" text,
  "activo" boolean DEFAULT true NOT NULL,
  "whatsapp_access_token" text,
  "connection_mode" text,
  "config_status" text DEFAULT 'incomplete'::text NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_comprobante_validaciones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "conversation_id" uuid NOT NULL,
  "flow_session_id" uuid NOT NULL,
  "channel_id" uuid,
  "flow_code" text DEFAULT ''::text NOT NULL,
  "comprobante_url" text,
  "comprobante_media_id" text,
  "comprobante_hash" text NOT NULL,
  "estado_validacion" text DEFAULT 'pendiente'::text NOT NULL,
  "motivo_validacion" text,
  "ocr_text_raw" text,
  "ocr_monto" text,
  "ocr_referencia" text,
  "ocr_fecha" text,
  "ocr_hora" text,
  "ocr_banco" text,
  "ocr_fingerprint" text,
  "sorteo_entrada_id" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "monto_validacion_esperado_gs" bigint,
  "monto_validacion_ocr_gs" bigint,
  "monto_validacion_diferencia_gs" bigint,
  "monto_validacion_status" text,
  "bank_val_titular_esperado" text,
  "bank_val_cuenta_esperada" text,
  "bank_val_alias_esperado" text,
  "bank_val_titular_ocr" text,
  "bank_val_cuenta_ocr" text,
  "bank_val_alias_ocr" text,
  "bank_val_coincidencias" integer,
  "bank_val_min_requeridas" integer,
  "bank_val_status" text,
  "manual_approval_usuario_id" uuid,
  "manual_approval_at" timestamp with time zone,
  "manual_approval_source" text,
  "manual_approval_note" text,
  "previous_estado_validacion" text,
  "previous_motivo_validacion" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_contacts" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "phone_number" text NOT NULL,
  "name" text,
  "cliente_id" uuid,
  "crm_prospecto_id" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "phone_normalized" text,
  "last_routed_chat_agent_id" uuid,
  "last_routed_at" timestamp with time zone,
  "last_routed_channel_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_conversation_closures" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "conversation_id" uuid NOT NULL,
  "queue_id" uuid,
  "closure_state_id" uuid,
  "closure_substate_id" uuid,
  "closure_state_label" text NOT NULL,
  "closure_substate_label" text NOT NULL,
  "comment" text NOT NULL,
  "closed_at" timestamp with time zone DEFAULT now() NOT NULL,
  "closed_by_usuario_id" uuid NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_conversations" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "channel_id" uuid NOT NULL,
  "contact_id" uuid NOT NULL,
  "status" text DEFAULT 'open'::text NOT NULL,
  "last_message_at" timestamp with time zone,
  "last_message_preview" text,
  "unread_count" integer DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "flow_code" text,
  "flow_current_node" text,
  "flow_status" text DEFAULT 'bot'::text NOT NULL,
  "human_taken_over" boolean DEFAULT false NOT NULL,
  "active_flow_session_id" uuid,
  "first_revendedor_id" uuid,
  "first_referral_captured_at" timestamp with time zone,
  "assigned_agent_id" uuid,
  "queue_id" uuid,
  "priority" text DEFAULT 'medium'::text NOT NULL,
  "closed_at" timestamp with time zone,
  "closed_by_usuario_id" uuid,
  "initial_assignment_at" timestamp with time zone,
  "first_human_response_at" timestamp with time zone,
  "initial_reassign_count" integer DEFAULT 0 NOT NULL,
  "assignment_wait_code" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_empresa_operator_roles" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "usuario_id" uuid NOT NULL,
  "role" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_data" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "conversation_id" uuid NOT NULL,
  "flow_code" text NOT NULL,
  "field_name" text NOT NULL,
  "field_value" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "flow_session_id" uuid NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_events" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "conversation_id" uuid NOT NULL,
  "flow_code" text,
  "node_code" text,
  "event_type" text NOT NULL,
  "selected_option_id" uuid,
  "meta_button_id" text,
  "payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "flow_session_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_node_blocks" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "node_id" uuid NOT NULL,
  "block_type" text NOT NULL,
  "content_text" text,
  "media_url" text,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_nodes" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "flow_code" text NOT NULL,
  "node_code" text NOT NULL,
  "message_text" text,
  "node_type" text NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "save_as_field" text,
  "next_node_code" text,
  "crm_action_type" text,
  "crm_action_config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "sort_order" integer NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_options" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "node_id" uuid NOT NULL,
  "label" text NOT NULL,
  "option_value" text NOT NULL,
  "meta_button_id" text NOT NULL,
  "next_node_code" text,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "option_payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "group_title" text,
  "group_order" integer DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_recontact_rules" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "flow_code" text NOT NULL,
  "nombre" text NOT NULL,
  "descripcion" text,
  "activo" boolean DEFAULT false NOT NULL,
  "prioridad" integer DEFAULT 100 NOT NULL,
  "included_node_codes" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "excluded_node_codes" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "idle_after_seconds" integer DEFAULT 3600 NOT NULL,
  "max_attempts" integer DEFAULT 1 NOT NULL,
  "cooldown_seconds" integer DEFAULT 86400 NOT NULL,
  "schedule_config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "guard_config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "message_config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_recontact_runs" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "rule_id" uuid NOT NULL,
  "flow_code" text NOT NULL,
  "conversation_id" uuid,
  "flow_session_id" uuid,
  "decision" text NOT NULL,
  "skip_reason" text,
  "attempt_no" integer,
  "correlation_id" text,
  "payload_snapshot" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flow_sessions" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "conversation_id" uuid NOT NULL,
  "flow_code" text NOT NULL,
  "status" text DEFAULT 'active'::text NOT NULL,
  "started_at" timestamp with time zone DEFAULT now() NOT NULL,
  "ended_at" timestamp with time zone,
  "end_reason" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "revendedor_id" uuid,
  "codigo_referido_snapshot" text,
  "referral_source" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_flows" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "flow_code" text NOT NULL,
  "label" text,
  "channel" text DEFAULT 'whatsapp'::text NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "sorteo_id" uuid,
  "sorteo_datos_incompletos_message" text,
  "flow_config" jsonb DEFAULT '{}'::jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_messages" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "conversation_id" uuid NOT NULL,
  "wa_message_id" text,
  "from_me" boolean DEFAULT false NOT NULL,
  "message_type" text DEFAULT 'text'::text NOT NULL,
  "content" text,
  "raw_payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "sender_type" text DEFAULT 'system'::text,
  "sent_by_user_id" uuid,
  "sent_by_user_name" text,
  "automation_source" text,
  "whatsapp_delivery_status" text,
  "whatsapp_delivered_at" timestamp with time zone,
  "whatsapp_read_at" timestamp with time zone
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_omnicanal_work_schedules" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "time_start" time without time zone NOT NULL,
  "time_end" time without time zone NOT NULL,
  "days_of_week" smallint[] DEFAULT '{}'::smallint[] NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_queue_channels" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "queue_id" uuid NOT NULL,
  "channel_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_queue_closure_states" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "queue_id" uuid NOT NULL,
  "label" text NOT NULL,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_queue_closure_substates" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "closure_state_id" uuid NOT NULL,
  "label" text NOT NULL,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_queue_supervisors" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "queue_id" uuid NOT NULL,
  "usuario_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_queues" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "channel_type" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "descripcion" text,
  "distribution_strategy" text DEFAULT 'least_load'::text NOT NULL,
  "priority" integer DEFAULT 0 NOT NULL,
  "routing_config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "assignment_state" jsonb DEFAULT '{}'::jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_routing_events" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "conversation_id" uuid NOT NULL,
  "queue_id" uuid,
  "event_type" text NOT NULL,
  "payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_supervisor_agents" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "supervisor_usuario_id" uuid NOT NULL,
  "agent_usuario_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."chat_usuario_omnicanal" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "usuario_id" uuid NOT NULL,
  "omnicanal_agent_enabled" boolean DEFAULT false NOT NULL,
  "work_schedule_id" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."cliente_historial" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "suscripcion_id" uuid,
  "tipo" text NOT NULL,
  "accion" text NOT NULL,
  "plan_anterior_id" uuid,
  "plan_nuevo_id" uuid,
  "plan_anterior_nombre" text,
  "plan_nuevo_nombre" text,
  "modo" text,
  "factura_id" uuid,
  "plan_pendiente_vigente_desde" date,
  "creado_por_auth_user_id" uuid,
  "creado_por_email" text,
  "detalle" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."cliente_obligaciones_tributarias" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_perfil_id" uuid NOT NULL,
  "obligacion_catalogo_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."cliente_perfil_tributario" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "perfil_activo" boolean DEFAULT false NOT NULL,
  "dv" text,
  "razon_social_fiscal" text,
  "clave_tributaria_encrypted" text,
  "honorario_mensual" numeric,
  "honorario_anual" numeric,
  "notas_tributarias" text,
  "obligacion_otro_detalle" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "dia_vencimiento_tributario" smallint
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."cliente_tipos_servicio_catalogo" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "slug" text NOT NULL,
  "nombre" text NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "orden" smallint DEFAULT 0 NOT NULL,
  "es_sistema" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."clientes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid,
  "nombre" text,
  "telefono" text,
  "email" text,
  "direccion" text,
  "created_at" timestamp without time zone DEFAULT now(),
  "tipo_cliente" text DEFAULT 'empresa'::text,
  "empresa" text,
  "ruc" text,
  "documento" text,
  "telefono_secundario" text,
  "email_secundario" text,
  "ciudad" text,
  "pais" text,
  "sitio_web" text,
  "instagram" text,
  "linkedin" text,
  "categoria_cliente" text,
  "industria" text,
  "valor_cliente" numeric,
  "condicion_pago" text,
  "moneda_preferida" text DEFAULT 'GS'::text,
  "vendedor_asignado" text,
  "origen" text DEFAULT 'MANUAL'::text,
  "prospecto_id" integer,
  "estado" text DEFAULT 'activo'::text,
  "notas" jsonb DEFAULT '[]'::jsonb,
  "updated_at" timestamp with time zone DEFAULT now(),
  "nombre_contacto" text,
  "created_by_user_id" uuid,
  "created_by_nombre" text,
  "tipo_servicio_cliente" text,
  "deleted_at" timestamp with time zone,
  "deleted_by_user_id" uuid,
  "deletion_reason" text,
  "baja_operativa_at" timestamp with time zone,
  "baja_operativa_by_user_id" uuid,
  "baja_operativa_motivo" text,
  "baja_operativa_anulo_factura" boolean,
  "baja_operativa_by_nombre" text,
  "vendedor_usuario_id" uuid,
  "sifen_receptor_extranjero" boolean DEFAULT false NOT NULL,
  "sifen_codigo_pais" text,
  "sifen_tipo_doc_receptor" smallint,
  "sifen_receptor_manual" boolean DEFAULT false NOT NULL,
  "sifen_receptor_naturaleza" text,
  "sifen_ti_ope" smallint,
  "sifen_num_id_de" text,
  "sifen_direccion_de" text,
  "sifen_num_casa_de" integer,
  "sifen_descripcion_tipo_doc" text,
  "plan_comercial_id" uuid,
  "usa_nota_remision" boolean DEFAULT false NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."cobros_clientes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "cuenta_por_cobrar_id" uuid NOT NULL,
  "venta_id" uuid,
  "fecha_pago" timestamp with time zone DEFAULT now() NOT NULL,
  "monto" numeric DEFAULT 0 NOT NULL,
  "metodo_pago" text DEFAULT 'efectivo'::text NOT NULL,
  "entidad_bancaria_id" uuid,
  "referencia" text,
  "titular" text,
  "observaciones" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "usuario_id" uuid,
  "usuario_nombre" text,
  "entidad_nombre_snapshot" text,
  "conciliacion_estado" text DEFAULT 'pendiente'::text NOT NULL,
  "conciliado_at" timestamp with time zone,
  "conciliado_por" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_ajustes" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "periodo_id" uuid,
  "linea_id" uuid,
  "monto" numeric(18,2) NOT NULL,
  "motivo" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_equipo_miembros" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "equipo_id" uuid NOT NULL,
  "usuario_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_equipos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "supervisor_usuario_id" uuid NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_escalas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "politica_id" uuid NOT NULL,
  "orden" integer DEFAULT 0 NOT NULL,
  "desde_monto" numeric(18,2) NOT NULL,
  "hasta_monto" numeric(18,2),
  "porcentaje_comision" numeric(9,4) NOT NULL,
  "premio_fijo" numeric(18,2),
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_lineas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "periodo_id" uuid NOT NULL,
  "usuario_vendedor_id" uuid NOT NULL,
  "fuente_tipo" text,
  "fuente_id" uuid,
  "monto_base" numeric(18,2) DEFAULT 0 NOT NULL,
  "monto_comision" numeric(18,2) DEFAULT 0 NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_periodos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "politica_id" uuid NOT NULL,
  "estado" text DEFAULT 'borrador'::text NOT NULL,
  "fecha_inicio" timestamp with time zone NOT NULL,
  "fecha_fin" timestamp with time zone NOT NULL,
  "label" text,
  "congelado_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_politica_versiones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "politica_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "nombre" text NOT NULL,
  "activo" boolean NOT NULL,
  "base_calculo" text NOT NULL,
  "timezone" text NOT NULL,
  "modo_periodo" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."comision_politicas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "base_calculo" text NOT NULL,
  "timezone" text DEFAULT 'America/Asuncion'::text NOT NULL,
  "modo_periodo" text DEFAULT 'mensual_penultimo_dia_habil'::text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid,
  "updated_by" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."compras" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "proveedor_id" uuid NOT NULL,
  "proveedor_nombre" text NOT NULL,
  "producto_id" uuid NOT NULL,
  "producto_nombre" text NOT NULL,
  "cantidad" numeric NOT NULL,
  "moneda" text DEFAULT 'PYG'::text NOT NULL,
  "tipo_cambio" numeric DEFAULT 1 NOT NULL,
  "costo_unitario_original" numeric NOT NULL,
  "costo_unitario" numeric NOT NULL,
  "iva_tipo" text DEFAULT '10'::text NOT NULL,
  "subtotal" numeric NOT NULL,
  "monto_iva" numeric NOT NULL,
  "total" numeric NOT NULL,
  "precio_venta" numeric NOT NULL,
  "margen_venta" numeric,
  "tipo_pago" text DEFAULT 'contado'::text NOT NULL,
  "plazo_dias" integer,
  "nro_timbrado" text NOT NULL,
  "numero_control" text NOT NULL,
  "estado" text DEFAULT 'registrada'::text NOT NULL,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid,
  "usuario_nombre" text,
  "comprobante_url" text,
  "comprobante_storage_path" text,
  "comprobante_nombre" text,
  "comprobante_mime_type" text,
  "numero_factura" text,
  "orden_compra_numero" text,
  "orden_compra_item_id" uuid,
  "fecha_factura" date,
  "observacion" text,
  "anulada_at" timestamp with time zone,
  "anulada_por" uuid,
  "anulada_motivo" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."crm_etapas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "codigo" text NOT NULL,
  "nombre" text NOT NULL,
  "color" text DEFAULT 'gray'::text NOT NULL,
  "orden" integer DEFAULT 0 NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."crm_notas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "prospecto_id" uuid NOT NULL,
  "texto" text NOT NULL,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."crm_prospectos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "numero_control" text NOT NULL,
  "empresa" text NOT NULL,
  "contacto" text NOT NULL,
  "email" text,
  "telefono" text,
  "servicio" text NOT NULL,
  "valor_estimado" numeric DEFAULT 0,
  "etapa" text DEFAULT 'LEAD'::text NOT NULL,
  "proxima_accion" text,
  "fecha_proxima_accion" date,
  "creado_por" text,
  "responsable" text,
  "cliente_creado" boolean DEFAULT false,
  "fecha_creacion" timestamp with time zone DEFAULT now() NOT NULL,
  "fecha_actualizacion" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "origen_creacion" text DEFAULT 'manual'::text NOT NULL,
  "origen_detalle" text,
  "observaciones" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."cuentas_por_cobrar" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "venta_id" uuid NOT NULL,
  "numero_venta" text,
  "fecha_emision" date DEFAULT CURRENT_DATE NOT NULL,
  "fecha_vencimiento" date,
  "moneda" text DEFAULT 'PYG'::text NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "saldo" numeric DEFAULT 0 NOT NULL,
  "estado" text DEFAULT 'pendiente'::text NOT NULL,
  "observaciones" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."dashboard_views" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "slug" text NOT NULL,
  "nombre" text NOT NULL,
  "orden" integer DEFAULT 0 NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."devoluciones_venta" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "numero_devolucion" text NOT NULL,
  "venta_id" uuid NOT NULL,
  "venta_numero_control" text,
  "venta_fecha" timestamp with time zone,
  "cliente_id" uuid,
  "cliente_nombre" text,
  "tipo" text DEFAULT 'parcial'::text NOT NULL,
  "resolucion" text DEFAULT 'reembolso'::text NOT NULL,
  "estado" text DEFAULT 'confirmada'::text NOT NULL,
  "motivo" text,
  "total_devuelto" numeric DEFAULT 0 NOT NULL,
  "total_entregado" numeric DEFAULT 0 NOT NULL,
  "diferencia" numeric DEFAULT 0 NOT NULL,
  "metodo_reembolso" text,
  "caja_id" uuid,
  "caja_movimiento_id" uuid,
  "requiere_nota_credito" boolean DEFAULT false NOT NULL,
  "idempotency_key" text,
  "created_by" uuid,
  "usuario_nombre" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "anulada_at" timestamp with time zone,
  "anulada_por" uuid,
  "anulada_motivo" text,
  "anulada_caja_movimiento_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."devoluciones_venta_cambios" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "devolucion_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "producto_nombre" text NOT NULL,
  "sku" text,
  "cantidad" numeric NOT NULL,
  "precio_unitario" numeric NOT NULL,
  "tipo_iva" text DEFAULT '10%'::text NOT NULL,
  "monto_iva" numeric DEFAULT 0 NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."devoluciones_venta_items" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "devolucion_id" uuid NOT NULL,
  "venta_item_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "producto_nombre" text NOT NULL,
  "sku" text,
  "cantidad_vendida" numeric NOT NULL,
  "cantidad_devuelta" numeric NOT NULL,
  "precio_unitario" numeric NOT NULL,
  "tipo_iva" text NOT NULL,
  "monto_iva" numeric DEFAULT 0 NOT NULL,
  "total_devuelto" numeric DEFAULT 0 NOT NULL,
  "condicion" text DEFAULT 'buen_estado'::text NOT NULL,
  "reintegra_stock" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."empresa_autoimpresor_config" (
  "empresa_id" uuid NOT NULL,
  "activo" boolean DEFAULT false NOT NULL,
  "ruc_emisor" text,
  "razon_social_emisor" text,
  "nombre_fantasia" text,
  "direccion_matriz" text,
  "telefono" text,
  "timbrado_numero" text,
  "timbrado_inicio_vigencia" date,
  "timbrado_fin_vigencia" date,
  "establecimiento_codigo" text,
  "punto_expedicion_codigo" text,
  "numero_actual" integer,
  "numero_inicial" integer,
  "numero_final" integer,
  "tipo_documento_default" text DEFAULT 'factura'::text NOT NULL,
  "formato_impresion_default" text DEFAULT 'pdf_a4'::text NOT NULL,
  "leyenda_papel_termico" text,
  "observaciones" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."empresa_dashboard_views" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "dashboard_view_id" uuid NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."empresa_facturacion_modo" (
  "empresa_id" uuid NOT NULL,
  "modo" text DEFAULT 'sin_factura_fiscal'::text NOT NULL,
  "impresion_tipo_default" text DEFAULT 'pdf_a4'::text NOT NULL,
  "imprimir_al_confirmar" boolean DEFAULT false NOT NULL,
  "preguntar_datos_al_confirmar" boolean DEFAULT false NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."empresa_modulos" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "created_at" timestamp without time zone DEFAULT now() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "modulo_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."empresa_sifen_config" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "ambiente" text DEFAULT 'test'::text NOT NULL,
  "ruc" text NOT NULL,
  "razon_social" text NOT NULL,
  "timbrado_numero" text NOT NULL,
  "establecimiento" text NOT NULL,
  "punto_expedicion" text NOT NULL,
  "csc" text,
  "certificado_path" text,
  "certificado_vencimiento" timestamp with time zone,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "certificado_password_encrypted" text,
  "direccion_fiscal" text,
  "timbrado_fecha_inicio_vigencia" date,
  "actividad_economica_codigo" text,
  "actividad_economica_descripcion" text,
  "sifen_plazo_cancelacion_horas" integer DEFAULT 48 NOT NULL,
  "kude_logo_path" text,
  "kude_color_primario" text,
  "kude_color_primario_fill" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."empresas" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "nombre_empresa" text NOT NULL,
  "ruc" text,
  "telefono" text,
  "email" text,
  "direccion" text,
  "pais" text DEFAULT 'PARAGUAY'::text,
  "plan" text,
  "estado" text DEFAULT 'ACTIVA'::text,
  "created_at" timestamp without time zone DEFAULT now(),
  "data_schema" text,
  "gestion_tributaria_clientes" boolean DEFAULT false NOT NULL,
  "ofertas_countdown_end" timestamp with time zone
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."entidades_bancarias" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "tipo" text,
  "activo" boolean DEFAULT true NOT NULL,
  "orden" integer DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "codigo" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."factura_autoimpresor" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "venta_id" uuid NOT NULL,
  "numero_secuencia" integer NOT NULL,
  "numero_completo" text NOT NULL,
  "establecimiento_codigo" text NOT NULL,
  "punto_expedicion_codigo" text NOT NULL,
  "timbrado_numero" text NOT NULL,
  "timbrado_inicio_vigencia" date,
  "timbrado_fin_vigencia" date,
  "condicion" text DEFAULT 'contado'::text NOT NULL,
  "gravado_10" numeric DEFAULT 0 NOT NULL,
  "iva_10" numeric DEFAULT 0 NOT NULL,
  "gravado_5" numeric DEFAULT 0 NOT NULL,
  "iva_5" numeric DEFAULT 0 NOT NULL,
  "exentas" numeric DEFAULT 0 NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "emitida_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."factura_correlativos" (
  "empresa_id" uuid NOT NULL,
  "prefijo" text DEFAULT 'FAC-'::text NOT NULL,
  "ultimo_numero" bigint DEFAULT 0 NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."factura_electronica" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "factura_id" uuid NOT NULL,
  "estado_sifen" text DEFAULT 'borrador'::text NOT NULL,
  "cdc" text,
  "xml_path" text,
  "kude_url" text,
  "qr_data" text,
  "error" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "xml_firmado_path" text,
  "sifen_d_prot_cons_lote" text,
  "sifen_ultima_respuesta_recibe_lote" jsonb,
  "sifen_ultima_respuesta_consulta_lote" jsonb,
  "sifen_aprobado_at" timestamp with time zone,
  "sifen_cancelado_at" timestamp with time zone,
  "sifen_cancelacion_motivo" text,
  "sifen_regeneracion_seq" integer DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."factura_electronica_evento" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "factura_electronica_id" uuid NOT NULL,
  "tipo" text NOT NULL,
  "detalle" jsonb,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."factura_items" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "factura_id" uuid NOT NULL,
  "empresa_id" uuid NOT NULL,
  "descripcion" text NOT NULL,
  "cantidad" numeric DEFAULT 1 NOT NULL,
  "precio_unitario" numeric DEFAULT 0 NOT NULL,
  "subtotal" numeric DEFAULT 0 NOT NULL,
  "iva" numeric DEFAULT 0 NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."facturas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "numero_factura" text NOT NULL,
  "fecha" date NOT NULL,
  "fecha_vencimiento" date NOT NULL,
  "monto" numeric NOT NULL,
  "saldo" numeric DEFAULT 0 NOT NULL,
  "estado" text DEFAULT 'Pendiente'::text NOT NULL,
  "tipo" text NOT NULL,
  "moneda" text DEFAULT 'GS'::text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "suscripcion_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."gastos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "categoria" text,
  "descripcion" text,
  "monto" numeric(12,2) NOT NULL,
  "tipo" text DEFAULT 'variable'::text NOT NULL,
  "recurrente" boolean DEFAULT false NOT NULL,
  "frecuencia" text,
  "fecha" date NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "descuenta_caja" boolean DEFAULT false NOT NULL,
  "caja_movimiento_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."imports_audit" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "entidad" text NOT NULL,
  "filename" text,
  "total_rows" integer DEFAULT 0 NOT NULL,
  "inserted_count" integer DEFAULT 0 NOT NULL,
  "updated_count" integer DEFAULT 0 NOT NULL,
  "skipped_count" integer DEFAULT 0 NOT NULL,
  "error_count" integer DEFAULT 0 NOT NULL,
  "warning_count" integer DEFAULT 0 NOT NULL,
  "errors_json" jsonb,
  "warnings_json" jsonb,
  "created_by" text,
  "usuario_nombre" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."inventario_stock_ubicacion" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "ubicacion_id" uuid NOT NULL,
  "stock_actual" numeric DEFAULT 0 NOT NULL,
  "stock_minimo" numeric,
  "stock_maximo" numeric,
  "es_principal" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."inventario_ubicaciones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "codigo" text,
  "tipo" text DEFAULT 'deposito'::text NOT NULL,
  "parent_id" uuid,
  "descripcion" text,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."marketing_calendarios" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid,
  "mes" text,
  "semana" integer,
  "fecha_inicio" date,
  "fecha_fin" date,
  "estado_calendario" text DEFAULT 'pendiente'::text NOT NULL,
  "enviado_estado" text DEFAULT 'no_enviado'::text NOT NULL,
  "aprobado_estado" text DEFAULT 'pendiente'::text NOT NULL,
  "observaciones" text,
  "metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."marketing_comentarios" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "pieza_id" uuid NOT NULL,
  "usuario_id" uuid,
  "comentario" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."marketing_historial_estados" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "pieza_id" uuid NOT NULL,
  "campo" text NOT NULL,
  "estado_anterior" text,
  "estado_nuevo" text,
  "changed_by" uuid,
  "changed_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."marketing_piezas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "calendario_id" uuid,
  "cliente_id" uuid,
  "titulo" text NOT NULL,
  "tipo_pieza" text,
  "canal" text,
  "responsable_id" uuid,
  "fecha_limite" date,
  "fecha_publicacion" date,
  "prioridad" text DEFAULT 'media'::text NOT NULL,
  "estado_produccion" text DEFAULT 'por_hacer'::text NOT NULL,
  "estado_cliente" text DEFAULT 'no_enviado'::text NOT NULL,
  "estado_publicacion" text DEFAULT 'pendiente'::text NOT NULL,
  "link_archivo" text,
  "observaciones" text,
  "metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."marketing_tasks" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "titulo" text NOT NULL,
  "descripcion" text,
  "tipo_contenido" text NOT NULL,
  "estado" text DEFAULT 'pendiente'::text NOT NULL,
  "fecha_entrega" date NOT NULL,
  "responsable_user_id" uuid,
  "prioridad" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "suscripcion_id" uuid,
  "plan_id" uuid,
  "generada_automaticamente" boolean DEFAULT false NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."modulos" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "nombre" text,
  "descripcion" text,
  "slug" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."movimientos_inventario" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "producto_nombre" text NOT NULL,
  "producto_sku" text NOT NULL,
  "tipo" text NOT NULL,
  "cantidad" numeric NOT NULL,
  "costo_unitario" numeric DEFAULT 0 NOT NULL,
  "origen" text NOT NULL,
  "referencia" text,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "venta_id" uuid,
  "created_by" uuid,
  "usuario_nombre" text,
  "produccion_id" uuid,
  "anulado_at" timestamp with time zone,
  "anulado_por" uuid,
  "devolucion_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."nota_credito" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "factura_id" uuid NOT NULL,
  "monto" numeric NOT NULL,
  "motivo" text NOT NULL,
  "observacion_interna" text,
  "estado_erp" text DEFAULT 'borrador'::text NOT NULL,
  "created_by_user_id" uuid,
  "created_by_email_snapshot" text,
  "created_by_nombre_snapshot" text,
  "saldo_previo_snapshot" numeric NOT NULL,
  "monto_factura_snapshot" numeric NOT NULL,
  "suma_pagos_snapshot" numeric NOT NULL,
  "moneda_snapshot" text NOT NULL,
  "factura_electronica_origen_id" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."nota_credito_electronica" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nota_credito_id" uuid NOT NULL,
  "estado_sifen" text DEFAULT 'sin_envio'::text NOT NULL,
  "cdc" text,
  "cdc_factura_origen" text,
  "xml_path" text,
  "xml_firmado_path" text,
  "kude_url" text,
  "response_json" jsonb,
  "error" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "sifen_d_prot_cons_lote" text,
  "sifen_ultima_respuesta_recibe_lote" jsonb,
  "sifen_ultima_respuesta_consulta_lote" jsonb,
  "sifen_aprobado_at" timestamp with time zone,
  "last_response_json" jsonb,
  "last_error" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."nota_credito_evento" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nota_credito_id" uuid NOT NULL,
  "actor_user_id" uuid,
  "tipo_evento" text NOT NULL,
  "detalle_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."notificaciones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "tipo" text NOT NULL,
  "titulo" text NOT NULL,
  "mensaje" text NOT NULL,
  "producto_id" uuid,
  "url" text,
  "leida" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."obligaciones_tributarias_catalogo" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "slug" text NOT NULL,
  "nombre" text NOT NULL,
  "requiere_detalle_otro" boolean DEFAULT false NOT NULL,
  "orden" smallint DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."omnichannel_routes" (
  "meta_phone_number_id" text NOT NULL,
  "empresa_id" uuid NOT NULL,
  "channel_id" uuid NOT NULL,
  "data_schema" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."ordenes_compra" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "numero_oc" text NOT NULL,
  "proveedor_id" uuid NOT NULL,
  "proveedor_nombre" text DEFAULT ''::text NOT NULL,
  "producto_id" uuid NOT NULL,
  "producto_nombre" text DEFAULT ''::text NOT NULL,
  "cantidad" numeric DEFAULT 0 NOT NULL,
  "moneda" text DEFAULT 'PYG'::text NOT NULL,
  "tipo_cambio" numeric DEFAULT 1 NOT NULL,
  "costo_unitario_original" numeric DEFAULT 0 NOT NULL,
  "costo_unitario" numeric DEFAULT 0 NOT NULL,
  "iva_tipo" text DEFAULT '10'::text NOT NULL,
  "subtotal" numeric DEFAULT 0 NOT NULL,
  "monto_iva" numeric DEFAULT 0 NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "precio_venta" numeric DEFAULT 0 NOT NULL,
  "margen_venta" numeric,
  "tipo_pago" text DEFAULT 'contado'::text NOT NULL,
  "plazo_dias" integer,
  "estado" text DEFAULT 'abierta'::text NOT NULL,
  "observacion" text,
  "compra_numero_control" text,
  "recibida_at" timestamp with time zone,
  "cancelada_at" timestamp with time zone,
  "cancelada_motivo" text,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid,
  "usuario_nombre" text,
  "cantidad_recibida" numeric DEFAULT 0 NOT NULL,
  "cancelada_por" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."pagos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "factura_id" uuid NOT NULL,
  "monto" numeric NOT NULL,
  "fecha_pago" date NOT NULL,
  "metodo_pago" text DEFAULT 'efectivo'::text NOT NULL,
  "referencia" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "cliente_id" uuid,
  "usuario_id" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."pedidos_caja" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "titulo" text NOT NULL,
  "cliente_id" uuid,
  "cliente_nombre" text,
  "cliente_telefono" text,
  "observacion" text,
  "items" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "total_estimado" numeric DEFAULT 0 NOT NULL,
  "estado" text DEFAULT 'pendiente'::text NOT NULL,
  "armado_por_id" uuid,
  "armado_por_email" text,
  "venta_id" uuid,
  "venta_numero" text,
  "facturado_at" timestamp with time zone,
  "cancelado_por_id" uuid,
  "cancelado_motivo" text,
  "cancelado_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "numero" text,
  "abierto_por_id" uuid,
  "abierto_por_email" text,
  "abierto_at" timestamp with time zone,
  "en_cola_caja" boolean DEFAULT true NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."planes" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "codigo_plan" text NOT NULL,
  "nombre" text NOT NULL,
  "descripcion" text,
  "precio" numeric NOT NULL,
  "moneda" text DEFAULT 'GS'::text NOT NULL,
  "periodicidad" text DEFAULT 'mensual'::text NOT NULL,
  "limite_usuarios" integer,
  "limite_clientes" integer,
  "limite_facturas" integer,
  "estado" text DEFAULT 'activo'::text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "es_plan_marketing" boolean DEFAULT false NOT NULL,
  "plantilla_operativa" jsonb
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."presupuesto_items" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "presupuesto_id" uuid NOT NULL,
  "producto_id" uuid,
  "producto_nombre" text NOT NULL,
  "sku" text,
  "cantidad" numeric NOT NULL,
  "unidad_medida" text,
  "precio_unitario" numeric DEFAULT 0 NOT NULL,
  "iva_tipo" text DEFAULT '10%'::text NOT NULL,
  "subtotal" numeric DEFAULT 0 NOT NULL,
  "monto_iva" numeric DEFAULT 0 NOT NULL,
  "descuento" numeric DEFAULT 0 NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."presupuestos" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid,
  "cliente_nombre" text NOT NULL,
  "cliente_ruc" text,
  "cliente_telefono" text,
  "cliente_direccion" text,
  "numero_control" text NOT NULL,
  "estado" text DEFAULT 'creado'::text NOT NULL,
  "moneda" text DEFAULT 'PYG'::text NOT NULL,
  "subtotal" numeric DEFAULT 0 NOT NULL,
  "monto_iva" numeric DEFAULT 0 NOT NULL,
  "descuento_total" numeric DEFAULT 0 NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "validez_dias" integer,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "fecha_vencimiento" date,
  "forma_pago" text,
  "plazo_entrega" text,
  "observaciones" text,
  "convertido_pedido_id" uuid,
  "convertido_venta_id" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."produccion_items" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "produccion_id" uuid NOT NULL,
  "insumo_producto_id" uuid NOT NULL,
  "insumo_nombre" text NOT NULL,
  "cantidad" numeric NOT NULL,
  "unidad_medida" text,
  "costo_unitario" numeric DEFAULT 0 NOT NULL,
  "subcosto" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."producciones" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "receta_id" uuid,
  "producto_id" uuid NOT NULL,
  "producto_nombre" text NOT NULL,
  "cantidad_fabricada" numeric NOT NULL,
  "rendimiento_cantidad" numeric DEFAULT 1 NOT NULL,
  "unidad_rendimiento" text,
  "costo_total" numeric DEFAULT 0 NOT NULL,
  "costo_unitario" numeric DEFAULT 0 NOT NULL,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "usuario_id" uuid,
  "usuario_nombre" text,
  "observaciones" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."producto_categorias" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "categoria_id" uuid NOT NULL,
  "es_principal" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."producto_presentaciones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "cantidad_base" numeric NOT NULL,
  "precio_venta" numeric,
  "es_default" boolean DEFAULT false NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."productos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "sku" text NOT NULL,
  "costo_promedio" numeric DEFAULT 0 NOT NULL,
  "precio_venta" numeric DEFAULT 0 NOT NULL,
  "stock_actual" numeric DEFAULT 0 NOT NULL,
  "stock_minimo" numeric DEFAULT 0 NOT NULL,
  "unidad_medida" text DEFAULT 'Unidad'::text NOT NULL,
  "metodo_valuacion" text DEFAULT 'CPP'::text NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "imagen_url" text,
  "imagen_path" text,
  "codigo_barras" text,
  "codigo_barras_interno" boolean DEFAULT false NOT NULL,
  "proveedor_principal_id" uuid,
  "categoria_principal_id" uuid,
  "ubicacion_principal_id" uuid,
  "es_insumo" boolean DEFAULT false NOT NULL,
  "es_vendible" boolean DEFAULT true NOT NULL,
  "controla_stock" boolean DEFAULT true NOT NULL,
  "valorizado" boolean DEFAULT true NOT NULL,
  "unidad_compra" text,
  "unidad_receta" text,
  "factor_compra_receta" numeric DEFAULT 1 NOT NULL,
  "tiempo_prep_minutos" integer DEFAULT 0 NOT NULL,
  "descripcion" text,
  "precio_mayorista" numeric,
  "cantidad_minima_mayorista" numeric,
  "precio_distribuidor" numeric,
  "modo_receta" text DEFAULT 'preparado_al_vender'::text NOT NULL,
  "destacado" boolean DEFAULT false NOT NULL,
  "discount_type" text,
  "discount_value" numeric(12,2) DEFAULT 0 NOT NULL,
  "discount_starts_at" timestamp with time zone,
  "discount_ends_at" timestamp with time zone,
  "oferta_semana_destacada" boolean DEFAULT false NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."productos_codigo_secuencia" (
  "empresa_id" uuid NOT NULL,
  "last_value" bigint DEFAULT 0 NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proveedor_categoria_rel" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "proveedor_id" uuid NOT NULL,
  "categoria_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proveedor_categorias" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "descripcion" text,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proveedor_productos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "proveedor_id" uuid NOT NULL,
  "es_principal" boolean DEFAULT false NOT NULL,
  "codigo_proveedor" text,
  "costo_habitual" numeric,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "marca" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proveedores" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "ruc" text,
  "telefono" text,
  "email" text,
  "direccion" text,
  "contacto" text,
  "estado" text DEFAULT 'activo'::text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "nombre_comercial" text,
  "razon_social" text,
  "condicion_pago" text,
  "plazo_pago_dias" integer,
  "moneda_preferida" text,
  "observaciones" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyecto_archivos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "proyecto_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "storage_bucket" text DEFAULT 'proyectos'::text NOT NULL,
  "storage_path" text NOT NULL,
  "mime_type" text,
  "size_bytes" bigint,
  "uploaded_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyecto_comentarios" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "proyecto_id" uuid NOT NULL,
  "usuario_id" uuid NOT NULL,
  "comentario" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyecto_estado_historial" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "proyecto_id" uuid NOT NULL,
  "estado_anterior_id" uuid,
  "estado_nuevo_id" uuid NOT NULL,
  "changed_by" uuid,
  "changed_at" timestamp with time zone DEFAULT now() NOT NULL,
  "entered_at" timestamp with time zone DEFAULT now() NOT NULL,
  "exited_at" timestamp with time zone,
  "duration_seconds" bigint,
  "tipo_sla_snapshot" text,
  "metadata" jsonb DEFAULT '{}'::jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyecto_estados" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "codigo" text NOT NULL,
  "descripcion" text,
  "color" text DEFAULT '#64748b'::text NOT NULL,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "cuenta_sla" boolean DEFAULT true NOT NULL,
  "tipo_sla" text NOT NULL,
  "sla_horas_objetivo" integer,
  "es_estado_inicial" boolean DEFAULT false NOT NULL,
  "es_estado_final" boolean DEFAULT false NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyecto_prioridades_config" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "codigo" text NOT NULL,
  "nombre" text NOT NULL,
  "color" text,
  "bg_color" text,
  "text_color" text,
  "border_color" text,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyecto_tareas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "proyecto_id" uuid NOT NULL,
  "titulo" text NOT NULL,
  "descripcion" text,
  "estado" text DEFAULT 'pendiente'::text NOT NULL,
  "responsable_id" uuid,
  "fecha_limite" timestamp with time zone,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "completed_at" timestamp with time zone,
  "created_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyecto_tipos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "codigo" text NOT NULL,
  "descripcion" text,
  "config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."proyectos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid,
  "tipo_id" uuid NOT NULL,
  "estado_id" uuid NOT NULL,
  "titulo" text NOT NULL,
  "descripcion" text,
  "prioridad" text DEFAULT 'normal'::text NOT NULL,
  "responsable_comercial_id" uuid,
  "responsable_tecnico_id" uuid,
  "fecha_ingreso" timestamp with time zone DEFAULT now() NOT NULL,
  "fecha_prometida" timestamp with time zone,
  "fecha_entrega" timestamp with time zone,
  "monto_vendido" numeric(14,2),
  "observaciones_comerciales" text,
  "brief_data" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "bloqueado" boolean DEFAULT false NOT NULL,
  "bloqueo_motivo" text,
  "archivado" boolean DEFAULT false NOT NULL,
  "ultimo_movimiento_at" timestamp with time zone DEFAULT now() NOT NULL,
  "last_activity_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."receta_items" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "receta_id" uuid NOT NULL,
  "insumo_producto_id" uuid NOT NULL,
  "cantidad" numeric NOT NULL,
  "unidad_medida" text,
  "merma_pct" numeric DEFAULT 0 NOT NULL,
  "orden" integer DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."recetas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "nombre" text,
  "rendimiento_cantidad" numeric DEFAULT 1 NOT NULL,
  "rendimiento_unidad" text,
  "notas" text,
  "activa" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."recibos_dinero" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "numero_recibo" text NOT NULL,
  "cliente_id" uuid,
  "cliente_nombre" text NOT NULL,
  "cliente_documento" text,
  "origen" text DEFAULT 'manual'::text NOT NULL,
  "venta_id" uuid,
  "cuenta_por_cobrar_id" uuid,
  "cobro_cliente_id" uuid,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "moneda" text DEFAULT 'PYG'::text NOT NULL,
  "monto" numeric DEFAULT 0 NOT NULL,
  "metodo_pago" text,
  "entidad_bancaria_id" uuid,
  "referencia" text,
  "concepto" text,
  "observaciones" text,
  "usuario_id" uuid,
  "usuario_nombre" text,
  "anulado" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sifen_jobs" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "data_schema" text NOT NULL,
  "factura_id" uuid NOT NULL,
  "factura_electronica_id" uuid NOT NULL,
  "estado" text DEFAULT 'pendiente'::text NOT NULL,
  "etapa" text,
  "intentos" integer DEFAULT 0 NOT NULL,
  "max_intentos_auto" integer DEFAULT 2 NOT NULL,
  "intentos_log" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "codigo_error_set" text,
  "codigo_sub_error_set" text,
  "mensaje_set" text,
  "ultimo_error" text,
  "tipo_error" text,
  "respuesta_recibe_lote" jsonb,
  "respuesta_consulta_lote" jsonb,
  "cdc" text,
  "protocolo_lote" text,
  "tiempo_xml_ms" integer,
  "tiempo_firmar_ms" integer,
  "tiempo_enviar_ms" integer,
  "tiempo_consulta_ms" integer,
  "tiempo_total_ms" integer,
  "origen" text DEFAULT 'auto_venta'::text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "started_at" timestamp with time zone,
  "finished_at" timestamp with time zone,
  "procesando_desde" timestamp with time zone,
  "lock_owner" text,
  "proximo_reintento_at" timestamp with time zone,
  "veces_re_encolado_consulta" integer DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sorteo_conversaciones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "sorteo_id" uuid NOT NULL,
  "whatsapp_numero" text NOT NULL,
  "cliente_id" uuid,
  "estado" text DEFAULT 'new_lead'::text NOT NULL,
  "ultimo_mensaje" text,
  "cantidad_boletos" integer,
  "datos_cliente" jsonb DEFAULT '{}'::jsonb,
  "recordatorio_24h" boolean DEFAULT false,
  "recordatorio_48h" boolean DEFAULT false,
  "recordatorio_72h" boolean DEFAULT false,
  "ultimo_recordatorio_at" timestamp with time zone,
  "human_handoff_at" timestamp with time zone,
  "activa" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sorteo_cupones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "sorteo_id" uuid NOT NULL,
  "entrada_id" uuid NOT NULL,
  "numero_cupon" text NOT NULL,
  "ganador" boolean DEFAULT false,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "coupon_number_value" integer
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sorteo_entradas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "sorteo_id" uuid NOT NULL,
  "conversacion_id" uuid,
  "cliente_id" uuid,
  "whatsapp_numero" text NOT NULL,
  "nombre_participante" text NOT NULL,
  "documento" text,
  "cantidad_boletos" integer NOT NULL,
  "monto_total" numeric NOT NULL,
  "moneda" text DEFAULT 'PYG'::text NOT NULL,
  "estado_pago" text DEFAULT 'pendiente'::text NOT NULL,
  "fecha_pago" timestamp with time zone,
  "monto_pagado" numeric,
  "banco_origen" text,
  "comprobante_url" text,
  "comprobante_ia_resultado" jsonb DEFAULT '{}'::jsonb,
  "comprobante_ia_confianza" numeric,
  "validado_por" text DEFAULT 'IA'::text,
  "validado_por_user_id" uuid,
  "validado_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "numero_orden" integer NOT NULL,
  "chat_conversation_id" uuid,
  "flow_code" text,
  "idempotency_key" text,
  "promo_nombre" text,
  "precio_fuente" text,
  "precio_regular_referencia" numeric,
  "comprobante_validacion_id" uuid,
  "revendedor_id" uuid,
  "codigo_referido_snapshot" text,
  "observacion_interna" text,
  "venta_origen" text,
  "venta_canal" text,
  "pago_metodo" text,
  "cupones_impresos_at" timestamp with time zone,
  "cupones_impresos_by" uuid,
  "cupones_impresion_count" integer
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sorteo_revendedor_clicks" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "sorteo_id" uuid NOT NULL,
  "revendedor_id" uuid NOT NULL,
  "attribution_token" text NOT NULL,
  "user_agent" text,
  "ip_hash" text,
  "conversation_id" uuid,
  "flow_session_id" uuid,
  "contact_phone_norm" text,
  "redeemed_at" timestamp with time zone,
  "expires_at" timestamp with time zone NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sorteo_revendedores" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "sorteo_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "telefono" text,
  "codigo_referido" text NOT NULL,
  "activo" boolean DEFAULT true NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sorteo_ticket_deliveries" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "sorteo_id" uuid NOT NULL,
  "entrada_id" uuid NOT NULL,
  "conversation_id" uuid,
  "flow_session_id" uuid,
  "delivery_mode" text NOT NULL,
  "status" text NOT NULL,
  "cliente_nombre" text,
  "cliente_documento" text,
  "telefono" text,
  "numero_orden" text,
  "cupones" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "storage_bucket" text,
  "storage_path" text,
  "whatsapp_message_id" text,
  "provider" text,
  "channel_id" uuid,
  "error_message" text,
  "payload_snapshot" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "config_snapshot" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "template_revision" integer DEFAULT 1 NOT NULL,
  "is_current" boolean DEFAULT true NOT NULL,
  "png_bytes_hash" text,
  "generated_at" timestamp with time zone,
  "sent_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."sorteos" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "nombre" text NOT NULL,
  "descripcion" text,
  "precio_por_boleto" numeric DEFAULT 0 NOT NULL,
  "max_boletos" integer DEFAULT 100 NOT NULL,
  "total_boletos_vendidos" integer DEFAULT 0 NOT NULL,
  "ultimo_numero_cupon" integer DEFAULT 0 NOT NULL,
  "fecha_sorteo" timestamp with time zone,
  "estado" text DEFAULT 'activo'::text NOT NULL,
  "datos_bancarios" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "imagen_url" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "ultimo_numero_orden" integer DEFAULT 0 NOT NULL,
  "ticket_delivery_mode" text DEFAULT 'text_only'::text NOT NULL,
  "ticket_image_config" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "coupon_numbering_enabled" boolean DEFAULT false NOT NULL,
  "coupon_number_start" integer,
  "coupon_number_mode" text,
  "coupon_number_limit" integer
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."suscripciones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "plan_id" uuid,
  "precio" numeric DEFAULT 0 NOT NULL,
  "moneda" text DEFAULT 'GS'::text NOT NULL,
  "fecha_inicio" date NOT NULL,
  "duracion_meses" integer DEFAULT 12 NOT NULL,
  "dia_facturacion" integer DEFAULT 1 NOT NULL,
  "dia_vencimiento" integer DEFAULT 10 NOT NULL,
  "estado" text DEFAULT 'activa'::text NOT NULL,
  "generar_factura_este_mes" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "plan_pendiente_id" uuid,
  "precio_pendiente" numeric,
  "moneda_pendiente" text,
  "plan_pendiente_vigente_desde" date
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."tipificaciones" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid NOT NULL,
  "usuario" text NOT NULL,
  "tipo_gestion" text NOT NULL,
  "resultado" text NOT NULL,
  "observacion" text NOT NULL,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."usuario_dashboard_views" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "usuario_id" uuid NOT NULL,
  "dashboard_view_id" uuid NOT NULL,
  "es_default" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."usuario_modulos" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "usuario_id" uuid NOT NULL,
  "modulo_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."usuarios" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "email" text,
  "nombre" text,
  "rol" text,
  "empresa_id" uuid,
  "auth_user_id" uuid,
  "created_at" timestamp with time zone DEFAULT now(),
  "activo" boolean DEFAULT true,
  "porcentaje_comision" numeric,
  "estado" text DEFAULT 'activo'::text NOT NULL,
  "telefono" text,
  "fecha_nacimiento" date,
  "fecha_ingreso" date,
  "tipo_contrato" text,
  "salario_base" numeric,
  "ips" boolean DEFAULT false NOT NULL,
  "area" text
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."ventas" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "cliente_id" uuid,
  "numero_control" text NOT NULL,
  "moneda" text DEFAULT 'GS'::text NOT NULL,
  "tipo_cambio" numeric DEFAULT 1 NOT NULL,
  "subtotal" numeric DEFAULT 0 NOT NULL,
  "monto_iva" numeric DEFAULT 0 NOT NULL,
  "total" numeric DEFAULT 0 NOT NULL,
  "estado" text DEFAULT 'completada'::text NOT NULL,
  "tipo_venta" text DEFAULT 'CONTADO'::text NOT NULL,
  "plazo_dias" integer,
  "fecha" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "observaciones" text,
  "metodo_pago" text,
  "genera_nota_remision" boolean DEFAULT false NOT NULL,
  "nota_remision_numero" text,
  "caja_id" uuid,
  "created_by" uuid,
  "usuario_nombre" text,
  "anulada_at" timestamp with time zone,
  "anulada_motivo" text,
  "anulada_por" uuid
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."ventas_items" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "venta_id" uuid NOT NULL,
  "producto_id" uuid NOT NULL,
  "producto_nombre" text NOT NULL,
  "sku" text NOT NULL,
  "cantidad" numeric NOT NULL,
  "precio_venta_original" numeric NOT NULL,
  "precio_venta" numeric NOT NULL,
  "tipo_iva" text DEFAULT '10%'::text NOT NULL,
  "subtotal" numeric NOT NULL,
  "monto_iva" numeric NOT NULL,
  "total_linea" numeric NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "tipo_precio" text DEFAULT 'minorista'::text NOT NULL,
  "presentacion_id" uuid,
  "presentacion_nombre" text,
  "presentacion_cantidad_base" numeric,
  "cantidad_total_base" numeric
);
CREATE TABLE IF NOT EXISTS "tecnolabo"."ventas_pagos_detalle" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "empresa_id" uuid NOT NULL,
  "venta_id" uuid NOT NULL,
  "metodo_pago" text NOT NULL,
  "entidad_bancaria_id" uuid,
  "entidad_nombre_snapshot" text,
  "monto" numeric DEFAULT 0 NOT NULL,
  "referencia" text,
  "fecha_pago" timestamp with time zone DEFAULT now() NOT NULL,
  "fecha_acreditacion" date,
  "observacion" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "titular" text,
  "conciliacion_estado" text DEFAULT 'pendiente'::text NOT NULL,
  "conciliado_at" timestamp with time zone,
  "conciliado_por" text
);

-- ── CONSTRAINTS (PK / UNIQUE / CHECK) ────────────────────────────────────────

DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'caja_movimientos_medio_pago_check'
                    AND conrelid = '"tecnolabo"."caja_movimientos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."caja_movimientos" ADD CONSTRAINT "caja_movimientos_medio_pago_check" CHECK ((medio_pago = ANY (ARRAY['efectivo'::text, 'tarjeta'::text, 'transferencia'::text, 'otro'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'caja_movimientos_pkey'
                    AND conrelid = '"tecnolabo"."caja_movimientos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."caja_movimientos" ADD CONSTRAINT "caja_movimientos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'caja_movimientos_tipo_check'
                    AND conrelid = '"tecnolabo"."caja_movimientos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."caja_movimientos" ADD CONSTRAINT "caja_movimientos_tipo_check" CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'retiro'::text, 'ajuste'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cajas_estado_check'
                    AND conrelid = '"tecnolabo"."cajas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cajas" ADD CONSTRAINT "cajas_estado_check" CHECK ((estado = ANY (ARRAY['abierta'::text, 'en_cierre'::text, 'cerrada'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cajas_pkey'
                    AND conrelid = '"tecnolabo"."cajas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cajas" ADD CONSTRAINT "cajas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'categorias_productos_pkey'
                    AND conrelid = '"tecnolabo"."categorias_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."categorias_productos" ADD CONSTRAINT "categorias_productos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_agents_max_conversations_check'
                    AND conrelid = '"tecnolabo"."chat_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_agents" ADD CONSTRAINT "chat_agents_max_conversations_check" CHECK ((max_conversations >= 1));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_agents_operational_status_check'
                    AND conrelid = '"tecnolabo"."chat_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_agents" ADD CONSTRAINT "chat_agents_operational_status_check" CHECK ((operational_status = ANY (ARRAY['ready'::text, 'offline'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_agents_pkey'
                    AND conrelid = '"tecnolabo"."chat_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_agents" ADD CONSTRAINT "chat_agents_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_agents_usuario_id_queue_id_key'
                    AND conrelid = '"tecnolabo"."chat_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_agents" ADD CONSTRAINT "chat_agents_usuario_id_queue_id_key" UNIQUE (usuario_id, queue_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_events_pkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_events" ADD CONSTRAINT "chat_campaign_events_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_jobs_pkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_jobs" ADD CONSTRAINT "chat_campaign_jobs_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_jobs_status_check'
                    AND conrelid = '"tecnolabo"."chat_campaign_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_jobs" ADD CONSTRAINT "chat_campaign_jobs_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'done'::text, 'failed'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_recipients_pkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_recipients"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_recipients" ADD CONSTRAINT "chat_campaign_recipients_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_recipients_status_check'
                    AND conrelid = '"tecnolabo"."chat_campaign_recipients"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_recipients" ADD CONSTRAINT "chat_campaign_recipients_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'invalid'::text, 'queued'::text, 'sending'::text, 'sent'::text, 'failed'::text, 'replied'::text, 'skipped'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_templates_name_trim'
                    AND conrelid = '"tecnolabo"."chat_campaign_templates"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_templates" ADD CONSTRAINT "chat_campaign_templates_name_trim" CHECK ((length(TRIM(BOTH FROM name)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_templates_pkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_templates"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_templates" ADD CONSTRAINT "chat_campaign_templates_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_templates_provider_check'
                    AND conrelid = '"tecnolabo"."chat_campaign_templates"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_templates" ADD CONSTRAINT "chat_campaign_templates_provider_check" CHECK ((provider = ANY (ARRAY['meta'::text, 'ycloud'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaigns_name_trim'
                    AND conrelid = '"tecnolabo"."chat_campaigns"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaigns" ADD CONSTRAINT "chat_campaigns_name_trim" CHECK ((length(TRIM(BOTH FROM name)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaigns_pkey'
                    AND conrelid = '"tecnolabo"."chat_campaigns"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaigns" ADD CONSTRAINT "chat_campaigns_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaigns_provider_check'
                    AND conrelid = '"tecnolabo"."chat_campaigns"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaigns" ADD CONSTRAINT "chat_campaigns_provider_check" CHECK ((provider = ANY (ARRAY['meta'::text, 'ycloud'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaigns_status_check'
                    AND conrelid = '"tecnolabo"."chat_campaigns"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaigns" ADD CONSTRAINT "chat_campaigns_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'ready'::text, 'sending'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channel_quick_replies_body_trim'
                    AND conrelid = '"tecnolabo"."chat_channel_quick_replies"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channel_quick_replies" ADD CONSTRAINT "chat_channel_quick_replies_body_trim" CHECK ((length(TRIM(BOTH FROM body)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channel_quick_replies_pkey'
                    AND conrelid = '"tecnolabo"."chat_channel_quick_replies"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channel_quick_replies" ADD CONSTRAINT "chat_channel_quick_replies_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channel_quick_replies_title_trim'
                    AND conrelid = '"tecnolabo"."chat_channel_quick_replies"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channel_quick_replies" ADD CONSTRAINT "chat_channel_quick_replies_title_trim" CHECK ((length(TRIM(BOTH FROM title)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channels_config_status_check'
                    AND conrelid = '"tecnolabo"."chat_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channels" ADD CONSTRAINT "chat_channels_config_status_check" CHECK ((config_status = ANY (ARRAY['inactive'::text, 'incomplete'::text, 'active'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channels_pkey'
                    AND conrelid = '"tecnolabo"."chat_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channels" ADD CONSTRAINT "chat_channels_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channels_type_check'
                    AND conrelid = '"tecnolabo"."chat_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channels" ADD CONSTRAINT "chat_channels_type_check" CHECK ((type = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'facebook'::text, 'email'::text, 'linkedin'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_comprobante_validaciones_estado_validacion_check'
                    AND conrelid = '"tecnolabo"."chat_comprobante_validaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ADD CONSTRAINT "chat_comprobante_validaciones_estado_validacion_check" CHECK ((estado_validacion = ANY (ARRAY['pendiente'::text, 'valido'::text, 'duplicado_hash'::text, 'duplicado_ocr'::text, 'revision_manual'::text, 'ocr_error'::text, 'monto_incoherente'::text, 'datos_bancarios_incoherentes'::text, 'aprobado_manual'::text, 'rechazado_manual'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_comprobante_validaciones_pkey'
                    AND conrelid = '"tecnolabo"."chat_comprobante_validaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ADD CONSTRAINT "chat_comprobante_validaciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_contacts_empresa_id_phone_number_key'
                    AND conrelid = '"tecnolabo"."chat_contacts"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_contacts" ADD CONSTRAINT "chat_contacts_empresa_id_phone_number_key" UNIQUE (empresa_id, phone_number);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_contacts_pkey'
                    AND conrelid = '"tecnolabo"."chat_contacts"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_contacts" ADD CONSTRAINT "chat_contacts_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversation_closures_pkey'
                    AND conrelid = '"tecnolabo"."chat_conversation_closures"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversation_closures" ADD CONSTRAINT "chat_conversation_closures_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_contact_id_channel_id_key'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_contact_id_channel_id_key" UNIQUE (contact_id, channel_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_pkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_priority_check'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_priority_check" CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_status_check'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'pending'::text, 'closed'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_empresa_operator_roles_empresa_id_usuario_id_key'
                    AND conrelid = '"tecnolabo"."chat_empresa_operator_roles"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_empresa_operator_roles" ADD CONSTRAINT "chat_empresa_operator_roles_empresa_id_usuario_id_key" UNIQUE (empresa_id, usuario_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_empresa_operator_roles_pkey'
                    AND conrelid = '"tecnolabo"."chat_empresa_operator_roles"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_empresa_operator_roles" ADD CONSTRAINT "chat_empresa_operator_roles_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_empresa_operator_roles_role_check'
                    AND conrelid = '"tecnolabo"."chat_empresa_operator_roles"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_empresa_operator_roles" ADD CONSTRAINT "chat_empresa_operator_roles_role_check" CHECK ((role = ANY (ARRAY['admin'::text, 'supervisor'::text, 'agente'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_data_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_data"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_data" ADD CONSTRAINT "chat_flow_data_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_events_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_events" ADD CONSTRAINT "chat_flow_events_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_node_blocks_block_type_check'
                    AND conrelid = '"tecnolabo"."chat_flow_node_blocks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_node_blocks" ADD CONSTRAINT "chat_flow_node_blocks_block_type_check" CHECK ((block_type = ANY (ARRAY['text'::text, 'image'::text, 'buttons'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_node_blocks_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_node_blocks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_node_blocks" ADD CONSTRAINT "chat_flow_node_blocks_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_nodes_empresa_id_flow_code_node_code_key'
                    AND conrelid = '"tecnolabo"."chat_flow_nodes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_nodes" ADD CONSTRAINT "chat_flow_nodes_empresa_id_flow_code_node_code_key" UNIQUE (empresa_id, flow_code, node_code);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_nodes_node_type_check'
                    AND conrelid = '"tecnolabo"."chat_flow_nodes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_nodes" ADD CONSTRAINT "chat_flow_nodes_node_type_check" CHECK ((node_type = ANY (ARRAY['buttons'::text, 'list'::text, 'text'::text, 'media'::text, 'image_input'::text, 'human'::text, 'end'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_nodes_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_nodes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_nodes" ADD CONSTRAINT "chat_flow_nodes_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_options_node_id_meta_button_id_key'
                    AND conrelid = '"tecnolabo"."chat_flow_options"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_options" ADD CONSTRAINT "chat_flow_options_node_id_meta_button_id_key" UNIQUE (node_id, meta_button_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_options_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_options"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_options" ADD CONSTRAINT "chat_flow_options_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cfr_rules_cooldown_min'
                    AND conrelid = '"tecnolabo"."chat_flow_recontact_rules"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_recontact_rules" ADD CONSTRAINT "cfr_rules_cooldown_min" CHECK ((cooldown_seconds >= 60));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cfr_rules_idle_min'
                    AND conrelid = '"tecnolabo"."chat_flow_recontact_rules"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_recontact_rules" ADD CONSTRAINT "cfr_rules_idle_min" CHECK ((idle_after_seconds >= 60));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cfr_rules_max_attempts'
                    AND conrelid = '"tecnolabo"."chat_flow_recontact_rules"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_recontact_rules" ADD CONSTRAINT "cfr_rules_max_attempts" CHECK ((max_attempts >= 1));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_recontact_rules_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_recontact_rules"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_recontact_rules" ADD CONSTRAINT "chat_flow_recontact_rules_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_recontact_runs_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_recontact_runs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_recontact_runs" ADD CONSTRAINT "chat_flow_recontact_runs_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_sessions_pkey'
                    AND conrelid = '"tecnolabo"."chat_flow_sessions"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_sessions" ADD CONSTRAINT "chat_flow_sessions_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_sessions_referral_source_check'
                    AND conrelid = '"tecnolabo"."chat_flow_sessions"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_sessions" ADD CONSTRAINT "chat_flow_sessions_referral_source_check" CHECK (((referral_source IS NULL) OR (referral_source = ANY (ARRAY['click_token'::text, 'inbound_text'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_sessions_status_check'
                    AND conrelid = '"tecnolabo"."chat_flow_sessions"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_sessions" ADD CONSTRAINT "chat_flow_sessions_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'abandoned'::text, 'restarted'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flows_empresa_id_flow_code_key'
                    AND conrelid = '"tecnolabo"."chat_flows"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flows" ADD CONSTRAINT "chat_flows_empresa_id_flow_code_key" UNIQUE (empresa_id, flow_code);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flows_pkey'
                    AND conrelid = '"tecnolabo"."chat_flows"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flows" ADD CONSTRAINT "chat_flows_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_messages_pkey'
                    AND conrelid = '"tecnolabo"."chat_messages"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_messages" ADD CONSTRAINT "chat_messages_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_messages_sender_type_check'
                    AND conrelid = '"tecnolabo"."chat_messages"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_messages" ADD CONSTRAINT "chat_messages_sender_type_check" CHECK ((sender_type = ANY (ARRAY['contact'::text, 'ai'::text, 'human'::text, 'system'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_omnicanal_work_schedules_days_check'
                    AND conrelid = '"tecnolabo"."chat_omnicanal_work_schedules"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_omnicanal_work_schedules" ADD CONSTRAINT "chat_omnicanal_work_schedules_days_check" CHECK ((days_of_week <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint, (6)::smallint, (7)::smallint]));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_omnicanal_work_schedules_pkey'
                    AND conrelid = '"tecnolabo"."chat_omnicanal_work_schedules"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_omnicanal_work_schedules" ADD CONSTRAINT "chat_omnicanal_work_schedules_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_channels_pkey'
                    AND conrelid = '"tecnolabo"."chat_queue_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_channels" ADD CONSTRAINT "chat_queue_channels_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_channels_queue_id_channel_id_key'
                    AND conrelid = '"tecnolabo"."chat_queue_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_channels" ADD CONSTRAINT "chat_queue_channels_queue_id_channel_id_key" UNIQUE (queue_id, channel_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_closure_states_pkey'
                    AND conrelid = '"tecnolabo"."chat_queue_closure_states"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_closure_states" ADD CONSTRAINT "chat_queue_closure_states_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_closure_substates_pkey'
                    AND conrelid = '"tecnolabo"."chat_queue_closure_substates"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_closure_substates" ADD CONSTRAINT "chat_queue_closure_substates_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_supervisors_pkey'
                    AND conrelid = '"tecnolabo"."chat_queue_supervisors"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_supervisors" ADD CONSTRAINT "chat_queue_supervisors_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_supervisors_queue_id_usuario_id_key'
                    AND conrelid = '"tecnolabo"."chat_queue_supervisors"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_supervisors" ADD CONSTRAINT "chat_queue_supervisors_queue_id_usuario_id_key" UNIQUE (queue_id, usuario_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queues_channel_type_check'
                    AND conrelid = '"tecnolabo"."chat_queues"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queues" ADD CONSTRAINT "chat_queues_channel_type_check" CHECK (((channel_type IS NULL) OR (channel_type = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'facebook'::text, 'email'::text, 'linkedin'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queues_distribution_strategy_check'
                    AND conrelid = '"tecnolabo"."chat_queues"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queues" ADD CONSTRAINT "chat_queues_distribution_strategy_check" CHECK ((distribution_strategy = ANY (ARRAY['round_robin'::text, 'least_load'::text, 'manual_pull'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queues_pkey'
                    AND conrelid = '"tecnolabo"."chat_queues"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queues" ADD CONSTRAINT "chat_queues_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_routing_events_pkey'
                    AND conrelid = '"tecnolabo"."chat_routing_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_routing_events" ADD CONSTRAINT "chat_routing_events_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_supervisor_agents_empresa_id_supervisor_usuario_id_age_key'
                    AND conrelid = '"tecnolabo"."chat_supervisor_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_supervisor_agents" ADD CONSTRAINT "chat_supervisor_agents_empresa_id_supervisor_usuario_id_age_key" UNIQUE (empresa_id, supervisor_usuario_id, agent_usuario_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_supervisor_agents_no_self'
                    AND conrelid = '"tecnolabo"."chat_supervisor_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_supervisor_agents" ADD CONSTRAINT "chat_supervisor_agents_no_self" CHECK ((supervisor_usuario_id <> agent_usuario_id));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_supervisor_agents_pkey'
                    AND conrelid = '"tecnolabo"."chat_supervisor_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_supervisor_agents" ADD CONSTRAINT "chat_supervisor_agents_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_usuario_omnicanal_empresa_id_usuario_id_key'
                    AND conrelid = '"tecnolabo"."chat_usuario_omnicanal"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_usuario_omnicanal" ADD CONSTRAINT "chat_usuario_omnicanal_empresa_id_usuario_id_key" UNIQUE (empresa_id, usuario_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_usuario_omnicanal_pkey'
                    AND conrelid = '"tecnolabo"."chat_usuario_omnicanal"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_usuario_omnicanal" ADD CONSTRAINT "chat_usuario_omnicanal_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_historial_modo_check'
                    AND conrelid = '"tecnolabo"."cliente_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_historial" ADD CONSTRAINT "cliente_historial_modo_check" CHECK (((modo IS NULL) OR (modo = ANY (ARRAY['inmediato'::text, 'proximo_mes'::text, 'actualizar_factura_pendiente'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_historial_pkey'
                    AND conrelid = '"tecnolabo"."cliente_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_historial" ADD CONSTRAINT "cliente_historial_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_obligaciones_tributar_cliente_perfil_id_obligacion__key'
                    AND conrelid = '"tecnolabo"."cliente_obligaciones_tributarias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_obligaciones_tributarias" ADD CONSTRAINT "cliente_obligaciones_tributar_cliente_perfil_id_obligacion__key" UNIQUE (cliente_perfil_id, obligacion_catalogo_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_obligaciones_tributarias_pkey'
                    AND conrelid = '"tecnolabo"."cliente_obligaciones_tributarias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_obligaciones_tributarias" ADD CONSTRAINT "cliente_obligaciones_tributarias_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_perfil_tributario_dia_vencimiento_range'
                    AND conrelid = '"tecnolabo"."cliente_perfil_tributario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_perfil_tributario" ADD CONSTRAINT "cliente_perfil_tributario_dia_vencimiento_range" CHECK (((dia_vencimiento_tributario IS NULL) OR ((dia_vencimiento_tributario >= 1) AND (dia_vencimiento_tributario <= 31))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_perfil_tributario_empresa_id_cliente_id_key'
                    AND conrelid = '"tecnolabo"."cliente_perfil_tributario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_perfil_tributario" ADD CONSTRAINT "cliente_perfil_tributario_empresa_id_cliente_id_key" UNIQUE (empresa_id, cliente_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_perfil_tributario_pkey'
                    AND conrelid = '"tecnolabo"."cliente_perfil_tributario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_perfil_tributario" ADD CONSTRAINT "cliente_perfil_tributario_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'c_cliente_tipo_cat_slug_format'
                    AND conrelid = '"tecnolabo"."cliente_tipos_servicio_catalogo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_tipos_servicio_catalogo" ADD CONSTRAINT "c_cliente_tipo_cat_slug_format" CHECK (((char_length(btrim(slug)) > 0) AND (slug = lower(btrim(slug))) AND (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_tipos_servicio_catalogo_empresa_id_slug_key'
                    AND conrelid = '"tecnolabo"."cliente_tipos_servicio_catalogo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_tipos_servicio_catalogo" ADD CONSTRAINT "cliente_tipos_servicio_catalogo_empresa_id_slug_key" UNIQUE (empresa_id, slug);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_tipos_servicio_catalogo_pkey'
                    AND conrelid = '"tecnolabo"."cliente_tipos_servicio_catalogo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_tipos_servicio_catalogo" ADD CONSTRAINT "cliente_tipos_servicio_catalogo_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_pkey'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_sifen_receptor_naturaleza_check'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_sifen_receptor_naturaleza_check" CHECK (((sifen_receptor_naturaleza IS NULL) OR (sifen_receptor_naturaleza = ANY (ARRAY['contribuyente_paraguayo'::text, 'no_contribuyente'::text, 'extranjero'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_sifen_ti_ope_check'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_sifen_ti_ope_check" CHECK (((sifen_ti_ope IS NULL) OR ((sifen_ti_ope >= 1) AND (sifen_ti_ope <= 4))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cc_conciliacion_estado_check'
                    AND conrelid = '"tecnolabo"."cobros_clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cobros_clientes" ADD CONSTRAINT "cc_conciliacion_estado_check" CHECK ((conciliacion_estado = ANY (ARRAY['pendiente'::text, 'aprobado'::text, 'rechazado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cobros_clientes_pkey'
                    AND conrelid = '"tecnolabo"."cobros_clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cobros_clientes" ADD CONSTRAINT "cobros_clientes_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_comision_ajustes_motivo'
                    AND conrelid = '"tecnolabo"."comision_ajustes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_ajustes" ADD CONSTRAINT "chk_comision_ajustes_motivo" CHECK ((length(TRIM(BOTH FROM motivo)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_ajustes_pkey'
                    AND conrelid = '"tecnolabo"."comision_ajustes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_ajustes" ADD CONSTRAINT "comision_ajustes_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipo_miembros_equipo_id_usuario_id_key'
                    AND conrelid = '"tecnolabo"."comision_equipo_miembros"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipo_miembros" ADD CONSTRAINT "comision_equipo_miembros_equipo_id_usuario_id_key" UNIQUE (equipo_id, usuario_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipo_miembros_pkey'
                    AND conrelid = '"tecnolabo"."comision_equipo_miembros"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipo_miembros" ADD CONSTRAINT "comision_equipo_miembros_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_comision_equipos_nombre'
                    AND conrelid = '"tecnolabo"."comision_equipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipos" ADD CONSTRAINT "chk_comision_equipos_nombre" CHECK ((length(TRIM(BOTH FROM nombre)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipos_pkey'
                    AND conrelid = '"tecnolabo"."comision_equipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipos" ADD CONSTRAINT "comision_equipos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_escalas_pkey'
                    AND conrelid = '"tecnolabo"."comision_escalas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_escalas" ADD CONSTRAINT "comision_escalas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_lineas_pkey'
                    AND conrelid = '"tecnolabo"."comision_lineas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_lineas" ADD CONSTRAINT "comision_lineas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_periodos_estado_check'
                    AND conrelid = '"tecnolabo"."comision_periodos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_periodos" ADD CONSTRAINT "comision_periodos_estado_check" CHECK ((estado = ANY (ARRAY['borrador'::text, 'cerrado'::text, 'congelado'::text, 'aprobado'::text, 'pagado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_periodos_pkey'
                    AND conrelid = '"tecnolabo"."comision_periodos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_periodos" ADD CONSTRAINT "comision_periodos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politica_versiones_pkey'
                    AND conrelid = '"tecnolabo"."comision_politica_versiones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politica_versiones" ADD CONSTRAINT "comision_politica_versiones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politica_versiones_politica_id_version_no_key'
                    AND conrelid = '"tecnolabo"."comision_politica_versiones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politica_versiones" ADD CONSTRAINT "comision_politica_versiones_politica_id_version_no_key" UNIQUE (politica_id, version_no);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_comision_politicas_nombre'
                    AND conrelid = '"tecnolabo"."comision_politicas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politicas" ADD CONSTRAINT "chk_comision_politicas_nombre" CHECK ((length(TRIM(BOTH FROM nombre)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politicas_base_calculo_check'
                    AND conrelid = '"tecnolabo"."comision_politicas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politicas" ADD CONSTRAINT "comision_politicas_base_calculo_check" CHECK ((base_calculo = ANY (ARRAY['pago_registrado'::text, 'factura_emitida'::text, 'factura_pagada'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politicas_empresa_id_key'
                    AND conrelid = '"tecnolabo"."comision_politicas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politicas" ADD CONSTRAINT "comision_politicas_empresa_id_key" UNIQUE (empresa_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politicas_pkey'
                    AND conrelid = '"tecnolabo"."comision_politicas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politicas" ADD CONSTRAINT "comision_politicas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_estado_check'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_estado_check" CHECK ((estado = ANY (ARRAY['registrada'::text, 'pendiente'::text, 'pagada'::text, 'anulada'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_iva_tipo_check'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_iva_tipo_check" CHECK ((iva_tipo = ANY (ARRAY['exenta'::text, '5'::text, '10'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_moneda_check'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_moneda_check" CHECK ((moneda = ANY (ARRAY['PYG'::text, 'USD'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_pkey'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_tipo_pago_check'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_tipo_pago_check" CHECK ((tipo_pago = ANY (ARRAY['contado'::text, 'credito'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_etapas_empresa_id_codigo_key'
                    AND conrelid = '"tecnolabo"."crm_etapas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_etapas" ADD CONSTRAINT "crm_etapas_empresa_id_codigo_key" UNIQUE (empresa_id, codigo);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_etapas_pkey'
                    AND conrelid = '"tecnolabo"."crm_etapas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_etapas" ADD CONSTRAINT "crm_etapas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_notas_pkey'
                    AND conrelid = '"tecnolabo"."crm_notas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_notas" ADD CONSTRAINT "crm_notas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_prospectos_pkey'
                    AND conrelid = '"tecnolabo"."crm_prospectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_prospectos" ADD CONSTRAINT "crm_prospectos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cuentas_por_cobrar_estado_check'
                    AND conrelid = '"tecnolabo"."cuentas_por_cobrar"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cuentas_por_cobrar" ADD CONSTRAINT "cuentas_por_cobrar_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'parcial'::text, 'pagado'::text, 'vencido'::text, 'anulado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cuentas_por_cobrar_pkey'
                    AND conrelid = '"tecnolabo"."cuentas_por_cobrar"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cuentas_por_cobrar" ADD CONSTRAINT "cuentas_por_cobrar_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'dashboard_views_pkey'
                    AND conrelid = '"tecnolabo"."dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."dashboard_views" ADD CONSTRAINT "dashboard_views_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'dashboard_views_slug_key'
                    AND conrelid = '"tecnolabo"."dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."dashboard_views" ADD CONSTRAINT "dashboard_views_slug_key" UNIQUE (slug);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_estado_check'
                    AND conrelid = '"tecnolabo"."devoluciones_venta"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta" ADD CONSTRAINT "devoluciones_venta_estado_check" CHECK ((estado = ANY (ARRAY['confirmada'::text, 'anulada'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_metodo_check'
                    AND conrelid = '"tecnolabo"."devoluciones_venta"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta" ADD CONSTRAINT "devoluciones_venta_metodo_check" CHECK (((metodo_reembolso IS NULL) OR (metodo_reembolso = ANY (ARRAY['efectivo'::text, 'tarjeta'::text, 'transferencia'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_pkey'
                    AND conrelid = '"tecnolabo"."devoluciones_venta"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta" ADD CONSTRAINT "devoluciones_venta_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_resolucion_check'
                    AND conrelid = '"tecnolabo"."devoluciones_venta"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta" ADD CONSTRAINT "devoluciones_venta_resolucion_check" CHECK ((resolucion = ANY (ARRAY['reembolso'::text, 'cambio'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_tipo_check'
                    AND conrelid = '"tecnolabo"."devoluciones_venta"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta" ADD CONSTRAINT "devoluciones_venta_tipo_check" CHECK ((tipo = ANY (ARRAY['total'::text, 'parcial'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_cambios_cant_check'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_cambios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_cambios" ADD CONSTRAINT "devoluciones_venta_cambios_cant_check" CHECK ((cantidad > (0)::numeric));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_cambios_pkey'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_cambios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_cambios" ADD CONSTRAINT "devoluciones_venta_cambios_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_items_cant_check'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_items" ADD CONSTRAINT "devoluciones_venta_items_cant_check" CHECK ((cantidad_devuelta > (0)::numeric));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_items_condicion_check'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_items" ADD CONSTRAINT "devoluciones_venta_items_condicion_check" CHECK ((condicion = ANY (ARRAY['buen_estado'::text, 'danado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_items_pkey'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_items" ADD CONSTRAINT "devoluciones_venta_items_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_autoimpresor_config_formato_impresion_default_check'
                    AND conrelid = '"tecnolabo"."empresa_autoimpresor_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_autoimpresor_config" ADD CONSTRAINT "empresa_autoimpresor_config_formato_impresion_default_check" CHECK ((formato_impresion_default = ANY (ARRAY['pdf_a4'::text, 'pdf_media_hoja'::text, 'ticket_80mm'::text, 'ticket_58mm'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_autoimpresor_config_pkey'
                    AND conrelid = '"tecnolabo"."empresa_autoimpresor_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_autoimpresor_config" ADD CONSTRAINT "empresa_autoimpresor_config_pkey" PRIMARY KEY (empresa_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_autoimpresor_config_tipo_documento_default_check'
                    AND conrelid = '"tecnolabo"."empresa_autoimpresor_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_autoimpresor_config" ADD CONSTRAINT "empresa_autoimpresor_config_tipo_documento_default_check" CHECK ((tipo_documento_default = ANY (ARRAY['factura'::text, 'ticket'::text, 'nota_venta'::text, 'otro'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_dashboard_views_empresa_id_dashboard_view_id_key'
                    AND conrelid = '"tecnolabo"."empresa_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_dashboard_views" ADD CONSTRAINT "empresa_dashboard_views_empresa_id_dashboard_view_id_key" UNIQUE (empresa_id, dashboard_view_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_dashboard_views_pkey'
                    AND conrelid = '"tecnolabo"."empresa_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_dashboard_views" ADD CONSTRAINT "empresa_dashboard_views_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_facturacion_modo_impresion_tipo_default_check'
                    AND conrelid = '"tecnolabo"."empresa_facturacion_modo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_facturacion_modo" ADD CONSTRAINT "empresa_facturacion_modo_impresion_tipo_default_check" CHECK ((impresion_tipo_default = ANY (ARRAY['pdf_a4'::text, 'pdf_media_hoja'::text, 'ticket_80mm'::text, 'ticket_58mm'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_facturacion_modo_modo_check'
                    AND conrelid = '"tecnolabo"."empresa_facturacion_modo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_facturacion_modo" ADD CONSTRAINT "empresa_facturacion_modo_modo_check" CHECK ((modo = ANY (ARRAY['sin_factura_fiscal'::text, 'sifen'::text, 'autoimpresor'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_facturacion_modo_pkey'
                    AND conrelid = '"tecnolabo"."empresa_facturacion_modo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_facturacion_modo" ADD CONSTRAINT "empresa_facturacion_modo_pkey" PRIMARY KEY (empresa_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_modulos_pkey'
                    AND conrelid = '"tecnolabo"."empresa_modulos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_modulos" ADD CONSTRAINT "empresa_modulos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_sifen_config_ambiente_check'
                    AND conrelid = '"tecnolabo"."empresa_sifen_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_sifen_config" ADD CONSTRAINT "empresa_sifen_config_ambiente_check" CHECK ((ambiente = ANY (ARRAY['test'::text, 'produccion'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_sifen_config_empresa_id_key'
                    AND conrelid = '"tecnolabo"."empresa_sifen_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_sifen_config" ADD CONSTRAINT "empresa_sifen_config_empresa_id_key" UNIQUE (empresa_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_sifen_config_kude_color_primario_fill_fmt_chk'
                    AND conrelid = '"tecnolabo"."empresa_sifen_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_sifen_config" ADD CONSTRAINT "empresa_sifen_config_kude_color_primario_fill_fmt_chk" CHECK (((kude_color_primario_fill IS NULL) OR (kude_color_primario_fill ~ '^#[0-9A-Fa-f]{6}$'::text)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_sifen_config_kude_color_primario_fmt_chk'
                    AND conrelid = '"tecnolabo"."empresa_sifen_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_sifen_config" ADD CONSTRAINT "empresa_sifen_config_kude_color_primario_fmt_chk" CHECK (((kude_color_primario IS NULL) OR (kude_color_primario ~ '^#[0-9A-Fa-f]{6}$'::text)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_sifen_config_pkey'
                    AND conrelid = '"tecnolabo"."empresa_sifen_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_sifen_config" ADD CONSTRAINT "empresa_sifen_config_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_sifen_config_sifen_plazo_cancelacion_horas_check'
                    AND conrelid = '"tecnolabo"."empresa_sifen_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_sifen_config" ADD CONSTRAINT "empresa_sifen_config_sifen_plazo_cancelacion_horas_check" CHECK (((sifen_plazo_cancelacion_horas >= 1) AND (sifen_plazo_cancelacion_horas <= 8760)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresas_pkey'
                    AND conrelid = '"tecnolabo"."empresas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresas" ADD CONSTRAINT "empresas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'entidades_bancarias_pkey'
                    AND conrelid = '"tecnolabo"."entidades_bancarias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."entidades_bancarias" ADD CONSTRAINT "entidades_bancarias_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_autoimpresor_condicion_check'
                    AND conrelid = '"tecnolabo"."factura_autoimpresor"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_autoimpresor" ADD CONSTRAINT "factura_autoimpresor_condicion_check" CHECK ((condicion = ANY (ARRAY['contado'::text, 'credito'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_autoimpresor_pkey'
                    AND conrelid = '"tecnolabo"."factura_autoimpresor"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_autoimpresor" ADD CONSTRAINT "factura_autoimpresor_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_correlativos_pkey'
                    AND conrelid = '"tecnolabo"."factura_correlativos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_correlativos" ADD CONSTRAINT "factura_correlativos_pkey" PRIMARY KEY (empresa_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_correlativos_ultimo_numero_check'
                    AND conrelid = '"tecnolabo"."factura_correlativos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_correlativos" ADD CONSTRAINT "factura_correlativos_ultimo_numero_check" CHECK ((ultimo_numero >= 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_estado_sifen_check'
                    AND conrelid = '"tecnolabo"."factura_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica" ADD CONSTRAINT "factura_electronica_estado_sifen_check" CHECK ((estado_sifen = ANY (ARRAY['borrador'::text, 'generado'::text, 'firmado'::text, 'enviado'::text, 'aprobado'::text, 'rechazado'::text, 'error_envio'::text, 'cancelado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_factura_id_key'
                    AND conrelid = '"tecnolabo"."factura_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica" ADD CONSTRAINT "factura_electronica_factura_id_key" UNIQUE (factura_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_pkey'
                    AND conrelid = '"tecnolabo"."factura_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica" ADD CONSTRAINT "factura_electronica_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_evento_pkey'
                    AND conrelid = '"tecnolabo"."factura_electronica_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica_evento" ADD CONSTRAINT "factura_electronica_evento_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_evento_tipo_check'
                    AND conrelid = '"tecnolabo"."factura_electronica_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica_evento" ADD CONSTRAINT "factura_electronica_evento_tipo_check" CHECK ((tipo = ANY (ARRAY['generacion'::text, 'envio'::text, 'respuesta'::text, 'error'::text, 'firma'::text, 'cancelacion'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_items_pkey'
                    AND conrelid = '"tecnolabo"."factura_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_items" ADD CONSTRAINT "factura_items_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'facturas_estado_check'
                    AND conrelid = '"tecnolabo"."facturas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."facturas" ADD CONSTRAINT "facturas_estado_check" CHECK ((estado = ANY (ARRAY['Pagado'::text, 'Pendiente'::text, 'Vencido'::text, 'Anulado'::text, 'Corregida NC'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'facturas_moneda_check'
                    AND conrelid = '"tecnolabo"."facturas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."facturas" ADD CONSTRAINT "facturas_moneda_check" CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'facturas_pkey'
                    AND conrelid = '"tecnolabo"."facturas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."facturas" ADD CONSTRAINT "facturas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'facturas_tipo_check'
                    AND conrelid = '"tecnolabo"."facturas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."facturas" ADD CONSTRAINT "facturas_tipo_check" CHECK ((tipo = ANY (ARRAY['contado'::text, 'credito'::text, 'suscripcion'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'gastos_pkey'
                    AND conrelid = '"tecnolabo"."gastos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."gastos" ADD CONSTRAINT "gastos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'gastos_tipo_check'
                    AND conrelid = '"tecnolabo"."gastos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."gastos" ADD CONSTRAINT "gastos_tipo_check" CHECK ((tipo = ANY (ARRAY['fijo'::text, 'variable'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'imports_audit_pkey'
                    AND conrelid = '"tecnolabo"."imports_audit"'::regclass) THEN
    ALTER TABLE "tecnolabo"."imports_audit" ADD CONSTRAINT "imports_audit_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_stock_ubicacion_pkey'
                    AND conrelid = '"tecnolabo"."inventario_stock_ubicacion"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_stock_ubicacion" ADD CONSTRAINT "inventario_stock_ubicacion_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_ubicaciones_pkey'
                    AND conrelid = '"tecnolabo"."inventario_ubicaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_ubicaciones" ADD CONSTRAINT "inventario_ubicaciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_ubicaciones_tipo_check'
                    AND conrelid = '"tecnolabo"."inventario_ubicaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_ubicaciones" ADD CONSTRAINT "inventario_ubicaciones_tipo_check" CHECK ((tipo = ANY (ARRAY['deposito'::text, 'salon'::text, 'pasillo'::text, 'gondola'::text, 'estante'::text, 'zona'::text, 'otro'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_calendarios_pkey'
                    AND conrelid = '"tecnolabo"."marketing_calendarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_calendarios" ADD CONSTRAINT "marketing_calendarios_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_marketing_comentarios_texto_non_empty'
                    AND conrelid = '"tecnolabo"."marketing_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_comentarios" ADD CONSTRAINT "chk_marketing_comentarios_texto_non_empty" CHECK ((length(TRIM(BOTH FROM comentario)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_comentarios_pkey'
                    AND conrelid = '"tecnolabo"."marketing_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_comentarios" ADD CONSTRAINT "marketing_comentarios_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_marketing_historial_campo_non_empty'
                    AND conrelid = '"tecnolabo"."marketing_historial_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_historial_estados" ADD CONSTRAINT "chk_marketing_historial_campo_non_empty" CHECK ((length(TRIM(BOTH FROM campo)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_historial_estados_pkey'
                    AND conrelid = '"tecnolabo"."marketing_historial_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_historial_estados" ADD CONSTRAINT "marketing_historial_estados_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_marketing_piezas_titulo_non_empty'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "chk_marketing_piezas_titulo_non_empty" CHECK ((length(TRIM(BOTH FROM titulo)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_estado_cliente_check'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_estado_cliente_check" CHECK ((estado_cliente = ANY (ARRAY['no_enviado'::text, 'enviado'::text, 'aprobado'::text, 'con_correcciones'::text, 'sin_respuesta'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_estado_produccion_check'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_estado_produccion_check" CHECK ((estado_produccion = ANY (ARRAY['por_hacer'::text, 'en_produccion'::text, 'revision_interna'::text, 'correccion_interna'::text, 'listo_para_enviar'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_estado_publicacion_check'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_estado_publicacion_check" CHECK ((estado_publicacion = ANY (ARRAY['pendiente'::text, 'programado'::text, 'publicado'::text, 'cancelado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_pkey'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_prioridad_check'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_prioridad_check" CHECK ((prioridad = ANY (ARRAY['baja'::text, 'media'::text, 'alta'::text, 'urgente'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_estado_check'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_proceso'::text, 'en_revision'::text, 'aprobado'::text, 'publicado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_pkey'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_prioridad_check'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_prioridad_check" CHECK (((prioridad IS NULL) OR (prioridad = ANY (ARRAY['baja'::text, 'media'::text, 'alta'::text, 'urgente'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_tipo_contenido_check'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_tipo_contenido_check" CHECK ((tipo_contenido = ANY (ARRAY['post'::text, 'reel'::text, 'historia'::text, 'anuncio'::text, 'otro'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'modulos_pkey'
                    AND conrelid = '"tecnolabo"."modulos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."modulos" ADD CONSTRAINT "modulos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'movimientos_inventario_origen_check'
                    AND conrelid = '"tecnolabo"."movimientos_inventario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."movimientos_inventario" ADD CONSTRAINT "movimientos_inventario_origen_check" CHECK ((origen = ANY (ARRAY['compra'::text, 'venta'::text, 'ajuste_manual'::text, 'inventario_inicial'::text, 'produccion'::text, 'devolucion_venta'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'movimientos_inventario_pkey'
                    AND conrelid = '"tecnolabo"."movimientos_inventario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."movimientos_inventario" ADD CONSTRAINT "movimientos_inventario_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'movimientos_inventario_tipo_check'
                    AND conrelid = '"tecnolabo"."movimientos_inventario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."movimientos_inventario" ADD CONSTRAINT "movimientos_inventario_tipo_check" CHECK ((tipo = ANY (ARRAY['ENTRADA'::text, 'SALIDA'::text, 'AJUSTE'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_estado_erp_check'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_estado_erp_check" CHECK ((estado_erp = ANY (ARRAY['borrador'::text, 'pendiente_envio_sifen'::text, 'aprobada'::text, 'rechazada'::text, 'error'::text, 'anulada_borrador'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_moneda_snapshot_check'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_moneda_snapshot_check" CHECK ((moneda_snapshot = ANY (ARRAY['GS'::text, 'USD'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_monto_check'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_monto_check" CHECK ((monto > (0)::numeric));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_motivo_len_check'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_motivo_len_check" CHECK (((length(TRIM(BOTH FROM motivo)) >= 5) AND (length(motivo) <= 2000)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_pkey'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_electronica_estado_sifen_check'
                    AND conrelid = '"tecnolabo"."nota_credito_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_electronica" ADD CONSTRAINT "nota_credito_electronica_estado_sifen_check" CHECK ((estado_sifen = ANY (ARRAY['sin_envio'::text, 'generado'::text, 'firmado'::text, 'enviado'::text, 'en_proceso'::text, 'aprobado'::text, 'rechazado'::text, 'error_envio'::text, 'cancelado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_electronica_nota_credito_id_key'
                    AND conrelid = '"tecnolabo"."nota_credito_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_electronica" ADD CONSTRAINT "nota_credito_electronica_nota_credito_id_key" UNIQUE (nota_credito_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_electronica_pkey'
                    AND conrelid = '"tecnolabo"."nota_credito_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_electronica" ADD CONSTRAINT "nota_credito_electronica_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_evento_pkey'
                    AND conrelid = '"tecnolabo"."nota_credito_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_evento" ADD CONSTRAINT "nota_credito_evento_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_evento_tipo_check'
                    AND conrelid = '"tecnolabo"."nota_credito_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_evento" ADD CONSTRAINT "nota_credito_evento_tipo_check" CHECK ((tipo_evento = ANY (ARRAY['creacion'::text, 'validacion'::text, 'rechazo_negocio'::text, 'cambio_estado_erp'::text, 'preparacion_sifen'::text, 'error'::text, 'observacion_operativa'::text, 'anulacion_borrador'::text, 'xml_generado'::text, 'xml_firmado'::text, 'enviado_set'::text, 'respuesta_set'::text, 'aprobado'::text, 'rechazado'::text, 'impacto_saldo_aplicado'::text, 'error_envio'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'notificaciones_pkey'
                    AND conrelid = '"tecnolabo"."notificaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."notificaciones" ADD CONSTRAINT "notificaciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'obligaciones_tributarias_catalogo_pkey'
                    AND conrelid = '"tecnolabo"."obligaciones_tributarias_catalogo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."obligaciones_tributarias_catalogo" ADD CONSTRAINT "obligaciones_tributarias_catalogo_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'obligaciones_tributarias_catalogo_slug_key'
                    AND conrelid = '"tecnolabo"."obligaciones_tributarias_catalogo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."obligaciones_tributarias_catalogo" ADD CONSTRAINT "obligaciones_tributarias_catalogo_slug_key" UNIQUE (slug);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'omnichannel_routes_pkey'
                    AND conrelid = '"tecnolabo"."omnichannel_routes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."omnichannel_routes" ADD CONSTRAINT "omnichannel_routes_pkey" PRIMARY KEY (meta_phone_number_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ordenes_compra_estado_check'
                    AND conrelid = '"tecnolabo"."ordenes_compra"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ordenes_compra" ADD CONSTRAINT "ordenes_compra_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'recibida_parcial'::text, 'recibida_total'::text, 'cancelada'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ordenes_compra_iva_tipo_check'
                    AND conrelid = '"tecnolabo"."ordenes_compra"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ordenes_compra" ADD CONSTRAINT "ordenes_compra_iva_tipo_check" CHECK ((iva_tipo = ANY (ARRAY['exenta'::text, '5'::text, '10'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ordenes_compra_moneda_check'
                    AND conrelid = '"tecnolabo"."ordenes_compra"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ordenes_compra" ADD CONSTRAINT "ordenes_compra_moneda_check" CHECK ((moneda = ANY (ARRAY['PYG'::text, 'USD'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ordenes_compra_pkey'
                    AND conrelid = '"tecnolabo"."ordenes_compra"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ordenes_compra" ADD CONSTRAINT "ordenes_compra_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ordenes_compra_tipo_pago_check'
                    AND conrelid = '"tecnolabo"."ordenes_compra"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ordenes_compra" ADD CONSTRAINT "ordenes_compra_tipo_pago_check" CHECK ((tipo_pago = ANY (ARRAY['contado'::text, 'credito'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pagos_metodo_pago_check'
                    AND conrelid = '"tecnolabo"."pagos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pagos" ADD CONSTRAINT "pagos_metodo_pago_check" CHECK ((metodo_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'cheque'::text, 'tarjeta'::text, 'otro'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pagos_pkey'
                    AND conrelid = '"tecnolabo"."pagos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pagos" ADD CONSTRAINT "pagos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pedidos_caja_estado_check'
                    AND conrelid = '"tecnolabo"."pedidos_caja"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pedidos_caja" ADD CONSTRAINT "pedidos_caja_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_caja'::text, 'facturado'::text, 'cancelado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pedidos_caja_pkey'
                    AND conrelid = '"tecnolabo"."pedidos_caja"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pedidos_caja" ADD CONSTRAINT "pedidos_caja_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'planes_estado_check'
                    AND conrelid = '"tecnolabo"."planes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."planes" ADD CONSTRAINT "planes_estado_check" CHECK ((estado = ANY (ARRAY['activo'::text, 'inactivo'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'planes_moneda_check'
                    AND conrelid = '"tecnolabo"."planes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."planes" ADD CONSTRAINT "planes_moneda_check" CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'planes_periodicidad_check'
                    AND conrelid = '"tecnolabo"."planes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."planes" ADD CONSTRAINT "planes_periodicidad_check" CHECK ((periodicidad = ANY (ARRAY['mensual'::text, 'anual'::text, 'unico'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'planes_pkey'
                    AND conrelid = '"tecnolabo"."planes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."planes" ADD CONSTRAINT "planes_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'presupuesto_items_pkey'
                    AND conrelid = '"tecnolabo"."presupuesto_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."presupuesto_items" ADD CONSTRAINT "presupuesto_items_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'presupuestos_estado_check'
                    AND conrelid = '"tecnolabo"."presupuestos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."presupuestos" ADD CONSTRAINT "presupuestos_estado_check" CHECK ((estado = ANY (ARRAY['creado'::text, 'enviado'::text, 'aprobado'::text, 'rechazado'::text, 'convertido'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'presupuestos_pkey'
                    AND conrelid = '"tecnolabo"."presupuestos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."presupuestos" ADD CONSTRAINT "presupuestos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'produccion_items_pkey'
                    AND conrelid = '"tecnolabo"."produccion_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."produccion_items" ADD CONSTRAINT "produccion_items_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producciones_pkey'
                    AND conrelid = '"tecnolabo"."producciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producciones" ADD CONSTRAINT "producciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_categorias_pkey'
                    AND conrelid = '"tecnolabo"."producto_categorias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_categorias" ADD CONSTRAINT "producto_categorias_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_presentaciones_cantidad_base_check'
                    AND conrelid = '"tecnolabo"."producto_presentaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_presentaciones" ADD CONSTRAINT "producto_presentaciones_cantidad_base_check" CHECK ((cantidad_base > (0)::numeric));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_presentaciones_pkey'
                    AND conrelid = '"tecnolabo"."producto_presentaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_presentaciones" ADD CONSTRAINT "producto_presentaciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_presentaciones_precio_venta_check'
                    AND conrelid = '"tecnolabo"."producto_presentaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_presentaciones" ADD CONSTRAINT "producto_presentaciones_precio_venta_check" CHECK (((precio_venta IS NULL) OR (precio_venta >= (0)::numeric)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_discount_type_chk'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_discount_type_chk" CHECK (((discount_type IS NULL) OR (discount_type = ANY (ARRAY['percentage'::text, 'fixed'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_factor_compra_receta_check'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_factor_compra_receta_check" CHECK ((factor_compra_receta > (0)::numeric));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_metodo_valuacion_check'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_metodo_valuacion_check" CHECK ((metodo_valuacion = ANY (ARRAY['CPP'::text, 'FIFO'::text, 'LIFO'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_modo_receta_check'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_modo_receta_check" CHECK ((modo_receta = ANY (ARRAY['preparado_al_vender'::text, 'produccion_previa'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_pkey'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_tiempo_prep_minutos_check'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_tiempo_prep_minutos_check" CHECK ((tiempo_prep_minutos >= 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_codigo_secuencia_pkey'
                    AND conrelid = '"tecnolabo"."productos_codigo_secuencia"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos_codigo_secuencia" ADD CONSTRAINT "productos_codigo_secuencia_pkey" PRIMARY KEY (empresa_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_categoria_rel_pkey'
                    AND conrelid = '"tecnolabo"."proveedor_categoria_rel"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_categoria_rel" ADD CONSTRAINT "proveedor_categoria_rel_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_categoria_rel_proveedor_id_categoria_id_key'
                    AND conrelid = '"tecnolabo"."proveedor_categoria_rel"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_categoria_rel" ADD CONSTRAINT "proveedor_categoria_rel_proveedor_id_categoria_id_key" UNIQUE (proveedor_id, categoria_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_categorias_pkey'
                    AND conrelid = '"tecnolabo"."proveedor_categorias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_categorias" ADD CONSTRAINT "proveedor_categorias_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_productos_empresa_id_producto_id_proveedor_id_key'
                    AND conrelid = '"tecnolabo"."proveedor_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_productos" ADD CONSTRAINT "proveedor_productos_empresa_id_producto_id_proveedor_id_key" UNIQUE (empresa_id, producto_id, proveedor_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_productos_pkey'
                    AND conrelid = '"tecnolabo"."proveedor_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_productos" ADD CONSTRAINT "proveedor_productos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedores_condicion_pago_check'
                    AND conrelid = '"tecnolabo"."proveedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedores" ADD CONSTRAINT "proveedores_condicion_pago_check" CHECK (((condicion_pago IS NULL) OR (condicion_pago = ANY (ARRAY['contado'::text, 'credito'::text, 'mixto'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedores_estado_check'
                    AND conrelid = '"tecnolabo"."proveedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedores" ADD CONSTRAINT "proveedores_estado_check" CHECK ((estado = ANY (ARRAY['activo'::text, 'inactivo'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedores_moneda_preferida_check'
                    AND conrelid = '"tecnolabo"."proveedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedores" ADD CONSTRAINT "proveedores_moneda_preferida_check" CHECK (((moneda_preferida IS NULL) OR (moneda_preferida = ANY (ARRAY['GS'::text, 'USD'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedores_pkey'
                    AND conrelid = '"tecnolabo"."proveedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedores" ADD CONSTRAINT "proveedores_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_archivos_nombre_non_empty'
                    AND conrelid = '"tecnolabo"."proyecto_archivos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_archivos" ADD CONSTRAINT "chk_proyecto_archivos_nombre_non_empty" CHECK ((length(TRIM(BOTH FROM nombre)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_archivos_empresa_id_storage_bucket_storage_path_key'
                    AND conrelid = '"tecnolabo"."proyecto_archivos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_archivos" ADD CONSTRAINT "proyecto_archivos_empresa_id_storage_bucket_storage_path_key" UNIQUE (empresa_id, storage_bucket, storage_path);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_archivos_pkey'
                    AND conrelid = '"tecnolabo"."proyecto_archivos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_archivos" ADD CONSTRAINT "proyecto_archivos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_comentarios_texto_non_empty'
                    AND conrelid = '"tecnolabo"."proyecto_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_comentarios" ADD CONSTRAINT "chk_proyecto_comentarios_texto_non_empty" CHECK ((length(TRIM(BOTH FROM comentario)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_comentarios_pkey'
                    AND conrelid = '"tecnolabo"."proyecto_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_comentarios" ADD CONSTRAINT "proyecto_comentarios_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estado_historial_pkey'
                    AND conrelid = '"tecnolabo"."proyecto_estado_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estado_historial" ADD CONSTRAINT "proyecto_estado_historial_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_estados_codigo_non_empty'
                    AND conrelid = '"tecnolabo"."proyecto_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estados" ADD CONSTRAINT "chk_proyecto_estados_codigo_non_empty" CHECK ((length(TRIM(BOTH FROM codigo)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estados_empresa_id_codigo_key'
                    AND conrelid = '"tecnolabo"."proyecto_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estados" ADD CONSTRAINT "proyecto_estados_empresa_id_codigo_key" UNIQUE (empresa_id, codigo);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estados_pkey'
                    AND conrelid = '"tecnolabo"."proyecto_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estados" ADD CONSTRAINT "proyecto_estados_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estados_tipo_sla_check'
                    AND conrelid = '"tecnolabo"."proyecto_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estados" ADD CONSTRAINT "proyecto_estados_tipo_sla_check" CHECK ((tipo_sla = ANY (ARRAY['interno'::text, 'cliente'::text, 'pausado'::text, 'final'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_prioridades_bg_color'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "chk_proyecto_prioridades_bg_color" CHECK (((bg_color IS NULL) OR (bg_color ~ '^#[0-9A-Fa-f]{6}$'::text)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_prioridades_border_color'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "chk_proyecto_prioridades_border_color" CHECK (((border_color IS NULL) OR (border_color ~ '^#[0-9A-Fa-f]{6}$'::text)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_prioridades_codigo'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "chk_proyecto_prioridades_codigo" CHECK ((codigo = ANY (ARRAY['baja'::text, 'normal'::text, 'alta'::text, 'urgente'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_prioridades_color'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "chk_proyecto_prioridades_color" CHECK (((color IS NULL) OR (color ~ '^#[0-9A-Fa-f]{6}$'::text)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_prioridades_nombre_non_empty'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "chk_proyecto_prioridades_nombre_non_empty" CHECK ((length(TRIM(BOTH FROM nombre)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_prioridades_text_color'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "chk_proyecto_prioridades_text_color" CHECK (((text_color IS NULL) OR (text_color ~ '^#[0-9A-Fa-f]{6}$'::text)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_prioridades_config_empresa_id_codigo_key'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "proyecto_prioridades_config_empresa_id_codigo_key" UNIQUE (empresa_id, codigo);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_prioridades_config_pkey'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "proyecto_prioridades_config_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_tareas_titulo_non_empty'
                    AND conrelid = '"tecnolabo"."proyecto_tareas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tareas" ADD CONSTRAINT "chk_proyecto_tareas_titulo_non_empty" CHECK ((length(TRIM(BOTH FROM titulo)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tareas_estado_check'
                    AND conrelid = '"tecnolabo"."proyecto_tareas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tareas" ADD CONSTRAINT "proyecto_tareas_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_proceso'::text, 'completada'::text, 'bloqueada'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tareas_pkey'
                    AND conrelid = '"tecnolabo"."proyecto_tareas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tareas" ADD CONSTRAINT "proyecto_tareas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyecto_tipos_codigo_non_empty'
                    AND conrelid = '"tecnolabo"."proyecto_tipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tipos" ADD CONSTRAINT "chk_proyecto_tipos_codigo_non_empty" CHECK ((length(TRIM(BOTH FROM codigo)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tipos_empresa_id_codigo_key'
                    AND conrelid = '"tecnolabo"."proyecto_tipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tipos" ADD CONSTRAINT "proyecto_tipos_empresa_id_codigo_key" UNIQUE (empresa_id, codigo);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tipos_pkey'
                    AND conrelid = '"tecnolabo"."proyecto_tipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tipos" ADD CONSTRAINT "proyecto_tipos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_proyectos_titulo_non_empty'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "chk_proyectos_titulo_non_empty" CHECK ((length(TRIM(BOTH FROM titulo)) > 0));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_pkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_prioridad_check'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_prioridad_check" CHECK ((prioridad = ANY (ARRAY['baja'::text, 'normal'::text, 'alta'::text, 'urgente'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'receta_items_cantidad_check'
                    AND conrelid = '"tecnolabo"."receta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."receta_items" ADD CONSTRAINT "receta_items_cantidad_check" CHECK ((cantidad > (0)::numeric));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'receta_items_merma_pct_check'
                    AND conrelid = '"tecnolabo"."receta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."receta_items" ADD CONSTRAINT "receta_items_merma_pct_check" CHECK (((merma_pct >= (0)::numeric) AND (merma_pct < (1)::numeric)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'receta_items_pkey'
                    AND conrelid = '"tecnolabo"."receta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."receta_items" ADD CONSTRAINT "receta_items_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'receta_items_receta_id_insumo_producto_id_key'
                    AND conrelid = '"tecnolabo"."receta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."receta_items" ADD CONSTRAINT "receta_items_receta_id_insumo_producto_id_key" UNIQUE (receta_id, insumo_producto_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'recetas_empresa_id_producto_id_key'
                    AND conrelid = '"tecnolabo"."recetas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."recetas" ADD CONSTRAINT "recetas_empresa_id_producto_id_key" UNIQUE (empresa_id, producto_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'recetas_pkey'
                    AND conrelid = '"tecnolabo"."recetas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."recetas" ADD CONSTRAINT "recetas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'recetas_rendimiento_cantidad_check'
                    AND conrelid = '"tecnolabo"."recetas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."recetas" ADD CONSTRAINT "recetas_rendimiento_cantidad_check" CHECK ((rendimiento_cantidad > (0)::numeric));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'recibos_dinero_origen_check'
                    AND conrelid = '"tecnolabo"."recibos_dinero"'::regclass) THEN
    ALTER TABLE "tecnolabo"."recibos_dinero" ADD CONSTRAINT "recibos_dinero_origen_check" CHECK ((origen = ANY (ARRAY['venta_contado'::text, 'cobro_cxc'::text, 'manual'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'recibos_dinero_pkey'
                    AND conrelid = '"tecnolabo"."recibos_dinero"'::regclass) THEN
    ALTER TABLE "tecnolabo"."recibos_dinero" ADD CONSTRAINT "recibos_dinero_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sifen_jobs_estado_check'
                    AND conrelid = '"tecnolabo"."sifen_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sifen_jobs" ADD CONSTRAINT "sifen_jobs_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'procesando'::text, 'aprobado'::text, 'rechazado'::text, 'error'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sifen_jobs_etapa_check'
                    AND conrelid = '"tecnolabo"."sifen_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sifen_jobs" ADD CONSTRAINT "sifen_jobs_etapa_check" CHECK (((etapa IS NULL) OR (etapa = ANY (ARRAY['xml'::text, 'firmar'::text, 'enviar'::text, 'consulta_lote'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sifen_jobs_origen_check'
                    AND conrelid = '"tecnolabo"."sifen_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sifen_jobs" ADD CONSTRAINT "sifen_jobs_origen_check" CHECK ((origen = ANY (ARRAY['auto_venta'::text, 'reintento_manual'::text, 'manual_admin'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sifen_jobs_pkey'
                    AND conrelid = '"tecnolabo"."sifen_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sifen_jobs" ADD CONSTRAINT "sifen_jobs_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sifen_jobs_tipo_error_check'
                    AND conrelid = '"tecnolabo"."sifen_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sifen_jobs" ADD CONSTRAINT "sifen_jobs_tipo_error_check" CHECK (((tipo_error IS NULL) OR (tipo_error = ANY (ARRAY['set_rechazo'::text, 'fiscal'::text, 'firma'::text, 'config'::text, 'red'::text, 'http_5xx'::text, 'storage'::text, 'inesperado'::text, 'set_timeout'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_conversaciones_estado_check'
                    AND conrelid = '"tecnolabo"."sorteo_conversaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_conversaciones" ADD CONSTRAINT "sorteo_conversaciones_estado_check" CHECK ((estado = ANY (ARRAY['new_lead'::text, 'awaiting_ticket_selection'::text, 'awaiting_customer_data'::text, 'awaiting_payment'::text, 'awaiting_receipt'::text, 'receipt_under_review'::text, 'paid_confirmed'::text, 'human_handoff'::text, 'cancelled'::text, 'closed_no_response'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_conversaciones_pkey'
                    AND conrelid = '"tecnolabo"."sorteo_conversaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_conversaciones" ADD CONSTRAINT "sorteo_conversaciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_cupones_pkey'
                    AND conrelid = '"tecnolabo"."sorteo_cupones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_cupones" ADD CONSTRAINT "sorteo_cupones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_cupones_sorteo_id_numero_cupon_key'
                    AND conrelid = '"tecnolabo"."sorteo_cupones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_cupones" ADD CONSTRAINT "sorteo_cupones_sorteo_id_numero_cupon_key" UNIQUE (sorteo_id, numero_cupon);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_estado_pago_check'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_estado_pago_check" CHECK ((estado_pago = ANY (ARRAY['pendiente'::text, 'pendiente_revision'::text, 'confirmado'::text, 'rechazado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_moneda_check'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_moneda_check" CHECK ((moneda = 'PYG'::text));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_pago_metodo_check'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_pago_metodo_check" CHECK (((pago_metodo IS NULL) OR (pago_metodo = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'tarjeta'::text, 'otro'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_pkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_precio_fuente_check'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_precio_fuente_check" CHECK (((precio_fuente IS NULL) OR (precio_fuente = ANY (ARRAY['lista'::text, 'promo'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_venta_canal_check'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_venta_canal_check" CHECK (((venta_canal IS NULL) OR (venta_canal = ANY (ARRAY['remote'::text, 'local'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_venta_origen_check'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_venta_origen_check" CHECK (((venta_origen IS NULL) OR (venta_origen = ANY (ARRAY['whatsapp_flow'::text, 'erp_manual'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedor_clicks_pkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedor_clicks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedor_clicks" ADD CONSTRAINT "sorteo_revendedor_clicks_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedores_pkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedores" ADD CONSTRAINT "sorteo_revendedores_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_ticket_deliveries_delivery_mode_check'
                    AND conrelid = '"tecnolabo"."sorteo_ticket_deliveries"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ADD CONSTRAINT "sorteo_ticket_deliveries_delivery_mode_check" CHECK ((delivery_mode = ANY (ARRAY['text_only'::text, 'text_and_image'::text, 'image_only'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_ticket_deliveries_pkey'
                    AND conrelid = '"tecnolabo"."sorteo_ticket_deliveries"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ADD CONSTRAINT "sorteo_ticket_deliveries_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_ticket_deliveries_status_check'
                    AND conrelid = '"tecnolabo"."sorteo_ticket_deliveries"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ADD CONSTRAINT "sorteo_ticket_deliveries_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'generated'::text, 'sent'::text, 'error'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteos_coupon_number_mode_check'
                    AND conrelid = '"tecnolabo"."sorteos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteos" ADD CONSTRAINT "sorteos_coupon_number_mode_check" CHECK (((coupon_number_mode IS NULL) OR (coupon_number_mode = ANY (ARRAY['correlative'::text, 'random'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteos_estado_check'
                    AND conrelid = '"tecnolabo"."sorteos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteos" ADD CONSTRAINT "sorteos_estado_check" CHECK ((estado = ANY (ARRAY['activo'::text, 'pausado'::text, 'cerrado'::text, 'finalizado'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteos_pkey'
                    AND conrelid = '"tecnolabo"."sorteos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteos" ADD CONSTRAINT "sorteos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteos_ticket_delivery_mode_check'
                    AND conrelid = '"tecnolabo"."sorteos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteos" ADD CONSTRAINT "sorteos_ticket_delivery_mode_check" CHECK ((ticket_delivery_mode = ANY (ARRAY['text_only'::text, 'text_and_image'::text, 'image_only'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_dia_facturacion_check'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_dia_facturacion_check" CHECK (((dia_facturacion >= 1) AND (dia_facturacion <= 28)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_dia_vencimiento_check'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_dia_vencimiento_check" CHECK (((dia_vencimiento >= 1) AND (dia_vencimiento <= 31)));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_estado_check'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_estado_check" CHECK ((estado = ANY (ARRAY['activa'::text, 'pausada'::text, 'cancelada'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_moneda_check'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_moneda_check" CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_pkey'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tipificaciones_pkey'
                    AND conrelid = '"tecnolabo"."tipificaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."tipificaciones" ADD CONSTRAINT "tipificaciones_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tipificaciones_resultado_check'
                    AND conrelid = '"tecnolabo"."tipificaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."tipificaciones" ADD CONSTRAINT "tipificaciones_resultado_check" CHECK ((resultado = ANY (ARRAY['Pendiente'::text, 'Resuelto'::text, 'Escalar'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tipificaciones_tipo_gestion_check'
                    AND conrelid = '"tecnolabo"."tipificaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."tipificaciones" ADD CONSTRAINT "tipificaciones_tipo_gestion_check" CHECK ((tipo_gestion = ANY (ARRAY['Consulta'::text, 'Reclamo'::text, 'Seguimiento'::text, 'Promesa de pago'::text, 'Soporte técnico'::text, 'Cambio plan'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_dashboard_views_pkey'
                    AND conrelid = '"tecnolabo"."usuario_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_dashboard_views" ADD CONSTRAINT "usuario_dashboard_views_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_dashboard_views_usuario_id_dashboard_view_id_key'
                    AND conrelid = '"tecnolabo"."usuario_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_dashboard_views" ADD CONSTRAINT "usuario_dashboard_views_usuario_id_dashboard_view_id_key" UNIQUE (usuario_id, dashboard_view_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_modulos_pkey'
                    AND conrelid = '"tecnolabo"."usuario_modulos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_modulos" ADD CONSTRAINT "usuario_modulos_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_modulos_usuario_id_modulo_id_key'
                    AND conrelid = '"tecnolabo"."usuario_modulos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_modulos" ADD CONSTRAINT "usuario_modulos_usuario_id_modulo_id_key" UNIQUE (usuario_id, modulo_id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_area_check'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_area_check" CHECK (((area IS NULL) OR (area = ANY (ARRAY['ventas'::text, 'soporte'::text, 'finanzas'::text, 'operaciones'::text, 'administracion'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_email_key'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_email_key" UNIQUE (email);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_estado_check'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_estado_check" CHECK ((estado = ANY (ARRAY['activo'::text, 'inactivo'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_pkey'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_porcentaje_comision_check'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_porcentaje_comision_check" CHECK (((porcentaje_comision IS NULL) OR ((porcentaje_comision >= (0)::numeric) AND (porcentaje_comision <= (100)::numeric))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_tipo_contrato_check'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_tipo_contrato_check" CHECK (((tipo_contrato IS NULL) OR (tipo_contrato = ANY (ARRAY['salario'::text, 'comision'::text, 'mixto'::text, 'prestador_servicio'::text]))));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_estado_check'
                    AND conrelid = '"tecnolabo"."ventas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas" ADD CONSTRAINT "ventas_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'completada'::text, 'anulada'::text, 'parcialmente_devuelta'::text, 'devuelta_total'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_metodo_pago_chk'
                    AND conrelid = '"tecnolabo"."ventas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas" ADD CONSTRAINT "ventas_metodo_pago_chk" CHECK ((metodo_pago = ANY (ARRAY['efectivo'::text, 'tarjeta'::text, 'transferencia'::text, 'mixto'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_moneda_check'
                    AND conrelid = '"tecnolabo"."ventas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas" ADD CONSTRAINT "ventas_moneda_check" CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_pkey'
                    AND conrelid = '"tecnolabo"."ventas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas" ADD CONSTRAINT "ventas_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_tipo_venta_check'
                    AND conrelid = '"tecnolabo"."ventas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas" ADD CONSTRAINT "ventas_tipo_venta_check" CHECK ((tipo_venta = ANY (ARRAY['CONTADO'::text, 'CREDITO'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_items_pkey'
                    AND conrelid = '"tecnolabo"."ventas_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_items" ADD CONSTRAINT "ventas_items_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_items_tipo_iva_check'
                    AND conrelid = '"tecnolabo"."ventas_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_items" ADD CONSTRAINT "ventas_items_tipo_iva_check" CHECK ((tipo_iva = ANY (ARRAY['EXENTA'::text, '5%'::text, '10%'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_items_tipo_precio_check'
                    AND conrelid = '"tecnolabo"."ventas_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_items" ADD CONSTRAINT "ventas_items_tipo_precio_check" CHECK ((tipo_precio = ANY (ARRAY['minorista'::text, 'mayorista'::text, 'distribuidor'::text, 'costo'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_pagos_detalle_metodo_pago_check'
                    AND conrelid = '"tecnolabo"."ventas_pagos_detalle"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_pagos_detalle" ADD CONSTRAINT "ventas_pagos_detalle_metodo_pago_check" CHECK ((metodo_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'tarjeta'::text, 'qr'::text, 'billetera'::text, 'otro'::text])));
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_pagos_detalle_pkey'
                    AND conrelid = '"tecnolabo"."ventas_pagos_detalle"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_pagos_detalle" ADD CONSTRAINT "ventas_pagos_detalle_pkey" PRIMARY KEY (id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'vpd_conciliacion_estado_check'
                    AND conrelid = '"tecnolabo"."ventas_pagos_detalle"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_pagos_detalle" ADD CONSTRAINT "vpd_conciliacion_estado_check" CHECK ((conciliacion_estado = ANY (ARRAY['pendiente'::text, 'aprobado'::text, 'rechazado'::text])));
  END IF;
END $mig$;

-- ── FOREIGN KEYS (todas resueltas dentro de `tecnolabo`, salvo auth.users) ───

DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'caja_movimientos_caja_fk'
                    AND conrelid = '"tecnolabo"."caja_movimientos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."caja_movimientos" ADD CONSTRAINT "caja_movimientos_caja_fk" FOREIGN KEY (caja_id) REFERENCES tecnolabo.cajas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'categorias_productos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."categorias_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."categorias_productos" ADD CONSTRAINT "categorias_productos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'categorias_productos_parent_id_fkey'
                    AND conrelid = '"tecnolabo"."categorias_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."categorias_productos" ADD CONSTRAINT "categorias_productos_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES tecnolabo.categorias_productos(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_agents_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_agents" ADD CONSTRAINT "chat_agents_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_agents_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_agents" ADD CONSTRAINT "chat_agents_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_agents_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_agents" ADD CONSTRAINT "chat_agents_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_events_campaign_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_events" ADD CONSTRAINT "chat_campaign_events_campaign_id_fkey" FOREIGN KEY (campaign_id) REFERENCES tecnolabo.chat_campaigns(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_events_recipient_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_events" ADD CONSTRAINT "chat_campaign_events_recipient_id_fkey" FOREIGN KEY (recipient_id) REFERENCES tecnolabo.chat_campaign_recipients(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_jobs_campaign_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_jobs" ADD CONSTRAINT "chat_campaign_jobs_campaign_id_fkey" FOREIGN KEY (campaign_id) REFERENCES tecnolabo.chat_campaigns(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_recipients_campaign_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_recipients"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_recipients" ADD CONSTRAINT "chat_campaign_recipients_campaign_id_fkey" FOREIGN KEY (campaign_id) REFERENCES tecnolabo.chat_campaigns(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaign_templates_channel_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaign_templates"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaign_templates" ADD CONSTRAINT "chat_campaign_templates_channel_id_fkey" FOREIGN KEY (channel_id) REFERENCES tecnolabo.chat_channels(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaigns_channel_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaigns"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaigns" ADD CONSTRAINT "chat_campaigns_channel_id_fkey" FOREIGN KEY (channel_id) REFERENCES tecnolabo.chat_channels(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaigns_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaigns"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaigns" ADD CONSTRAINT "chat_campaigns_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_campaigns_template_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_campaigns"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_campaigns" ADD CONSTRAINT "chat_campaigns_template_id_fkey" FOREIGN KEY (template_id) REFERENCES tecnolabo.chat_campaign_templates(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channel_quick_replies_channel_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_channel_quick_replies"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channel_quick_replies" ADD CONSTRAINT "chat_channel_quick_replies_channel_id_fkey" FOREIGN KEY (channel_id) REFERENCES tecnolabo.chat_channels(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_channels_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_channels" ADD CONSTRAINT "chat_channels_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_comprobante_validaciones_channel_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_comprobante_validaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ADD CONSTRAINT "chat_comprobante_validaciones_channel_id_fkey" FOREIGN KEY (channel_id) REFERENCES tecnolabo.chat_channels(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_comprobante_validaciones_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_comprobante_validaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ADD CONSTRAINT "chat_comprobante_validaciones_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_comprobante_validaciones_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_comprobante_validaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ADD CONSTRAINT "chat_comprobante_validaciones_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_comprobante_validaciones_flow_session_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_comprobante_validaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ADD CONSTRAINT "chat_comprobante_validaciones_flow_session_id_fkey" FOREIGN KEY (flow_session_id) REFERENCES tecnolabo.chat_flow_sessions(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_comprobante_validaciones_sorteo_entrada_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_comprobante_validaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ADD CONSTRAINT "chat_comprobante_validaciones_sorteo_entrada_id_fkey" FOREIGN KEY (sorteo_entrada_id) REFERENCES tecnolabo.sorteo_entradas(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_contacts_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_contacts"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_contacts" ADD CONSTRAINT "chat_contacts_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_contacts_crm_prospecto_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_contacts"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_contacts" ADD CONSTRAINT "chat_contacts_crm_prospecto_id_fkey" FOREIGN KEY (crm_prospecto_id) REFERENCES tecnolabo.crm_prospectos(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_contacts_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_contacts"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_contacts" ADD CONSTRAINT "chat_contacts_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversation_closures_closure_state_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversation_closures"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversation_closures" ADD CONSTRAINT "chat_conversation_closures_closure_state_id_fkey" FOREIGN KEY (closure_state_id) REFERENCES tecnolabo.chat_queue_closure_states(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversation_closures_closure_substate_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversation_closures"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversation_closures" ADD CONSTRAINT "chat_conversation_closures_closure_substate_id_fkey" FOREIGN KEY (closure_substate_id) REFERENCES tecnolabo.chat_queue_closure_substates(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversation_closures_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversation_closures"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversation_closures" ADD CONSTRAINT "chat_conversation_closures_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversation_closures_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversation_closures"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversation_closures" ADD CONSTRAINT "chat_conversation_closures_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_active_flow_session_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_active_flow_session_id_fkey" FOREIGN KEY (active_flow_session_id) REFERENCES tecnolabo.chat_flow_sessions(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_assigned_agent_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_assigned_agent_id_fkey" FOREIGN KEY (assigned_agent_id) REFERENCES tecnolabo.chat_agents(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_channel_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_channel_id_fkey" FOREIGN KEY (channel_id) REFERENCES tecnolabo.chat_channels(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_contact_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_contact_id_fkey" FOREIGN KEY (contact_id) REFERENCES tecnolabo.chat_contacts(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_first_revendedor_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_first_revendedor_id_fkey" FOREIGN KEY (first_revendedor_id) REFERENCES tecnolabo.sorteo_revendedores(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_conversations_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_conversations"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_conversations" ADD CONSTRAINT "chat_conversations_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_empresa_operator_roles_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_empresa_operator_roles"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_empresa_operator_roles" ADD CONSTRAINT "chat_empresa_operator_roles_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_data_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_data"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_data" ADD CONSTRAINT "chat_flow_data_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_data_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_data"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_data" ADD CONSTRAINT "chat_flow_data_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_data_flow_session_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_data"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_data" ADD CONSTRAINT "chat_flow_data_flow_session_id_fkey" FOREIGN KEY (flow_session_id) REFERENCES tecnolabo.chat_flow_sessions(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_events_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_events" ADD CONSTRAINT "chat_flow_events_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_events_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_events" ADD CONSTRAINT "chat_flow_events_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_events_flow_session_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_events" ADD CONSTRAINT "chat_flow_events_flow_session_id_fkey" FOREIGN KEY (flow_session_id) REFERENCES tecnolabo.chat_flow_sessions(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_events_selected_option_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_events" ADD CONSTRAINT "chat_flow_events_selected_option_id_fkey" FOREIGN KEY (selected_option_id) REFERENCES tecnolabo.chat_flow_options(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_node_blocks_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_node_blocks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_node_blocks" ADD CONSTRAINT "chat_flow_node_blocks_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_node_blocks_node_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_node_blocks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_node_blocks" ADD CONSTRAINT "chat_flow_node_blocks_node_id_fkey" FOREIGN KEY (node_id) REFERENCES tecnolabo.chat_flow_nodes(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_nodes_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_nodes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_nodes" ADD CONSTRAINT "chat_flow_nodes_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_options_node_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_options"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_options" ADD CONSTRAINT "chat_flow_options_node_id_fkey" FOREIGN KEY (node_id) REFERENCES tecnolabo.chat_flow_nodes(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cfr_rules_flow_fk'
                    AND conrelid = '"tecnolabo"."chat_flow_recontact_rules"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_recontact_rules" ADD CONSTRAINT "cfr_rules_flow_fk" FOREIGN KEY (empresa_id, flow_code) REFERENCES tecnolabo.chat_flows(empresa_id, flow_code) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_recontact_runs_rule_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_recontact_runs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_recontact_runs" ADD CONSTRAINT "chat_flow_recontact_runs_rule_id_fkey" FOREIGN KEY (rule_id) REFERENCES tecnolabo.chat_flow_recontact_rules(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_sessions_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_sessions"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_sessions" ADD CONSTRAINT "chat_flow_sessions_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_sessions_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_sessions"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_sessions" ADD CONSTRAINT "chat_flow_sessions_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flow_sessions_revendedor_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flow_sessions"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flow_sessions" ADD CONSTRAINT "chat_flow_sessions_revendedor_id_fkey" FOREIGN KEY (revendedor_id) REFERENCES tecnolabo.sorteo_revendedores(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flows_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flows"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flows" ADD CONSTRAINT "chat_flows_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_flows_sorteo_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_flows"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_flows" ADD CONSTRAINT "chat_flows_sorteo_id_fkey" FOREIGN KEY (sorteo_id) REFERENCES tecnolabo.sorteos(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_messages_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_messages"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_messages" ADD CONSTRAINT "chat_messages_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_messages_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_messages"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_messages" ADD CONSTRAINT "chat_messages_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_channels_channel_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queue_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_channels" ADD CONSTRAINT "chat_queue_channels_channel_id_fkey" FOREIGN KEY (channel_id) REFERENCES tecnolabo.chat_channels(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_channels_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queue_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_channels" ADD CONSTRAINT "chat_queue_channels_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_channels_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queue_channels"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_channels" ADD CONSTRAINT "chat_queue_channels_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_closure_states_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queue_closure_states"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_closure_states" ADD CONSTRAINT "chat_queue_closure_states_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_closure_substates_closure_state_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queue_closure_substates"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_closure_substates" ADD CONSTRAINT "chat_queue_closure_substates_closure_state_id_fkey" FOREIGN KEY (closure_state_id) REFERENCES tecnolabo.chat_queue_closure_states(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_supervisors_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queue_supervisors"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_supervisors" ADD CONSTRAINT "chat_queue_supervisors_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queue_supervisors_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queue_supervisors"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queue_supervisors" ADD CONSTRAINT "chat_queue_supervisors_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_queues_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_queues"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_queues" ADD CONSTRAINT "chat_queues_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_routing_events_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_routing_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_routing_events" ADD CONSTRAINT "chat_routing_events_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_routing_events_queue_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_routing_events"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_routing_events" ADD CONSTRAINT "chat_routing_events_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES tecnolabo.chat_queues(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_supervisor_agents_agent_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_supervisor_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_supervisor_agents" ADD CONSTRAINT "chat_supervisor_agents_agent_usuario_id_fkey" FOREIGN KEY (agent_usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_supervisor_agents_supervisor_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_supervisor_agents"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_supervisor_agents" ADD CONSTRAINT "chat_supervisor_agents_supervisor_usuario_id_fkey" FOREIGN KEY (supervisor_usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_usuario_omnicanal_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_usuario_omnicanal"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_usuario_omnicanal" ADD CONSTRAINT "chat_usuario_omnicanal_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chat_usuario_omnicanal_work_schedule_id_fkey'
                    AND conrelid = '"tecnolabo"."chat_usuario_omnicanal"'::regclass) THEN
    ALTER TABLE "tecnolabo"."chat_usuario_omnicanal" ADD CONSTRAINT "chat_usuario_omnicanal_work_schedule_id_fkey" FOREIGN KEY (work_schedule_id) REFERENCES tecnolabo.chat_omnicanal_work_schedules(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_historial_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_historial" ADD CONSTRAINT "cliente_historial_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_historial_creado_por_auth_user_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_historial" ADD CONSTRAINT "cliente_historial_creado_por_auth_user_id_fkey" FOREIGN KEY (creado_por_auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_historial_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_historial" ADD CONSTRAINT "cliente_historial_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_obligaciones_tributarias_cliente_perfil_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_obligaciones_tributarias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_obligaciones_tributarias" ADD CONSTRAINT "cliente_obligaciones_tributarias_cliente_perfil_id_fkey" FOREIGN KEY (cliente_perfil_id) REFERENCES tecnolabo.cliente_perfil_tributario(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_obligaciones_tributarias_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_obligaciones_tributarias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_obligaciones_tributarias" ADD CONSTRAINT "cliente_obligaciones_tributarias_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_obligaciones_tributarias_obligacion_catalogo_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_obligaciones_tributarias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_obligaciones_tributarias" ADD CONSTRAINT "cliente_obligaciones_tributarias_obligacion_catalogo_id_fkey" FOREIGN KEY (obligacion_catalogo_id) REFERENCES tecnolabo.obligaciones_tributarias_catalogo(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_perfil_tributario_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_perfil_tributario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_perfil_tributario" ADD CONSTRAINT "cliente_perfil_tributario_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_perfil_tributario_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_perfil_tributario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_perfil_tributario" ADD CONSTRAINT "cliente_perfil_tributario_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cliente_tipos_servicio_catalogo_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."cliente_tipos_servicio_catalogo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cliente_tipos_servicio_catalogo" ADD CONSTRAINT "cliente_tipos_servicio_catalogo_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_baja_operativa_by_user_id_fkey'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_baja_operativa_by_user_id_fkey" FOREIGN KEY (baja_operativa_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_created_by_user_id_fkey'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_created_by_user_id_fkey" FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_deleted_by_user_id_fkey'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_deleted_by_user_id_fkey" FOREIGN KEY (deleted_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_plan_comercial_id_fkey'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_plan_comercial_id_fkey" FOREIGN KEY (plan_comercial_id) REFERENCES tecnolabo.planes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'clientes_vendedor_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."clientes" ADD CONSTRAINT "clientes_vendedor_usuario_id_fkey" FOREIGN KEY (vendedor_usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'cobros_clientes_cuenta_por_cobrar_id_fkey'
                    AND conrelid = '"tecnolabo"."cobros_clientes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."cobros_clientes" ADD CONSTRAINT "cobros_clientes_cuenta_por_cobrar_id_fkey" FOREIGN KEY (cuenta_por_cobrar_id) REFERENCES tecnolabo.cuentas_por_cobrar(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_ajustes_created_by_fkey'
                    AND conrelid = '"tecnolabo"."comision_ajustes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_ajustes" ADD CONSTRAINT "comision_ajustes_created_by_fkey" FOREIGN KEY (created_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_ajustes_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_ajustes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_ajustes" ADD CONSTRAINT "comision_ajustes_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_ajustes_linea_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_ajustes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_ajustes" ADD CONSTRAINT "comision_ajustes_linea_id_fkey" FOREIGN KEY (linea_id) REFERENCES tecnolabo.comision_lineas(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_ajustes_periodo_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_ajustes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_ajustes" ADD CONSTRAINT "comision_ajustes_periodo_id_fkey" FOREIGN KEY (periodo_id) REFERENCES tecnolabo.comision_periodos(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipo_miembros_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_equipo_miembros"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipo_miembros" ADD CONSTRAINT "comision_equipo_miembros_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipo_miembros_equipo_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_equipo_miembros"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipo_miembros" ADD CONSTRAINT "comision_equipo_miembros_equipo_id_fkey" FOREIGN KEY (equipo_id) REFERENCES tecnolabo.comision_equipos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipo_miembros_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_equipo_miembros"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipo_miembros" ADD CONSTRAINT "comision_equipo_miembros_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_equipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipos" ADD CONSTRAINT "comision_equipos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_equipos_supervisor_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_equipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_equipos" ADD CONSTRAINT "comision_equipos_supervisor_usuario_id_fkey" FOREIGN KEY (supervisor_usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_escalas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_escalas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_escalas" ADD CONSTRAINT "comision_escalas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_escalas_politica_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_escalas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_escalas" ADD CONSTRAINT "comision_escalas_politica_id_fkey" FOREIGN KEY (politica_id) REFERENCES tecnolabo.comision_politicas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_lineas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_lineas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_lineas" ADD CONSTRAINT "comision_lineas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_lineas_periodo_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_lineas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_lineas" ADD CONSTRAINT "comision_lineas_periodo_id_fkey" FOREIGN KEY (periodo_id) REFERENCES tecnolabo.comision_periodos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_lineas_usuario_vendedor_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_lineas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_lineas" ADD CONSTRAINT "comision_lineas_usuario_vendedor_id_fkey" FOREIGN KEY (usuario_vendedor_id) REFERENCES tecnolabo.usuarios(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_periodos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_periodos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_periodos" ADD CONSTRAINT "comision_periodos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_periodos_politica_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_periodos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_periodos" ADD CONSTRAINT "comision_periodos_politica_id_fkey" FOREIGN KEY (politica_id) REFERENCES tecnolabo.comision_politicas(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politica_versiones_created_by_fkey'
                    AND conrelid = '"tecnolabo"."comision_politica_versiones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politica_versiones" ADD CONSTRAINT "comision_politica_versiones_created_by_fkey" FOREIGN KEY (created_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politica_versiones_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_politica_versiones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politica_versiones" ADD CONSTRAINT "comision_politica_versiones_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politica_versiones_politica_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_politica_versiones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politica_versiones" ADD CONSTRAINT "comision_politica_versiones_politica_id_fkey" FOREIGN KEY (politica_id) REFERENCES tecnolabo.comision_politicas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politicas_created_by_fkey'
                    AND conrelid = '"tecnolabo"."comision_politicas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politicas" ADD CONSTRAINT "comision_politicas_created_by_fkey" FOREIGN KEY (created_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politicas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."comision_politicas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politicas" ADD CONSTRAINT "comision_politicas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'comision_politicas_updated_by_fkey'
                    AND conrelid = '"tecnolabo"."comision_politicas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."comision_politicas" ADD CONSTRAINT "comision_politicas_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_orden_compra_item_id_fkey'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_orden_compra_item_id_fkey" FOREIGN KEY (orden_compra_item_id) REFERENCES tecnolabo.ordenes_compra(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_producto_id_fkey" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'compras_proveedor_id_fkey'
                    AND conrelid = '"tecnolabo"."compras"'::regclass) THEN
    ALTER TABLE "tecnolabo"."compras" ADD CONSTRAINT "compras_proveedor_id_fkey" FOREIGN KEY (proveedor_id) REFERENCES tecnolabo.proveedores(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_etapas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."crm_etapas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_etapas" ADD CONSTRAINT "crm_etapas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_notas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."crm_notas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_notas" ADD CONSTRAINT "crm_notas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_notas_prospecto_id_fkey'
                    AND conrelid = '"tecnolabo"."crm_notas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_notas" ADD CONSTRAINT "crm_notas_prospecto_id_fkey" FOREIGN KEY (prospecto_id) REFERENCES tecnolabo.crm_prospectos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'crm_prospectos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."crm_prospectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."crm_prospectos" ADD CONSTRAINT "crm_prospectos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_venta_id_fkey'
                    AND conrelid = '"tecnolabo"."devoluciones_venta"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta" ADD CONSTRAINT "devoluciones_venta_venta_id_fkey" FOREIGN KEY (venta_id) REFERENCES tecnolabo.ventas(id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_cambios_devolucion_id_fkey'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_cambios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_cambios" ADD CONSTRAINT "devoluciones_venta_cambios_devolucion_id_fkey" FOREIGN KEY (devolucion_id) REFERENCES tecnolabo.devoluciones_venta(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_items_devolucion_id_fkey'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_items" ADD CONSTRAINT "devoluciones_venta_items_devolucion_id_fkey" FOREIGN KEY (devolucion_id) REFERENCES tecnolabo.devoluciones_venta(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'devoluciones_venta_items_venta_item_id_fkey'
                    AND conrelid = '"tecnolabo"."devoluciones_venta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."devoluciones_venta_items" ADD CONSTRAINT "devoluciones_venta_items_venta_item_id_fkey" FOREIGN KEY (venta_item_id) REFERENCES tecnolabo.ventas_items(id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_autoimpresor_config_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."empresa_autoimpresor_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_autoimpresor_config" ADD CONSTRAINT "empresa_autoimpresor_config_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_dashboard_views_dashboard_view_id_fkey'
                    AND conrelid = '"tecnolabo"."empresa_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_dashboard_views" ADD CONSTRAINT "empresa_dashboard_views_dashboard_view_id_fkey" FOREIGN KEY (dashboard_view_id) REFERENCES tecnolabo.dashboard_views(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_dashboard_views_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."empresa_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_dashboard_views" ADD CONSTRAINT "empresa_dashboard_views_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_facturacion_modo_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."empresa_facturacion_modo"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_facturacion_modo" ADD CONSTRAINT "empresa_facturacion_modo_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_modulos_modulo_id_fkey'
                    AND conrelid = '"tecnolabo"."empresa_modulos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_modulos" ADD CONSTRAINT "empresa_modulos_modulo_id_fkey" FOREIGN KEY (modulo_id) REFERENCES tecnolabo.modulos(id);
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'empresa_sifen_config_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."empresa_sifen_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."empresa_sifen_config" ADD CONSTRAINT "empresa_sifen_config_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_autoimpresor_venta_id_fkey'
                    AND conrelid = '"tecnolabo"."factura_autoimpresor"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_autoimpresor" ADD CONSTRAINT "factura_autoimpresor_venta_id_fkey" FOREIGN KEY (venta_id) REFERENCES tecnolabo.ventas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."factura_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica" ADD CONSTRAINT "factura_electronica_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_factura_id_fkey'
                    AND conrelid = '"tecnolabo"."factura_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica" ADD CONSTRAINT "factura_electronica_factura_id_fkey" FOREIGN KEY (factura_id) REFERENCES tecnolabo.facturas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_evento_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."factura_electronica_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica_evento" ADD CONSTRAINT "factura_electronica_evento_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_electronica_evento_factura_electronica_id_fkey'
                    AND conrelid = '"tecnolabo"."factura_electronica_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_electronica_evento" ADD CONSTRAINT "factura_electronica_evento_factura_electronica_id_fkey" FOREIGN KEY (factura_electronica_id) REFERENCES tecnolabo.factura_electronica(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_items_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."factura_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_items" ADD CONSTRAINT "factura_items_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'factura_items_factura_id_fkey'
                    AND conrelid = '"tecnolabo"."factura_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."factura_items" ADD CONSTRAINT "factura_items_factura_id_fkey" FOREIGN KEY (factura_id) REFERENCES tecnolabo.facturas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'facturas_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."facturas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."facturas" ADD CONSTRAINT "facturas_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'facturas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."facturas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."facturas" ADD CONSTRAINT "facturas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'facturas_suscripcion_id_fkey'
                    AND conrelid = '"tecnolabo"."facturas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."facturas" ADD CONSTRAINT "facturas_suscripcion_id_fkey" FOREIGN KEY (suscripcion_id) REFERENCES tecnolabo.suscripciones(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'gastos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."gastos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."gastos" ADD CONSTRAINT "gastos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'imports_audit_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."imports_audit"'::regclass) THEN
    ALTER TABLE "tecnolabo"."imports_audit" ADD CONSTRAINT "imports_audit_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_stock_ubicacion_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."inventario_stock_ubicacion"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_stock_ubicacion" ADD CONSTRAINT "inventario_stock_ubicacion_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_stock_ubicacion_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."inventario_stock_ubicacion"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_stock_ubicacion" ADD CONSTRAINT "inventario_stock_ubicacion_producto_id_fkey" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_stock_ubicacion_ubicacion_id_fkey'
                    AND conrelid = '"tecnolabo"."inventario_stock_ubicacion"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_stock_ubicacion" ADD CONSTRAINT "inventario_stock_ubicacion_ubicacion_id_fkey" FOREIGN KEY (ubicacion_id) REFERENCES tecnolabo.inventario_ubicaciones(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_ubicaciones_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."inventario_ubicaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_ubicaciones" ADD CONSTRAINT "inventario_ubicaciones_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'inventario_ubicaciones_parent_id_fkey'
                    AND conrelid = '"tecnolabo"."inventario_ubicaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."inventario_ubicaciones" ADD CONSTRAINT "inventario_ubicaciones_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES tecnolabo.inventario_ubicaciones(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_calendarios_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_calendarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_calendarios" ADD CONSTRAINT "marketing_calendarios_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_calendarios_created_by_fkey'
                    AND conrelid = '"tecnolabo"."marketing_calendarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_calendarios" ADD CONSTRAINT "marketing_calendarios_created_by_fkey" FOREIGN KEY (created_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_calendarios_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_calendarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_calendarios" ADD CONSTRAINT "marketing_calendarios_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_calendarios_updated_by_fkey'
                    AND conrelid = '"tecnolabo"."marketing_calendarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_calendarios" ADD CONSTRAINT "marketing_calendarios_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_comentarios_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_comentarios" ADD CONSTRAINT "marketing_comentarios_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_comentarios_pieza_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_comentarios" ADD CONSTRAINT "marketing_comentarios_pieza_id_fkey" FOREIGN KEY (pieza_id) REFERENCES tecnolabo.marketing_piezas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_comentarios_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_comentarios" ADD CONSTRAINT "marketing_comentarios_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_historial_estados_changed_by_fkey'
                    AND conrelid = '"tecnolabo"."marketing_historial_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_historial_estados" ADD CONSTRAINT "marketing_historial_estados_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_historial_estados_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_historial_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_historial_estados" ADD CONSTRAINT "marketing_historial_estados_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_historial_estados_pieza_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_historial_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_historial_estados" ADD CONSTRAINT "marketing_historial_estados_pieza_id_fkey" FOREIGN KEY (pieza_id) REFERENCES tecnolabo.marketing_piezas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_calendario_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_calendario_id_fkey" FOREIGN KEY (calendario_id) REFERENCES tecnolabo.marketing_calendarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_created_by_fkey'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_created_by_fkey" FOREIGN KEY (created_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_responsable_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_responsable_id_fkey" FOREIGN KEY (responsable_id) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_piezas_updated_by_fkey'
                    AND conrelid = '"tecnolabo"."marketing_piezas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_piezas" ADD CONSTRAINT "marketing_piezas_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_plan_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_plan_id_fkey" FOREIGN KEY (plan_id) REFERENCES tecnolabo.planes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_responsable_user_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_responsable_user_id_fkey" FOREIGN KEY (responsable_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'marketing_tasks_suscripcion_id_fkey'
                    AND conrelid = '"tecnolabo"."marketing_tasks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."marketing_tasks" ADD CONSTRAINT "marketing_tasks_suscripcion_id_fkey" FOREIGN KEY (suscripcion_id) REFERENCES tecnolabo.suscripciones(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'movimientos_inventario_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."movimientos_inventario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."movimientos_inventario" ADD CONSTRAINT "movimientos_inventario_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'movimientos_inventario_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."movimientos_inventario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."movimientos_inventario" ADD CONSTRAINT "movimientos_inventario_producto_id_fkey" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'movimientos_inventario_venta_id_fkey'
                    AND conrelid = '"tecnolabo"."movimientos_inventario"'::regclass) THEN
    ALTER TABLE "tecnolabo"."movimientos_inventario" ADD CONSTRAINT "movimientos_inventario_venta_id_fkey" FOREIGN KEY (venta_id) REFERENCES tecnolabo.ventas(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_created_by_user_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_created_by_user_id_fkey" FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_factura_electronica_origen_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_factura_electronica_origen_id_fkey" FOREIGN KEY (factura_electronica_origen_id) REFERENCES tecnolabo.factura_electronica(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_factura_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito" ADD CONSTRAINT "nota_credito_factura_id_fkey" FOREIGN KEY (factura_id) REFERENCES tecnolabo.facturas(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_electronica_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_electronica" ADD CONSTRAINT "nota_credito_electronica_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_electronica_nota_credito_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito_electronica"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_electronica" ADD CONSTRAINT "nota_credito_electronica_nota_credito_id_fkey" FOREIGN KEY (nota_credito_id) REFERENCES tecnolabo.nota_credito(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_evento_actor_user_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_evento" ADD CONSTRAINT "nota_credito_evento_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_evento_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_evento" ADD CONSTRAINT "nota_credito_evento_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'nota_credito_evento_nota_credito_id_fkey'
                    AND conrelid = '"tecnolabo"."nota_credito_evento"'::regclass) THEN
    ALTER TABLE "tecnolabo"."nota_credito_evento" ADD CONSTRAINT "nota_credito_evento_nota_credito_id_fkey" FOREIGN KEY (nota_credito_id) REFERENCES tecnolabo.nota_credito(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'omnichannel_routes_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."omnichannel_routes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."omnichannel_routes" ADD CONSTRAINT "omnichannel_routes_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pagos_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."pagos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pagos" ADD CONSTRAINT "pagos_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pagos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."pagos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pagos" ADD CONSTRAINT "pagos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pagos_factura_id_fkey'
                    AND conrelid = '"tecnolabo"."pagos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pagos" ADD CONSTRAINT "pagos_factura_id_fkey" FOREIGN KEY (factura_id) REFERENCES tecnolabo.facturas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'pagos_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."pagos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."pagos" ADD CONSTRAINT "pagos_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'planes_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."planes"'::regclass) THEN
    ALTER TABLE "tecnolabo"."planes" ADD CONSTRAINT "planes_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'presupuesto_items_presupuesto_id_fkey'
                    AND conrelid = '"tecnolabo"."presupuesto_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."presupuesto_items" ADD CONSTRAINT "presupuesto_items_presupuesto_id_fkey" FOREIGN KEY (presupuesto_id) REFERENCES tecnolabo.presupuestos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'produccion_items_produccion_id_fkey'
                    AND conrelid = '"tecnolabo"."produccion_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."produccion_items" ADD CONSTRAINT "produccion_items_produccion_id_fkey" FOREIGN KEY (produccion_id) REFERENCES tecnolabo.producciones(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_categorias_categoria_id_fkey'
                    AND conrelid = '"tecnolabo"."producto_categorias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_categorias" ADD CONSTRAINT "producto_categorias_categoria_id_fkey" FOREIGN KEY (categoria_id) REFERENCES tecnolabo.categorias_productos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_categorias_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."producto_categorias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_categorias" ADD CONSTRAINT "producto_categorias_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_categorias_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."producto_categorias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_categorias" ADD CONSTRAINT "producto_categorias_producto_id_fkey" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'producto_presentaciones_producto_fk'
                    AND conrelid = '"tecnolabo"."producto_presentaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."producto_presentaciones" ADD CONSTRAINT "producto_presentaciones_producto_fk" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_categoria_principal_id_fkey'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_categoria_principal_id_fkey" FOREIGN KEY (categoria_principal_id) REFERENCES tecnolabo.categorias_productos(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_proveedor_principal_id_fkey'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_proveedor_principal_id_fkey" FOREIGN KEY (proveedor_principal_id) REFERENCES tecnolabo.proveedores(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'productos_ubicacion_principal_id_fkey'
                    AND conrelid = '"tecnolabo"."productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."productos" ADD CONSTRAINT "productos_ubicacion_principal_id_fkey" FOREIGN KEY (ubicacion_principal_id) REFERENCES tecnolabo.inventario_ubicaciones(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_categoria_rel_categoria_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedor_categoria_rel"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_categoria_rel" ADD CONSTRAINT "proveedor_categoria_rel_categoria_id_fkey" FOREIGN KEY (categoria_id) REFERENCES tecnolabo.proveedor_categorias(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_categoria_rel_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedor_categoria_rel"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_categoria_rel" ADD CONSTRAINT "proveedor_categoria_rel_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_categoria_rel_proveedor_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedor_categoria_rel"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_categoria_rel" ADD CONSTRAINT "proveedor_categoria_rel_proveedor_id_fkey" FOREIGN KEY (proveedor_id) REFERENCES tecnolabo.proveedores(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_categorias_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedor_categorias"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_categorias" ADD CONSTRAINT "proveedor_categorias_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_productos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedor_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_productos" ADD CONSTRAINT "proveedor_productos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_productos_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedor_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_productos" ADD CONSTRAINT "proveedor_productos_producto_id_fkey" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedor_productos_proveedor_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedor_productos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedor_productos" ADD CONSTRAINT "proveedor_productos_proveedor_id_fkey" FOREIGN KEY (proveedor_id) REFERENCES tecnolabo.proveedores(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proveedores_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proveedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proveedores" ADD CONSTRAINT "proveedores_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_archivos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_archivos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_archivos" ADD CONSTRAINT "proyecto_archivos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_archivos_proyecto_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_archivos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_archivos" ADD CONSTRAINT "proyecto_archivos_proyecto_id_fkey" FOREIGN KEY (proyecto_id) REFERENCES tecnolabo.proyectos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_archivos_uploaded_by_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_archivos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_archivos" ADD CONSTRAINT "proyecto_archivos_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_comentarios_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_comentarios" ADD CONSTRAINT "proyecto_comentarios_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_comentarios_proyecto_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_comentarios" ADD CONSTRAINT "proyecto_comentarios_proyecto_id_fkey" FOREIGN KEY (proyecto_id) REFERENCES tecnolabo.proyectos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_comentarios_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_comentarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_comentarios" ADD CONSTRAINT "proyecto_comentarios_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estado_historial_changed_by_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_estado_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estado_historial" ADD CONSTRAINT "proyecto_estado_historial_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estado_historial_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_estado_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estado_historial" ADD CONSTRAINT "proyecto_estado_historial_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estado_historial_estado_anterior_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_estado_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estado_historial" ADD CONSTRAINT "proyecto_estado_historial_estado_anterior_id_fkey" FOREIGN KEY (estado_anterior_id) REFERENCES tecnolabo.proyecto_estados(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estado_historial_estado_nuevo_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_estado_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estado_historial" ADD CONSTRAINT "proyecto_estado_historial_estado_nuevo_id_fkey" FOREIGN KEY (estado_nuevo_id) REFERENCES tecnolabo.proyecto_estados(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estado_historial_proyecto_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_estado_historial"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estado_historial" ADD CONSTRAINT "proyecto_estado_historial_proyecto_id_fkey" FOREIGN KEY (proyecto_id) REFERENCES tecnolabo.proyectos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_estados_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_estados"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_estados" ADD CONSTRAINT "proyecto_estados_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_prioridades_config_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_prioridades_config"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ADD CONSTRAINT "proyecto_prioridades_config_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tareas_created_by_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_tareas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tareas" ADD CONSTRAINT "proyecto_tareas_created_by_fkey" FOREIGN KEY (created_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tareas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_tareas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tareas" ADD CONSTRAINT "proyecto_tareas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tareas_proyecto_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_tareas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tareas" ADD CONSTRAINT "proyecto_tareas_proyecto_id_fkey" FOREIGN KEY (proyecto_id) REFERENCES tecnolabo.proyectos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tareas_responsable_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_tareas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tareas" ADD CONSTRAINT "proyecto_tareas_responsable_id_fkey" FOREIGN KEY (responsable_id) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyecto_tipos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyecto_tipos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyecto_tipos" ADD CONSTRAINT "proyecto_tipos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_created_by_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_created_by_fkey" FOREIGN KEY (created_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_estado_id_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_estado_id_fkey" FOREIGN KEY (estado_id) REFERENCES tecnolabo.proyecto_estados(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_responsable_comercial_id_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_responsable_comercial_id_fkey" FOREIGN KEY (responsable_comercial_id) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_responsable_tecnico_id_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_responsable_tecnico_id_fkey" FOREIGN KEY (responsable_tecnico_id) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_tipo_id_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_tipo_id_fkey" FOREIGN KEY (tipo_id) REFERENCES tecnolabo.proyecto_tipos(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'proyectos_updated_by_fkey'
                    AND conrelid = '"tecnolabo"."proyectos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."proyectos" ADD CONSTRAINT "proyectos_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES tecnolabo.usuarios(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'receta_items_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."receta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."receta_items" ADD CONSTRAINT "receta_items_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'receta_items_insumo_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."receta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."receta_items" ADD CONSTRAINT "receta_items_insumo_producto_id_fkey" FOREIGN KEY (insumo_producto_id) REFERENCES tecnolabo.productos(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'receta_items_receta_id_fkey'
                    AND conrelid = '"tecnolabo"."receta_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."receta_items" ADD CONSTRAINT "receta_items_receta_id_fkey" FOREIGN KEY (receta_id) REFERENCES tecnolabo.recetas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'recetas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."recetas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."recetas" ADD CONSTRAINT "recetas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'recetas_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."recetas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."recetas" ADD CONSTRAINT "recetas_producto_id_fkey" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sifen_jobs_factura_electronica_id_fkey'
                    AND conrelid = '"tecnolabo"."sifen_jobs"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sifen_jobs" ADD CONSTRAINT "sifen_jobs_factura_electronica_id_fkey" FOREIGN KEY (factura_electronica_id) REFERENCES tecnolabo.factura_electronica(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_conversaciones_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_conversaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_conversaciones" ADD CONSTRAINT "sorteo_conversaciones_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_conversaciones_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_conversaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_conversaciones" ADD CONSTRAINT "sorteo_conversaciones_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_conversaciones_sorteo_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_conversaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_conversaciones" ADD CONSTRAINT "sorteo_conversaciones_sorteo_id_fkey" FOREIGN KEY (sorteo_id) REFERENCES tecnolabo.sorteos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_cupones_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_cupones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_cupones" ADD CONSTRAINT "sorteo_cupones_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_cupones_entrada_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_cupones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_cupones" ADD CONSTRAINT "sorteo_cupones_entrada_id_fkey" FOREIGN KEY (entrada_id) REFERENCES tecnolabo.sorteo_entradas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_cupones_sorteo_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_cupones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_cupones" ADD CONSTRAINT "sorteo_cupones_sorteo_id_fkey" FOREIGN KEY (sorteo_id) REFERENCES tecnolabo.sorteos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_chat_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_chat_conversation_id_fkey" FOREIGN KEY (chat_conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_comprobante_validacion_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_comprobante_validacion_id_fkey" FOREIGN KEY (comprobante_validacion_id) REFERENCES tecnolabo.chat_comprobante_validaciones(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_conversacion_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_conversacion_id_fkey" FOREIGN KEY (conversacion_id) REFERENCES tecnolabo.sorteo_conversaciones(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_revendedor_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_revendedor_id_fkey" FOREIGN KEY (revendedor_id) REFERENCES tecnolabo.sorteo_revendedores(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_entradas_sorteo_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_entradas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_entradas" ADD CONSTRAINT "sorteo_entradas_sorteo_id_fkey" FOREIGN KEY (sorteo_id) REFERENCES tecnolabo.sorteos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedor_clicks_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedor_clicks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedor_clicks" ADD CONSTRAINT "sorteo_revendedor_clicks_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedor_clicks_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedor_clicks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedor_clicks" ADD CONSTRAINT "sorteo_revendedor_clicks_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedor_clicks_flow_session_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedor_clicks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedor_clicks" ADD CONSTRAINT "sorteo_revendedor_clicks_flow_session_id_fkey" FOREIGN KEY (flow_session_id) REFERENCES tecnolabo.chat_flow_sessions(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedor_clicks_revendedor_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedor_clicks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedor_clicks" ADD CONSTRAINT "sorteo_revendedor_clicks_revendedor_id_fkey" FOREIGN KEY (revendedor_id) REFERENCES tecnolabo.sorteo_revendedores(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedor_clicks_sorteo_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedor_clicks"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedor_clicks" ADD CONSTRAINT "sorteo_revendedor_clicks_sorteo_id_fkey" FOREIGN KEY (sorteo_id) REFERENCES tecnolabo.sorteos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedores_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedores" ADD CONSTRAINT "sorteo_revendedores_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_revendedores_sorteo_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_revendedores"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_revendedores" ADD CONSTRAINT "sorteo_revendedores_sorteo_id_fkey" FOREIGN KEY (sorteo_id) REFERENCES tecnolabo.sorteos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_ticket_deliveries_conversation_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_ticket_deliveries"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ADD CONSTRAINT "sorteo_ticket_deliveries_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES tecnolabo.chat_conversations(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_ticket_deliveries_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_ticket_deliveries"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ADD CONSTRAINT "sorteo_ticket_deliveries_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_ticket_deliveries_entrada_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_ticket_deliveries"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ADD CONSTRAINT "sorteo_ticket_deliveries_entrada_id_fkey" FOREIGN KEY (entrada_id) REFERENCES tecnolabo.sorteo_entradas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteo_ticket_deliveries_sorteo_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteo_ticket_deliveries"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ADD CONSTRAINT "sorteo_ticket_deliveries_sorteo_id_fkey" FOREIGN KEY (sorteo_id) REFERENCES tecnolabo.sorteos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'sorteos_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."sorteos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."sorteos" ADD CONSTRAINT "sorteos_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'suscripciones_plan_id_fkey'
                    AND conrelid = '"tecnolabo"."suscripciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."suscripciones" ADD CONSTRAINT "suscripciones_plan_id_fkey" FOREIGN KEY (plan_id) REFERENCES tecnolabo.planes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tipificaciones_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."tipificaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."tipificaciones" ADD CONSTRAINT "tipificaciones_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tipificaciones_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."tipificaciones"'::regclass) THEN
    ALTER TABLE "tecnolabo"."tipificaciones" ADD CONSTRAINT "tipificaciones_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_dashboard_views_dashboard_view_id_fkey'
                    AND conrelid = '"tecnolabo"."usuario_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_dashboard_views" ADD CONSTRAINT "usuario_dashboard_views_dashboard_view_id_fkey" FOREIGN KEY (dashboard_view_id) REFERENCES tecnolabo.dashboard_views(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_dashboard_views_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."usuario_dashboard_views"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_dashboard_views" ADD CONSTRAINT "usuario_dashboard_views_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_modulos_modulo_id_fkey'
                    AND conrelid = '"tecnolabo"."usuario_modulos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_modulos" ADD CONSTRAINT "usuario_modulos_modulo_id_fkey" FOREIGN KEY (modulo_id) REFERENCES tecnolabo.modulos(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuario_modulos_usuario_id_fkey'
                    AND conrelid = '"tecnolabo"."usuario_modulos"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuario_modulos" ADD CONSTRAINT "usuario_modulos_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES tecnolabo.usuarios(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_auth_user_id_fkey'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'usuarios_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."usuarios"'::regclass) THEN
    ALTER TABLE "tecnolabo"."usuarios" ADD CONSTRAINT "usuarios_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_cliente_id_fkey'
                    AND conrelid = '"tecnolabo"."ventas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas" ADD CONSTRAINT "ventas_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES tecnolabo.clientes(id) ON DELETE SET NULL;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."ventas"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas" ADD CONSTRAINT "ventas_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_items_empresa_id_fkey'
                    AND conrelid = '"tecnolabo"."ventas_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_items" ADD CONSTRAINT "ventas_items_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES tecnolabo.empresas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_items_producto_id_fkey'
                    AND conrelid = '"tecnolabo"."ventas_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_items" ADD CONSTRAINT "ventas_items_producto_id_fkey" FOREIGN KEY (producto_id) REFERENCES tecnolabo.productos(id) ON DELETE RESTRICT;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_items_venta_id_fkey'
                    AND conrelid = '"tecnolabo"."ventas_items"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_items" ADD CONSTRAINT "ventas_items_venta_id_fkey" FOREIGN KEY (venta_id) REFERENCES tecnolabo.ventas(id) ON DELETE CASCADE;
  END IF;
END $mig$;
DO $mig$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ventas_pagos_detalle_entidad_bancaria_id_fkey'
                    AND conrelid = '"tecnolabo"."ventas_pagos_detalle"'::regclass) THEN
    ALTER TABLE "tecnolabo"."ventas_pagos_detalle" ADD CONSTRAINT "ventas_pagos_detalle_entidad_bancaria_id_fkey" FOREIGN KEY (entidad_bancaria_id) REFERENCES tecnolabo.entidades_bancarias(id) ON DELETE SET NULL;
  END IF;
END $mig$;

-- ── INDICES ──────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS caja_movimientos_caja_idx ON tecnolabo.caja_movimientos USING btree (caja_id, created_at);
CREATE INDEX IF NOT EXISTS caja_movimientos_devolucion_idx ON tecnolabo.caja_movimientos USING btree (empresa_id, devolucion_id);
CREATE INDEX IF NOT EXISTS caja_movimientos_empresa_idx ON tecnolabo.caja_movimientos USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS caja_movimientos_tipo_estado_fecha_idx ON tecnolabo.caja_movimientos USING btree (empresa_id, tipo, ((anulado_at IS NULL)), created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS cajas_activa_por_numero ON tecnolabo.cajas USING btree (empresa_id, numero_caja) WHERE (estado = ANY (ARRAY['abierta'::text, 'en_cierre'::text]));
CREATE INDEX IF NOT EXISTS cajas_empresa_estado_idx ON tecnolabo.cajas USING btree (empresa_id, estado);
CREATE INDEX IF NOT EXISTS cajas_empresa_fecha_idx ON tecnolabo.cajas USING btree (empresa_id, fecha_apertura DESC);
CREATE UNIQUE INDEX IF NOT EXISTS chat_channels_meta_phone_number_id_uidx ON tecnolabo.chat_channels USING btree (meta_phone_number_id) WHERE ((meta_phone_number_id IS NOT NULL) AND (btrim(meta_phone_number_id) <> ''::text));
CREATE INDEX IF NOT EXISTS devoluciones_venta_cambios_dev_idx ON tecnolabo.devoluciones_venta_cambios USING btree (empresa_id, devolucion_id);
CREATE INDEX IF NOT EXISTS devoluciones_venta_fecha_idx ON tecnolabo.devoluciones_venta USING btree (empresa_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS devoluciones_venta_idem_uidx ON tecnolabo.devoluciones_venta USING btree (empresa_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);
CREATE INDEX IF NOT EXISTS devoluciones_venta_items_dev_idx ON tecnolabo.devoluciones_venta_items USING btree (empresa_id, devolucion_id);
CREATE INDEX IF NOT EXISTS devoluciones_venta_items_vitem_idx ON tecnolabo.devoluciones_venta_items USING btree (empresa_id, venta_item_id);
CREATE UNIQUE INDEX IF NOT EXISTS devoluciones_venta_numero_uidx ON tecnolabo.devoluciones_venta USING btree (empresa_id, numero_devolucion);
CREATE INDEX IF NOT EXISTS devoluciones_venta_venta_idx ON tecnolabo.devoluciones_venta USING btree (empresa_id, venta_id);
CREATE UNIQUE INDEX IF NOT EXISTS empresas_data_schema_unique ON tecnolabo.empresas USING btree (data_schema) WHERE (data_schema IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS factura_autoimpresor_numero_uq ON tecnolabo.factura_autoimpresor USING btree (empresa_id, timbrado_numero, establecimiento_codigo, punto_expedicion_codigo, numero_secuencia);
CREATE UNIQUE INDEX IF NOT EXISTS factura_autoimpresor_venta_uq ON tecnolabo.factura_autoimpresor USING btree (empresa_id, venta_id);
CREATE INDEX IF NOT EXISTS gastos_empresa_fecha_idx ON tecnolabo.gastos USING btree (empresa_id, fecha);
CREATE INDEX IF NOT EXISTS idx_caja_movimientos_venta_id ON tecnolabo.caja_movimientos USING btree (venta_id) WHERE (venta_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_categorias_productos_activo ON tecnolabo.categorias_productos USING btree (activo);
CREATE INDEX IF NOT EXISTS idx_categorias_productos_empresa ON tecnolabo.categorias_productos USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_categorias_productos_nombre ON tecnolabo.categorias_productos USING btree (nombre);
CREATE INDEX IF NOT EXISTS idx_categorias_productos_parent ON tecnolabo.categorias_productos USING btree (parent_id);
CREATE INDEX IF NOT EXISTS idx_cfr_rules_empresa_flow ON tecnolabo.chat_flow_recontact_rules USING btree (empresa_id, flow_code);
CREATE INDEX IF NOT EXISTS idx_cfr_rules_flow_prio ON tecnolabo.chat_flow_recontact_rules USING btree (flow_code, prioridad);
CREATE INDEX IF NOT EXISTS idx_cfr_runs_empresa_created ON tecnolabo.chat_flow_recontact_runs USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cfr_runs_rule_created ON tecnolabo.chat_flow_recontact_runs USING btree (rule_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_agents_empresa ON tecnolabo.chat_agents USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_agents_online ON tecnolabo.chat_agents USING btree (queue_id, is_online) WHERE (is_online = true);
CREATE INDEX IF NOT EXISTS idx_chat_agents_queue ON tecnolabo.chat_agents USING btree (queue_id);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_events_e_c_cr ON tecnolabo.chat_campaign_events USING btree (empresa_id, campaign_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_events_rec ON tecnolabo.chat_campaign_events USING btree (recipient_id);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_jobs_c ON tecnolabo.chat_campaign_jobs USING btree (campaign_id);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_jobs_e_st ON tecnolabo.chat_campaign_jobs USING btree (empresa_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_recipients_conv ON tecnolabo.chat_campaign_recipients USING btree (conversation_id);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_recipients_e_c_st ON tecnolabo.chat_campaign_recipients USING btree (empresa_id, campaign_id, status);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_recipients_wamid ON tecnolabo.chat_campaign_recipients USING btree (provider_message_id);
CREATE INDEX IF NOT EXISTS idx_chat_campaign_templates_ch_st ON tecnolabo.chat_campaign_templates USING btree (empresa_id, channel_id, status);
CREATE INDEX IF NOT EXISTS idx_chat_campaigns_e_ch ON tecnolabo.chat_campaigns USING btree (empresa_id, channel_id);
CREATE INDEX IF NOT EXISTS idx_chat_campaigns_e_q ON tecnolabo.chat_campaigns USING btree (empresa_id, queue_id);
CREATE INDEX IF NOT EXISTS idx_chat_campaigns_e_st_cr ON tecnolabo.chat_campaigns USING btree (empresa_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_channel_quick_replies_ch ON tecnolabo.chat_channel_quick_replies USING btree (channel_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_chat_channel_quick_replies_e ON tecnolabo.chat_channel_quick_replies USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_channels_empresa ON tecnolabo.chat_channels USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_channels_empresa_activo ON tecnolabo.chat_channels USING btree (empresa_id, activo) WHERE (activo = true);
CREATE INDEX IF NOT EXISTS idx_chat_closure_states_empresa ON tecnolabo.chat_queue_closure_states USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_closure_states_queue ON tecnolabo.chat_queue_closure_states USING btree (queue_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_chat_closure_substates_state ON tecnolabo.chat_queue_closure_substates USING btree (closure_state_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_chat_comp_val_conversation ON tecnolabo.chat_comprobante_validaciones USING btree (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_comp_val_empresa_hash ON tecnolabo.chat_comprobante_validaciones USING btree (empresa_id, comprobante_hash);
CREATE INDEX IF NOT EXISTS idx_chat_comp_val_empresa_ocr_fp ON tecnolabo.chat_comprobante_validaciones USING btree (empresa_id, ocr_fingerprint) WHERE ((ocr_fingerprint IS NOT NULL) AND (length(TRIM(BOTH FROM ocr_fingerprint)) > 0));
CREATE INDEX IF NOT EXISTS idx_chat_comp_val_entrada ON tecnolabo.chat_comprobante_validaciones USING btree (sorteo_entrada_id) WHERE (sorteo_entrada_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_chat_comp_val_flow_session ON tecnolabo.chat_comprobante_validaciones USING btree (flow_session_id);
CREATE INDEX IF NOT EXISTS idx_chat_contacts_cliente ON tecnolabo.chat_contacts USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_chat_contacts_empresa ON tecnolabo.chat_contacts USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_contacts_empresa_name_lower ON tecnolabo.chat_contacts USING btree (empresa_id, lower(name));
CREATE INDEX IF NOT EXISTS idx_chat_contacts_empresa_phone_normalized ON tecnolabo.chat_contacts USING btree (empresa_id, phone_normalized);
CREATE INDEX IF NOT EXISTS idx_chat_contacts_prospecto ON tecnolabo.chat_contacts USING btree (crm_prospecto_id);
CREATE INDEX IF NOT EXISTS idx_chat_conv_emp_unassigned_recent ON tecnolabo.chat_conversations USING btree (empresa_id, last_message_at DESC NULLS LAST) WHERE ((assigned_agent_id IS NULL) AND (status = ANY (ARRAY['open'::text, 'pending'::text])));
CREATE INDEX IF NOT EXISTS idx_chat_conv_empresa_last ON tecnolabo.chat_conversations USING btree (empresa_id, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_chat_conversation_closures_agent ON tecnolabo.chat_conversation_closures USING btree (empresa_id, closed_by_usuario_id, closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_conversation_closures_conv ON tecnolabo.chat_conversation_closures USING btree (conversation_id);
CREATE INDEX IF NOT EXISTS idx_chat_conversation_closures_empresa_closed ON tecnolabo.chat_conversation_closures USING btree (empresa_id, closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_conversation_closures_labels ON tecnolabo.chat_conversation_closures USING btree (empresa_id, closure_state_label, closure_substate_label);
CREATE INDEX IF NOT EXISTS idx_chat_conversation_closures_queue ON tecnolabo.chat_conversation_closures USING btree (empresa_id, queue_id, closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_active_flow_session ON tecnolabo.chat_conversations USING btree (active_flow_session_id);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_assigned_agent ON tecnolabo.chat_conversations USING btree (assigned_agent_id) WHERE (assigned_agent_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_first_revendedor ON tecnolabo.chat_conversations USING btree (first_revendedor_id) WHERE (first_revendedor_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_queue ON tecnolabo.chat_conversations USING btree (queue_id) WHERE (queue_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_chat_empresa_operator_roles_empresa ON tecnolabo.chat_empresa_operator_roles USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_flow_data_empresa_conversation ON tecnolabo.chat_flow_data USING btree (empresa_id, conversation_id);
CREATE INDEX IF NOT EXISTS idx_chat_flow_data_flow_session ON tecnolabo.chat_flow_data USING btree (flow_session_id);
CREATE INDEX IF NOT EXISTS idx_chat_flow_events_conv_created_desc ON tecnolabo.chat_flow_events USING btree (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_flow_events_session_created ON tecnolabo.chat_flow_events USING btree (flow_session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_flow_node_blocks_empresa ON tecnolabo.chat_flow_node_blocks USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_flow_node_blocks_node_order ON tecnolabo.chat_flow_node_blocks USING btree (node_id, sort_order, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_flow_nodes_empresa_flow ON tecnolabo.chat_flow_nodes USING btree (empresa_id, flow_code);
CREATE INDEX IF NOT EXISTS idx_chat_flow_nodes_empresa_flow_sort ON tecnolabo.chat_flow_nodes USING btree (empresa_id, flow_code, sort_order);
CREATE INDEX IF NOT EXISTS idx_chat_flow_options_node_sort ON tecnolabo.chat_flow_options USING btree (node_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_chat_flow_sessions_conversation ON tecnolabo.chat_flow_sessions USING btree (conversation_id, flow_code, status);
CREATE INDEX IF NOT EXISTS idx_chat_flow_sessions_empresa ON tecnolabo.chat_flow_sessions USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_flow_sessions_revendedor ON tecnolabo.chat_flow_sessions USING btree (revendedor_id) WHERE (revendedor_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_chat_flows_empresa ON tecnolabo.chat_flows USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_flows_sorteo ON tecnolabo.chat_flows USING btree (sorteo_id) WHERE (sorteo_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_chat_messages_empresa_created_at ON tecnolabo.chat_messages USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender_type ON tecnolabo.chat_messages USING btree (sender_type);
CREATE INDEX IF NOT EXISTS idx_chat_msg_conv ON tecnolabo.chat_messages USING btree (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_msg_empresa ON tecnolabo.chat_messages USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_omn_sched_activo ON tecnolabo.chat_omnicanal_work_schedules USING btree (empresa_id, is_active);
CREATE INDEX IF NOT EXISTS idx_chat_omn_sched_empresa ON tecnolabo.chat_omnicanal_work_schedules USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_queue_channels_channel ON tecnolabo.chat_queue_channels USING btree (channel_id);
CREATE INDEX IF NOT EXISTS idx_chat_queue_channels_empresa ON tecnolabo.chat_queue_channels USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_queue_channels_queue ON tecnolabo.chat_queue_channels USING btree (queue_id);
CREATE INDEX IF NOT EXISTS idx_chat_queue_supervisors_empresa_usuario ON tecnolabo.chat_queue_supervisors USING btree (empresa_id, usuario_id);
CREATE INDEX IF NOT EXISTS idx_chat_queues_empresa_active ON tecnolabo.chat_queues USING btree (empresa_id, is_active) WHERE (is_active = true);
CREATE INDEX IF NOT EXISTS idx_chat_supervisor_agents_supervisor ON tecnolabo.chat_supervisor_agents USING btree (empresa_id, supervisor_usuario_id);
CREATE INDEX IF NOT EXISTS idx_chat_usuario_omnicanal_empresa ON tecnolabo.chat_usuario_omnicanal USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_chat_usuario_omnicanal_usuario ON tecnolabo.chat_usuario_omnicanal USING btree (usuario_id);
CREATE INDEX IF NOT EXISTS idx_cliente_historial_cliente_at ON tecnolabo.cliente_historial USING btree (cliente_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cliente_historial_empresa_at ON tecnolabo.cliente_historial USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cliente_obligaciones_empresa ON tecnolabo.cliente_obligaciones_tributarias USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_cliente_obligaciones_perfil ON tecnolabo.cliente_obligaciones_tributarias USING btree (cliente_perfil_id);
CREATE INDEX IF NOT EXISTS idx_cliente_perfil_tributario_cliente ON tecnolabo.cliente_perfil_tributario USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_cliente_perfil_tributario_empresa ON tecnolabo.cliente_perfil_tributario USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_clientes_baja_operativa_at ON tecnolabo.clientes USING btree (baja_operativa_at) WHERE (baja_operativa_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_clientes_created_by ON tecnolabo.clientes USING btree (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_clientes_deleted_at ON tecnolabo.clientes USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_clientes_tipo_servicio ON tecnolabo.clientes USING btree (tipo_servicio_cliente) WHERE (tipo_servicio_cliente IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_cobros_cliente ON tecnolabo.cobros_clientes USING btree (empresa_id, cliente_id);
CREATE INDEX IF NOT EXISTS idx_cobros_cuenta ON tecnolabo.cobros_clientes USING btree (cuenta_por_cobrar_id);
CREATE INDEX IF NOT EXISTS idx_cobros_empresa_fecha ON tecnolabo.cobros_clientes USING btree (empresa_id, fecha_pago DESC);
CREATE INDEX IF NOT EXISTS idx_compras_created_by ON tecnolabo.compras USING btree (created_by);
CREATE INDEX IF NOT EXISTS idx_compras_empresa ON tecnolabo.compras USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_compras_empresa_fecha ON tecnolabo.compras USING btree (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_compras_empresa_numero ON tecnolabo.compras USING btree (empresa_id, numero_control);
CREATE INDEX IF NOT EXISTS idx_compras_fecha ON tecnolabo.compras USING btree (fecha);
CREATE INDEX IF NOT EXISTS idx_compras_orden_compra ON tecnolabo.compras USING btree (empresa_id, orden_compra_numero);
CREATE INDEX IF NOT EXISTS idx_compras_orden_compra_item ON tecnolabo.compras USING btree (orden_compra_item_id);
CREATE INDEX IF NOT EXISTS idx_compras_producto ON tecnolabo.compras USING btree (producto_id);
CREATE INDEX IF NOT EXISTS idx_compras_proveedor ON tecnolabo.compras USING btree (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_cre_conv ON tecnolabo.chat_routing_events USING btree (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cre_emp ON tecnolabo.chat_routing_events USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_crm_etapas_empresa ON tecnolabo.crm_etapas USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_crm_etapas_empresa_orden ON tecnolabo.crm_etapas USING btree (empresa_id, orden);
CREATE INDEX IF NOT EXISTS idx_crm_notas_empresa ON tecnolabo.crm_notas USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_crm_notas_prospecto ON tecnolabo.crm_notas USING btree (prospecto_id);
CREATE INDEX IF NOT EXISTS idx_crm_prospectos_empresa ON tecnolabo.crm_prospectos USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_crm_prospectos_empresa_origen ON tecnolabo.crm_prospectos USING btree (empresa_id, origen_creacion);
CREATE INDEX IF NOT EXISTS idx_crm_prospectos_etapa ON tecnolabo.crm_prospectos USING btree (etapa);
CREATE INDEX IF NOT EXISTS idx_cxc_cliente ON tecnolabo.cuentas_por_cobrar USING btree (empresa_id, cliente_id);
CREATE INDEX IF NOT EXISTS idx_cxc_empresa_estado ON tecnolabo.cuentas_por_cobrar USING btree (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_cxc_vencimiento ON tecnolabo.cuentas_por_cobrar USING btree (empresa_id, fecha_vencimiento);
CREATE INDEX IF NOT EXISTS idx_dashboard_views_activo ON tecnolabo.dashboard_views USING btree (activo);
CREATE INDEX IF NOT EXISTS idx_edv_empresa ON tecnolabo.empresa_dashboard_views USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_edv_view ON tecnolabo.empresa_dashboard_views USING btree (dashboard_view_id);
CREATE INDEX IF NOT EXISTS idx_factura_electronica_empresa ON tecnolabo.factura_electronica USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_factura_electronica_empresa_estado ON tecnolabo.factura_electronica USING btree (empresa_id, estado_sifen);
CREATE INDEX IF NOT EXISTS idx_factura_electronica_evento_de ON tecnolabo.factura_electronica_evento USING btree (factura_electronica_id);
CREATE INDEX IF NOT EXISTS idx_factura_electronica_evento_empresa ON tecnolabo.factura_electronica_evento USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_factura_electronica_evento_empresa_created ON tecnolabo.factura_electronica_evento USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_factura_electronica_factura ON tecnolabo.factura_electronica USING btree (factura_id);
CREATE INDEX IF NOT EXISTS idx_factura_items_empresa ON tecnolabo.factura_items USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_factura_items_factura ON tecnolabo.factura_items USING btree (factura_id);
CREATE INDEX IF NOT EXISTS idx_facturas_cliente ON tecnolabo.facturas USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_facturas_empresa ON tecnolabo.facturas USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_facturas_fecha ON tecnolabo.facturas USING btree (fecha);
CREATE INDEX IF NOT EXISTS idx_facturas_suscripcion ON tecnolabo.facturas USING btree (suscripcion_id);
CREATE INDEX IF NOT EXISTS idx_imports_audit_empresa_fecha ON tecnolabo.imports_audit USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_imports_audit_entidad ON tecnolabo.imports_audit USING btree (entidad);
CREATE INDEX IF NOT EXISTS idx_marketing_tasks_cliente ON tecnolabo.marketing_tasks USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_marketing_tasks_empresa ON tecnolabo.marketing_tasks USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_marketing_tasks_estado ON tecnolabo.marketing_tasks USING btree (estado);
CREATE INDEX IF NOT EXISTS idx_marketing_tasks_fecha ON tecnolabo.marketing_tasks USING btree (fecha_entrega);
CREATE INDEX IF NOT EXISTS idx_marketing_tasks_plan ON tecnolabo.marketing_tasks USING btree (plan_id);
CREATE INDEX IF NOT EXISTS idx_marketing_tasks_suscripcion ON tecnolabo.marketing_tasks USING btree (suscripcion_id);
CREATE INDEX IF NOT EXISTS idx_mov_produccion_id ON tecnolabo.movimientos_inventario USING btree (produccion_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_empresa ON tecnolabo.movimientos_inventario USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_fecha ON tecnolabo.movimientos_inventario USING btree (fecha);
CREATE INDEX IF NOT EXISTS idx_movimientos_inventario_created_by ON tecnolabo.movimientos_inventario USING btree (created_by);
CREATE INDEX IF NOT EXISTS idx_movimientos_producto ON tecnolabo.movimientos_inventario USING btree (producto_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_venta ON tecnolabo.movimientos_inventario USING btree (venta_id);
CREATE INDEX IF NOT EXISTS idx_nota_credito_electronica_empresa ON tecnolabo.nota_credito_electronica USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_nota_credito_empresa ON tecnolabo.nota_credito USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_nota_credito_empresa_created ON tecnolabo.nota_credito USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nota_credito_evento_empresa ON tecnolabo.nota_credito_evento USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_nota_credito_evento_nc ON tecnolabo.nota_credito_evento USING btree (nota_credito_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nota_credito_factura ON tecnolabo.nota_credito USING btree (factura_id);
CREATE INDEX IF NOT EXISTS idx_notificaciones_empresa ON tecnolabo.notificaciones USING btree (empresa_id, leida, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_omnichannel_routes_empresa ON tecnolabo.omnichannel_routes USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_compra_empresa ON tecnolabo.ordenes_compra USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_compra_estado ON tecnolabo.ordenes_compra USING btree (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_ordenes_compra_fecha ON tecnolabo.ordenes_compra USING btree (fecha);
CREATE INDEX IF NOT EXISTS idx_ordenes_compra_numero ON tecnolabo.ordenes_compra USING btree (empresa_id, numero_oc);
CREATE INDEX IF NOT EXISTS idx_ordenes_compra_proveedor ON tecnolabo.ordenes_compra USING btree (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_pagos_cliente ON tecnolabo.pagos USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_pagos_empresa ON tecnolabo.pagos USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_pagos_factura ON tecnolabo.pagos USING btree (factura_id);
CREATE INDEX IF NOT EXISTS idx_pagos_fecha ON tecnolabo.pagos USING btree (fecha_pago);
CREATE INDEX IF NOT EXISTS idx_pagos_usuario ON tecnolabo.pagos USING btree (usuario_id);
CREATE INDEX IF NOT EXISTS idx_planes_empresa ON tecnolabo.planes USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_presupuesto_items_presupuesto ON tecnolabo.presupuesto_items USING btree (presupuesto_id);
CREATE INDEX IF NOT EXISTS idx_presupuestos_empresa_fecha ON tecnolabo.presupuestos USING btree (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_presupuestos_estado ON tecnolabo.presupuestos USING btree (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_produccion_items_produccion ON tecnolabo.produccion_items USING btree (produccion_id);
CREATE INDEX IF NOT EXISTS idx_producciones_empresa_fecha ON tecnolabo.producciones USING btree (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_producto_categorias_categoria ON tecnolabo.producto_categorias USING btree (categoria_id);
CREATE INDEX IF NOT EXISTS idx_producto_categorias_producto ON tecnolabo.producto_categorias USING btree (producto_id);
CREATE INDEX IF NOT EXISTS idx_productos_destacado ON tecnolabo.productos USING btree (empresa_id, destacado) WHERE (destacado = true);
CREATE INDEX IF NOT EXISTS idx_productos_empresa ON tecnolabo.productos USING btree (empresa_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_productos_empresa_sku ON tecnolabo.productos USING btree (empresa_id, sku);
CREATE INDEX IF NOT EXISTS idx_productos_es_insumo ON tecnolabo.productos USING btree (empresa_id) WHERE (es_insumo = true);
CREATE INDEX IF NOT EXISTS idx_productos_es_vendible ON tecnolabo.productos USING btree (empresa_id) WHERE (es_vendible = true);
CREATE INDEX IF NOT EXISTS idx_prov_cat_rel_categoria ON tecnolabo.proveedor_categoria_rel USING btree (categoria_id);
CREATE INDEX IF NOT EXISTS idx_prov_cat_rel_empresa ON tecnolabo.proveedor_categoria_rel USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_prov_cat_rel_proveedor ON tecnolabo.proveedor_categoria_rel USING btree (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_proveedor_categorias_empresa ON tecnolabo.proveedor_categorias USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_proveedor_productos_empresa ON tecnolabo.proveedor_productos USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_proveedor_productos_producto ON tecnolabo.proveedor_productos USING btree (producto_id);
CREATE INDEX IF NOT EXISTS idx_proveedor_productos_proveedor ON tecnolabo.proveedor_productos USING btree (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_proveedores_empresa ON tecnolabo.proveedores USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_receta_items_empresa ON tecnolabo.receta_items USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_receta_items_insumo ON tecnolabo.receta_items USING btree (insumo_producto_id);
CREATE INDEX IF NOT EXISTS idx_receta_items_receta ON tecnolabo.receta_items USING btree (receta_id);
CREATE INDEX IF NOT EXISTS idx_recetas_empresa ON tecnolabo.recetas USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_recetas_producto ON tecnolabo.recetas USING btree (producto_id);
CREATE INDEX IF NOT EXISTS idx_recibos_empresa_fecha ON tecnolabo.recibos_dinero USING btree (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_sifen_jobs_empresa_created ON tecnolabo.sifen_jobs USING btree (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sifen_jobs_fe_created ON tecnolabo.sifen_jobs USING btree (factura_electronica_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sifen_jobs_pendientes ON tecnolabo.sifen_jobs USING btree (proximo_reintento_at NULLS FIRST, created_at) WHERE (estado = 'pendiente'::text);
CREATE INDEX IF NOT EXISTS idx_sifen_jobs_procesando ON tecnolabo.sifen_jobs USING btree (procesando_desde) WHERE (estado = 'procesando'::text);
CREATE INDEX IF NOT EXISTS idx_sorteo_conv_empresa ON tecnolabo.sorteo_conversaciones USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_conv_estado ON tecnolabo.sorteo_conversaciones USING btree (estado);
CREATE INDEX IF NOT EXISTS idx_sorteo_conv_sorteo ON tecnolabo.sorteo_conversaciones USING btree (sorteo_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_conv_wa ON tecnolabo.sorteo_conversaciones USING btree (whatsapp_numero);
CREATE INDEX IF NOT EXISTS idx_sorteo_cup_empresa ON tecnolabo.sorteo_cupones USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_cup_entrada ON tecnolabo.sorteo_cupones USING btree (entrada_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_cup_sorteo ON tecnolabo.sorteo_cupones USING btree (sorteo_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_ent_cliente ON tecnolabo.sorteo_entradas USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_ent_comp_val ON tecnolabo.sorteo_entradas USING btree (comprobante_validacion_id) WHERE (comprobante_validacion_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_sorteo_ent_conv ON tecnolabo.sorteo_entradas USING btree (conversacion_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_ent_empresa ON tecnolabo.sorteo_entradas USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_ent_sorteo ON tecnolabo.sorteo_entradas USING btree (sorteo_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_entradas_chat_conversation ON tecnolabo.sorteo_entradas USING btree (chat_conversation_id) WHERE (chat_conversation_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_sorteo_entradas_revendedor ON tecnolabo.sorteo_entradas USING btree (revendedor_id) WHERE (revendedor_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_sorteo_rev_clicks_revendedor ON tecnolabo.sorteo_revendedor_clicks USING btree (revendedor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sorteo_rev_clicks_sorteo ON tecnolabo.sorteo_revendedor_clicks USING btree (sorteo_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sorteo_revendedores_empresa ON tecnolabo.sorteo_revendedores USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_revendedores_sorteo ON tecnolabo.sorteo_revendedores USING btree (sorteo_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_ticket_empresa_sorteo ON tecnolabo.sorteo_ticket_deliveries USING btree (empresa_id, sorteo_id);
CREATE INDEX IF NOT EXISTS idx_sorteo_ticket_status ON tecnolabo.sorteo_ticket_deliveries USING btree (empresa_id, status);
CREATE INDEX IF NOT EXISTS idx_sorteos_empresa ON tecnolabo.sorteos USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_stock_ubic_producto ON tecnolabo.inventario_stock_ubicacion USING btree (producto_id);
CREATE INDEX IF NOT EXISTS idx_stock_ubic_ubicacion ON tecnolabo.inventario_stock_ubicacion USING btree (ubicacion_id);
CREATE INDEX IF NOT EXISTS idx_suscripciones_cliente ON tecnolabo.suscripciones USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_suscripciones_empresa ON tecnolabo.suscripciones USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_suscripciones_plan ON tecnolabo.suscripciones USING btree (plan_id);
CREATE INDEX IF NOT EXISTS idx_tipificaciones_cliente ON tecnolabo.tipificaciones USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_tipificaciones_empresa ON tecnolabo.tipificaciones USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ubicaciones_empresa ON tecnolabo.inventario_ubicaciones USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ubicaciones_parent ON tecnolabo.inventario_ubicaciones USING btree (parent_id);
CREATE INDEX IF NOT EXISTS idx_ubicaciones_tipo ON tecnolabo.inventario_ubicaciones USING btree (tipo);
CREATE INDEX IF NOT EXISTS idx_udv_usuario ON tecnolabo.usuario_dashboard_views USING btree (usuario_id);
CREATE INDEX IF NOT EXISTS idx_usuario_modulos_usuario ON tecnolabo.usuario_modulos USING btree (usuario_id);
CREATE INDEX IF NOT EXISTS idx_usuarios_auth_user_id ON tecnolabo.usuarios USING btree (auth_user_id);
CREATE INDEX IF NOT EXISTS idx_ventas_cliente ON tecnolabo.ventas USING btree (cliente_id);
CREATE INDEX IF NOT EXISTS idx_ventas_empresa ON tecnolabo.ventas USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ventas_estado ON tecnolabo.ventas USING btree (estado);
CREATE INDEX IF NOT EXISTS idx_ventas_fecha ON tecnolabo.ventas USING btree (fecha);
CREATE INDEX IF NOT EXISTS idx_ventas_items_empresa ON tecnolabo.ventas_items USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ventas_items_producto ON tecnolabo.ventas_items USING btree (producto_id);
CREATE INDEX IF NOT EXISTS idx_ventas_items_venta ON tecnolabo.ventas_items USING btree (venta_id);
CREATE INDEX IF NOT EXISTS ix_caj_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_ajustes USING btree (empresa_id, periodo_id);
CREATE INDEX IF NOT EXISTS ix_ce_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_escalas USING btree (empresa_id, politica_id, orden);
CREATE INDEX IF NOT EXISTS ix_ceq_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_equipos USING btree (empresa_id, activo);
CREATE INDEX IF NOT EXISTS ix_ceqm_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_equipo_miembros USING btree (empresa_id, equipo_id);
CREATE INDEX IF NOT EXISTS ix_cli_vend_93405e10933cb8b99a0af6286dc9466b ON tecnolabo.clientes USING btree (empresa_id, vendedor_usuario_id);
CREATE INDEX IF NOT EXISTS ix_cli_vend_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.clientes USING btree (empresa_id, vendedor_usuario_id);
CREATE INDEX IF NOT EXISTS ix_clin_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_lineas USING btree (empresa_id, periodo_id, usuario_vendedor_id);
CREATE INDEX IF NOT EXISTS ix_cob_cliente_fecha ON tecnolabo.cobros_clientes USING btree (empresa_id, cliente_id, fecha_pago DESC);
CREATE INDEX IF NOT EXISTS ix_cob_cxc ON tecnolabo.cobros_clientes USING btree (empresa_id, cuenta_por_cobrar_id);
CREATE INDEX IF NOT EXISTS ix_cob_empresa ON tecnolabo.cobros_clientes USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS ix_cob_fecha ON tecnolabo.cobros_clientes USING btree (empresa_id, fecha_pago DESC);
CREATE INDEX IF NOT EXISTS ix_cp_act_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_politicas USING btree (empresa_id, activo);
CREATE INDEX IF NOT EXISTS ix_cper_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_periodos USING btree (empresa_id, fecha_inicio, fecha_fin);
CREATE INDEX IF NOT EXISTS ix_cpv_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.comision_politica_versiones USING btree (empresa_id, politica_id);
CREATE INDEX IF NOT EXISTS ix_cxc_cliente ON tecnolabo.cuentas_por_cobrar USING btree (empresa_id, cliente_id);
CREATE INDEX IF NOT EXISTS ix_cxc_empresa ON tecnolabo.cuentas_por_cobrar USING btree (empresa_id);
CREATE INDEX IF NOT EXISTS ix_cxc_estado_venc ON tecnolabo.cuentas_por_cobrar USING btree (empresa_id, estado, fecha_vencimiento);
CREATE INDEX IF NOT EXISTS ix_cxc_venta ON tecnolabo.cuentas_por_cobrar USING btree (empresa_id, venta_id);
CREATE INDEX IF NOT EXISTS ix_entidades_bancarias_empresa_activo ON tecnolabo.entidades_bancarias USING btree (empresa_id, activo);
CREATE INDEX IF NOT EXISTS ix_mk_cal_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.marketing_calendarios USING btree (empresa_id, cliente_id, mes);
CREATE INDEX IF NOT EXISTS ix_mk_com_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.marketing_comentarios USING btree (empresa_id, pieza_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_mk_hist_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.marketing_historial_estados USING btree (empresa_id, pieza_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS ix_mk_pz_cli_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.marketing_piezas USING btree (empresa_id, cliente_id);
CREATE INDEX IF NOT EXISTS ix_mk_pz_lim_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.marketing_piezas USING btree (empresa_id, fecha_limite);
CREATE INDEX IF NOT EXISTS ix_mk_pz_prod_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.marketing_piezas USING btree (empresa_id, estado_produccion);
CREATE INDEX IF NOT EXISTS ix_mk_pz_resp_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.marketing_piezas USING btree (empresa_id, responsable_id);
CREATE INDEX IF NOT EXISTS ix_paf_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyecto_archivos USING btree (empresa_id, proyecto_id);
CREATE INDEX IF NOT EXISTS ix_pc_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyecto_comentarios USING btree (empresa_id, proyecto_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_pe_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyecto_estados USING btree (empresa_id, activo, sort_order);
CREATE INDEX IF NOT EXISTS ix_peh_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyecto_estado_historial USING btree (empresa_id, proyecto_id, entered_at);
CREATE INDEX IF NOT EXISTS ix_ppc_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyecto_prioridades_config USING btree (empresa_id, activo, sort_order);
CREATE INDEX IF NOT EXISTS ix_pr_cli_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyectos USING btree (empresa_id, cliente_id);
CREATE INDEX IF NOT EXISTS ix_pr_est_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyectos USING btree (empresa_id, estado_id, archivado);
CREATE INDEX IF NOT EXISTS ix_pr_fp_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyectos USING btree (empresa_id, fecha_prometida);
CREATE INDEX IF NOT EXISTS ix_pr_rc_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyectos USING btree (empresa_id, responsable_comercial_id);
CREATE INDEX IF NOT EXISTS ix_pr_rt_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyectos USING btree (empresa_id, responsable_tecnico_id);
CREATE INDEX IF NOT EXISTS ix_pr_tip_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyectos USING btree (empresa_id, tipo_id);
CREATE INDEX IF NOT EXISTS ix_pt_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyecto_tipos USING btree (empresa_id, activo);
CREATE INDEX IF NOT EXISTS ix_ptar_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.proyecto_tareas USING btree (empresa_id, proyecto_id);
CREATE INDEX IF NOT EXISTS ix_ventas_pagos_detalle_empresa_fecha ON tecnolabo.ventas_pagos_detalle USING btree (empresa_id, fecha_pago);
CREATE INDEX IF NOT EXISTS ix_ventas_pagos_detalle_venta ON tecnolabo.ventas_pagos_detalle USING btree (venta_id);
CREATE INDEX IF NOT EXISTS ixctsc_c9ff055d5178c1e5686eb62017e3c4ff ON tecnolabo.cliente_tipos_servicio_catalogo USING btree (empresa_id, activo, orden);
CREATE INDEX IF NOT EXISTS movimientos_inventario_devolucion_idx ON tecnolabo.movimientos_inventario USING btree (empresa_id, devolucion_id);
CREATE INDEX IF NOT EXISTS pedidos_caja_armado_por_idx ON tecnolabo.pedidos_caja USING btree (empresa_id, armado_por_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pedidos_caja_empresa_estado_idx ON tecnolabo.pedidos_caja USING btree (empresa_id, estado, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS pedidos_caja_numero_uniq ON tecnolabo.pedidos_caja USING btree (empresa_id, numero) WHERE (numero IS NOT NULL);
CREATE INDEX IF NOT EXISTS pedidos_caja_venta_idx ON tecnolabo.pedidos_caja USING btree (empresa_id, venta_id);
CREATE UNIQUE INDEX IF NOT EXISTS producto_presentaciones_default_uniq ON tecnolabo.producto_presentaciones USING btree (producto_id) WHERE ((es_default = true) AND (activo = true));
CREATE INDEX IF NOT EXISTS producto_presentaciones_empresa_idx ON tecnolabo.producto_presentaciones USING btree (empresa_id);
CREATE UNIQUE INDEX IF NOT EXISTS producto_presentaciones_nombre_uniq ON tecnolabo.producto_presentaciones USING btree (producto_id, lower(nombre));
CREATE INDEX IF NOT EXISTS producto_presentaciones_producto_idx ON tecnolabo.producto_presentaciones USING btree (producto_id);
CREATE INDEX IF NOT EXISTS productos_discount_active_idx ON tecnolabo.productos USING btree (empresa_id, discount_ends_at) WHERE ((discount_type IS NOT NULL) AND (discount_value > (0)::numeric));
CREATE INDEX IF NOT EXISTS productos_oferta_semana_destacada_idx ON tecnolabo.productos USING btree (empresa_id) WHERE (oferta_semana_destacada = true);
CREATE UNIQUE INDEX IF NOT EXISTS proveedor_categorias_empresa_nombre_lower ON tecnolabo.proveedor_categorias USING btree (empresa_id, lower(TRIM(BOTH FROM nombre)));
CREATE UNIQUE INDEX IF NOT EXISTS proveedor_productos_un_principal ON tecnolabo.proveedor_productos USING btree (empresa_id, producto_id) WHERE es_principal;
CREATE UNIQUE INDEX IF NOT EXISTS uq_categorias_productos_empresa_nombre ON tecnolabo.categorias_productos USING btree (empresa_id, lower(TRIM(BOTH FROM nombre)));
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_campaign_recipients_phone ON tecnolabo.chat_campaign_recipients USING btree (campaign_id, phone_e164);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_campaign_templates_natural ON tecnolabo.chat_campaign_templates USING btree (empresa_id, channel_id, provider, name, language);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_flow_data_conversation_field ON tecnolabo.chat_flow_data USING btree (conversation_id, field_name);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_flow_data_session_field ON tecnolabo.chat_flow_data USING btree (flow_session_id, field_name);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_flow_sessions_one_active_per_conversation ON tecnolabo.chat_flow_sessions USING btree (conversation_id) WHERE (status = 'active'::text);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_msg_wa_id ON tecnolabo.chat_messages USING btree (wa_message_id) WHERE (wa_message_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_cxc_venta ON tecnolabo.cuentas_por_cobrar USING btree (venta_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_entidades_bancarias_codigo ON tecnolabo.entidades_bancarias USING btree (empresa_id, lower(codigo)) WHERE ((codigo IS NOT NULL) AND (codigo <> ''::text));
CREATE UNIQUE INDEX IF NOT EXISTS uq_entidades_bancarias_empresa_nombre ON tecnolabo.entidades_bancarias USING btree (empresa_id, lower(nombre));
CREATE UNIQUE INDEX IF NOT EXISTS uq_nota_credito_factura_estado_activo ON tecnolabo.nota_credito USING btree (factura_id) WHERE (estado_erp = ANY (ARRAY['borrador'::text, 'pendiente_envio_sifen'::text, 'aprobada'::text]));
CREATE UNIQUE INDEX IF NOT EXISTS uq_notificaciones_activa ON tecnolabo.notificaciones USING btree (empresa_id, producto_id, tipo) WHERE ((leida = false) AND (producto_id IS NOT NULL));
CREATE UNIQUE INDEX IF NOT EXISTS uq_producto_categoria_principal_unica ON tecnolabo.producto_categorias USING btree (empresa_id, producto_id) WHERE (es_principal = true);
CREATE UNIQUE INDEX IF NOT EXISTS uq_producto_categorias_triple ON tecnolabo.producto_categorias USING btree (empresa_id, producto_id, categoria_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_productos_codigo_barras ON tecnolabo.productos USING btree (empresa_id, codigo_barras) WHERE (codigo_barras IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_recibos_cobro ON tecnolabo.recibos_dinero USING btree (cobro_cliente_id) WHERE (cobro_cliente_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_recibos_empresa_numero ON tecnolabo.recibos_dinero USING btree (empresa_id, numero_recibo);
CREATE UNIQUE INDEX IF NOT EXISTS uq_recibos_venta_contado ON tecnolabo.recibos_dinero USING btree (venta_id) WHERE ((origen = 'venta_contado'::text) AND (venta_id IS NOT NULL));
CREATE UNIQUE INDEX IF NOT EXISTS uq_sifen_jobs_fe_activo ON tecnolabo.sifen_jobs USING btree (factura_electronica_id) WHERE (estado = ANY (ARRAY['pendiente'::text, 'procesando'::text]));
CREATE UNIQUE INDEX IF NOT EXISTS uq_sorteo_conv_activa ON tecnolabo.sorteo_conversaciones USING btree (sorteo_id, whatsapp_numero) WHERE (activa = true);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sorteo_cupones_sorteo_coupon_value ON tecnolabo.sorteo_cupones USING btree (sorteo_id, coupon_number_value) WHERE (coupon_number_value IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sorteo_entradas_idempotency_key ON tecnolabo.sorteo_entradas USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sorteo_rev_clicks_token ON tecnolabo.sorteo_revendedor_clicks USING btree (attribution_token);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sorteo_revendedores_sorteo_codigo_lower ON tecnolabo.sorteo_revendedores USING btree (sorteo_id, lower(TRIM(BOTH FROM codigo_referido)));
CREATE UNIQUE INDEX IF NOT EXISTS uq_sorteo_ticket_entrada_current ON tecnolabo.sorteo_ticket_deliveries USING btree (entrada_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sorteo_ticket_entrada_revision ON tecnolabo.sorteo_ticket_deliveries USING btree (entrada_id, template_revision);
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_ubicacion_principal_unica ON tecnolabo.inventario_stock_ubicacion USING btree (empresa_id, producto_id) WHERE (es_principal = true);
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_ubicacion_triple ON tecnolabo.inventario_stock_ubicacion USING btree (empresa_id, producto_id, ubicacion_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_ubicaciones_empresa_codigo ON tecnolabo.inventario_ubicaciones USING btree (empresa_id, lower(TRIM(BOTH FROM codigo))) WHERE ((codigo IS NOT NULL) AND (TRIM(BOTH FROM codigo) <> ''::text));
CREATE UNIQUE INDEX IF NOT EXISTS uq_udv_one_default_per_user ON tecnolabo.usuario_dashboard_views USING btree (usuario_id) WHERE (es_default IS TRUE);
CREATE INDEX IF NOT EXISTS ventas_caja_idx ON tecnolabo.ventas USING btree (empresa_id, caja_id);

-- ── FUNCIONES ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION tecnolabo._touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.empresa_id_actual()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tecnolabo'
AS $function$
  SELECT empresa_id
  FROM tecnolabo.usuarios
  WHERE lower(trim(COALESCE(email, ''))) = tecnolabo.jwt_email_normalized()
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.es_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tecnolabo'
AS $function$
  SELECT rol = 'super_admin'
  FROM tecnolabo.usuarios
  WHERE lower(trim(COALESCE(email, ''))) = tecnolabo.jwt_email_normalized()
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.fn_receta_costeo(p_receta_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'tecnolabo', 'public'
AS $function$
DECLARE
  v_costo_total       numeric := 0;
  v_precio_venta      numeric := 0;
  v_rendimiento       numeric := 1;
  v_unidades_posibles numeric;
  v_items             jsonb;
  v_producto_id       uuid;
BEGIN
  SELECT r.producto_id, COALESCE(r.rendimiento_cantidad, 1), COALESCE(p.precio_venta, 0)
    INTO v_producto_id, v_rendimiento, v_precio_venta
  FROM tecnolabo.recetas r
  JOIN tecnolabo.productos p ON p.id = r.producto_id
  WHERE r.id = p_receta_id;

  IF v_producto_id IS NULL THEN
    RETURN jsonb_build_object('error', 'receta_no_encontrada');
  END IF;

  WITH base AS (
    SELECT
      ri.id, ri.insumo_producto_id, pi.nombre AS insumo_nombre, ri.orden,
      ri.cantidad, ri.unidad_medida, COALESCE(ri.merma_pct, 0) AS merma_pct,
      pi.costo_promedio, pi.stock_actual,
      upper(trim(COALESCE(NULLIF(ri.unidad_medida, ''), pi.unidad_medida))) AS u_item,
      upper(trim(pi.unidad_medida)) AS u_ins
    FROM tecnolabo.receta_items ri
    JOIN tecnolabo.productos pi ON pi.id = ri.insumo_producto_id
    WHERE ri.receta_id = p_receta_id
  ),
  fam AS (
    SELECT b.*,
      CASE u_item WHEN 'G' THEN 1 WHEN 'GR' THEN 1 WHEN 'GRS' THEN 1 WHEN 'KG' THEN 1000
                  WHEN 'ML' THEN 1 WHEN 'L' THEN 1000 WHEN 'LT' THEN 1000 WHEN 'LTS' THEN 1000
                  WHEN 'UNIDAD' THEN 1 WHEN 'UNID' THEN 1 WHEN 'U' THEN 1 ELSE NULL END AS f_item,
      CASE u_ins  WHEN 'G' THEN 1 WHEN 'GR' THEN 1 WHEN 'GRS' THEN 1 WHEN 'KG' THEN 1000
                  WHEN 'ML' THEN 1 WHEN 'L' THEN 1000 WHEN 'LT' THEN 1000 WHEN 'LTS' THEN 1000
                  WHEN 'UNIDAD' THEN 1 WHEN 'UNID' THEN 1 WHEN 'U' THEN 1 ELSE NULL END AS f_ins,
      CASE
        WHEN u_item IN ('G','GR','GRS','KG') AND u_ins IN ('G','GR','GRS','KG') THEN true
        WHEN u_item IN ('ML','L','LT','LTS') AND u_ins IN ('ML','L','LT','LTS') THEN true
        WHEN u_item IN ('UNIDAD','UNID','U') AND u_ins IN ('UNIDAD','UNID','U') THEN true
        ELSE false
      END AS compat
    FROM base b
  ),
  item_calc AS (
    SELECT *,
      (CASE WHEN compat AND f_ins > 0 THEN cantidad * f_item / f_ins ELSE NULL END) AS cant_insumo,
      (CASE WHEN compat AND f_ins > 0 THEN (cantidad * f_item / f_ins) * (1 + merma_pct) ELSE NULL END) AS cantidad_efectiva,
      (CASE WHEN compat AND f_ins > 0 THEN (cantidad * f_item / f_ins) * (1 + merma_pct) * COALESCE(costo_promedio, 0) ELSE 0 END) AS subcosto,
      (CASE WHEN compat AND f_ins > 0 AND (cantidad * f_item / f_ins) * (1 + merma_pct) > 0
            THEN FLOOR(COALESCE(stock_actual, 0) / ((cantidad * f_item / f_ins) * (1 + merma_pct)))
            ELSE NULL END) AS unidades_aporte,
      (NOT compat) AS unidad_incompatible
    FROM fam
  )
  SELECT
    COALESCE(SUM(subcosto), 0),
    COALESCE(MIN(unidades_aporte), 0),
    COALESCE(jsonb_agg(jsonb_build_object(
      'item_id', id,
      'insumo_producto_id', insumo_producto_id,
      'insumo_nombre', insumo_nombre,
      'cantidad', cantidad,
      'unidad_medida', unidad_medida,
      'merma_pct', merma_pct,
      'costo_promedio', costo_promedio,
      'stock_actual', stock_actual,
      'subcosto', subcosto,
      'unidades_aporte', unidades_aporte,
      'unidad_incompatible', unidad_incompatible
    ) ORDER BY orden, insumo_nombre), '[]'::jsonb)
    INTO v_costo_total, v_unidades_posibles, v_items
  FROM item_calc;

  IF NOT EXISTS (SELECT 1 FROM tecnolabo.receta_items WHERE receta_id = p_receta_id) THEN
    v_unidades_posibles := NULL;
  END IF;

  RETURN jsonb_build_object(
    'receta_id', p_receta_id,
    'producto_id', v_producto_id,
    'rendimiento_cantidad', v_rendimiento,
    'costo_total', v_costo_total,
    'costo_unitario', CASE WHEN v_rendimiento > 0 THEN v_costo_total / v_rendimiento ELSE NULL END,
    'precio_venta', v_precio_venta,
    'margen_abs', v_precio_venta - (CASE WHEN v_rendimiento > 0 THEN v_costo_total / v_rendimiento ELSE 0 END),
    'margen_pct', CASE
      WHEN v_precio_venta > 0 AND v_rendimiento > 0
      THEN ROUND(((v_precio_venta - (v_costo_total / v_rendimiento)) / v_precio_venta * 100)::numeric, 2)
      ELSE NULL
    END,
    'unidades_posibles', v_unidades_posibles,
    'items', v_items
  );
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.incrementar_secuencia_producto(p_empresa_id uuid)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
      DECLARE v bigint;
      BEGIN
        INSERT INTO tecnolabo.productos_codigo_secuencia (empresa_id, last_value)
        VALUES (p_empresa_id, 1)
        ON CONFLICT (empresa_id) DO UPDATE
          SET last_value = tecnolabo.productos_codigo_secuencia.last_value + 1,
              updated_at = now()
        RETURNING last_value INTO v;
        RETURN v;
      END;
      $function$;

CREATE OR REPLACE FUNCTION tecnolabo.jwt_email_normalized()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'tecnolabo'
AS $function$
  SELECT lower(trim(COALESCE(auth.jwt() ->> 'email', '')));
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.neura_inbox_awaiting_reply_since_batch(p_schema text, p_empresa_id uuid, p_conversation_ids uuid[])
 RETURNS TABLE(conversation_id uuid, awaiting_since timestamp with time zone, client_turn_since timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  sch text := trim(both from coalesce(p_schema, ''));
BEGIN
  IF sch IS NULL OR sch = '' OR sch !~ '^(tecnolabo|public|er_[0-9a-f]{32}|erp_[a-z0-9_]+)$' THEN
    RAISE EXCEPTION 'schema no permitido: %', p_schema;
  END IF;

  RETURN QUERY EXECUTE format(
    $q$
    WITH conv AS (SELECT unnest($1::uuid[]) AS id),
    last_contact AS (
      SELECT DISTINCT ON (m.conversation_id)
        m.conversation_id,
        m.created_at AS at
      FROM %I.chat_messages m
      INNER JOIN conv c ON c.id = m.conversation_id
      WHERE m.empresa_id = $2::uuid
        AND m.from_me = false
        AND lower(coalesce(m.sender_type, 'contact')) IN ('contact')
      ORDER BY m.conversation_id, m.created_at DESC
    ),
    last_human AS (
      SELECT m.conversation_id, max(m.created_at) AS at
      FROM %I.chat_messages m
      INNER JOIN conv c ON c.id = m.conversation_id
      WHERE m.empresa_id = $2::uuid
        AND m.from_me = true
        AND lower(coalesce(m.sender_type, '')) = 'human'
      GROUP BY m.conversation_id
    ),
    last_global AS (
      SELECT DISTINCT ON (m.conversation_id)
        m.conversation_id,
        m.from_me,
        m.created_at AS at
      FROM %I.chat_messages m
      INNER JOIN conv c ON c.id = m.conversation_id
      WHERE m.empresa_id = $2::uuid
      ORDER BY m.conversation_id, m.created_at DESC
    )
    SELECT
      conv.id AS conversation_id,
      CASE
        WHEN lc.at IS NOT NULL AND lc.at > coalesce(lh.at, '-infinity'::timestamptz) THEN lc.at
        ELSE NULL::timestamptz
      END AS awaiting_since,
      CASE
        WHEN lc.at IS NOT NULL AND lc.at > coalesce(lh.at, '-infinity'::timestamptz) THEN NULL::timestamptz
        WHEN lg.from_me IS TRUE THEN lg.at
        ELSE NULL::timestamptz
      END AS client_turn_since
    FROM conv
    LEFT JOIN last_contact lc ON lc.conversation_id = conv.id
    LEFT JOIN last_human lh ON lh.conversation_id = conv.id
    LEFT JOIN last_global lg ON lg.conversation_id = conv.id
    $q$,
    sch
  )
  USING p_conversation_ids, p_empresa_id;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.next_numero_factura_empresa(p_empresa_id uuid, p_prefijo_default text DEFAULT 'FAC-'::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
    DECLARE
      v_prefijo text;
      v_num bigint;
      v_ancho int := 6;
    BEGIN
      IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'next_numero_factura_empresa: empresa_id es obligatorio';
      END IF;

      -- Inicializa contador si no existe (toma max numérico real de facturas de la empresa).
      IF NOT EXISTS (
        SELECT 1 FROM tecnolabo.factura_correlativos c WHERE c.empresa_id = p_empresa_id
      ) THEN
        SELECT
          COALESCE(
            (
              SELECT NULLIF(regexp_replace(f.numero_factura, '([0-9]+)$', ''), '')
              FROM tecnolabo.facturas f
              WHERE f.empresa_id = p_empresa_id
                AND f.numero_factura ~ '[0-9]+$'
              ORDER BY COALESCE(f.created_at, f.updated_at) DESC NULLS LAST, f.id DESC
              LIMIT 1
            ),
            NULLIF(btrim(p_prefijo_default), ''),
            'FAC-'
          ),
          COALESCE(
            (
              SELECT max((regexp_match(f.numero_factura, '([0-9]+)$'))[1]::bigint)
              FROM tecnolabo.facturas f
              WHERE f.empresa_id = p_empresa_id
                AND f.numero_factura ~ '[0-9]+$'
            ),
            0
          )
        INTO v_prefijo, v_num;

        INSERT INTO tecnolabo.factura_correlativos(empresa_id, prefijo, ultimo_numero)
        VALUES (p_empresa_id, v_prefijo, v_num)
        ON CONFLICT (empresa_id) DO NOTHING;
      END IF;

      UPDATE tecnolabo.factura_correlativos c
      SET
        prefijo = COALESCE(NULLIF(btrim(p_prefijo_default), ''), c.prefijo, 'FAC-'),
        ultimo_numero = c.ultimo_numero + 1,
        updated_at = now()
      WHERE c.empresa_id = p_empresa_id
      RETURNING c.prefijo, c.ultimo_numero
      INTO v_prefijo, v_num;

      IF v_num IS NULL THEN
        RAISE EXCEPTION 'No se pudo reservar correlativo de factura';
      END IF;

      RETURN COALESCE(v_prefijo, 'FAC-') || lpad(v_num::text, v_ancho, '0');
    END;
    $function$;

CREATE OR REPLACE FUNCTION tecnolabo.nota_credito_aplicar_aprobacion_set(p_data_schema text, p_nota_credito_id uuid, p_factura_id uuid, p_empresa_id uuid, p_monto numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_temp'
AS $function$
DECLARE
  s text := btrim(p_data_schema);
  fq text := quote_ident(btrim(p_data_schema));
  saldo_act numeric;
  otra uuid;
BEGIN
  IF s IS NULL OR s = '' THEN
    RAISE EXCEPTION 'nota_credito_aplicar_aprobacion_set: schema vacío';
  END IF;

  EXECUTE format(
    'SELECT id FROM %s.nota_credito
     WHERE factura_id = $1 AND empresa_id = $2 AND estado_erp = ''aprobada'' AND id <> $3
     LIMIT 1',
    fq
  ) INTO otra USING p_factura_id, p_empresa_id, p_nota_credito_id;
  IF otra IS NOT NULL THEN
    RAISE EXCEPTION 'Ya existe otra nota de crédito aprobada para esta factura';
  END IF;

  EXECUTE format(
    'SELECT saldo FROM %s.facturas WHERE id = $1 AND empresa_id = $2 FOR UPDATE',
    fq
  ) INTO saldo_act USING p_factura_id, p_empresa_id;

  IF saldo_act IS NULL THEN
    RAISE EXCEPTION 'Factura no encontrada';
  END IF;
  IF p_monto > saldo_act + 0.02 THEN
    RAISE EXCEPTION 'El monto de la NC (%) supera el saldo pendiente (%)', p_monto, saldo_act;
  END IF;

  EXECUTE format(
    'UPDATE %s.facturas SET
       saldo = GREATEST(0::numeric, saldo - $1),
       estado = CASE
         WHEN estado = ''Anulado'' THEN ''Anulado''
         WHEN GREATEST(0::numeric, saldo - $1) <= 0.0001 THEN ''Corregida NC''
         ELSE estado
       END,
       updated_at = now()
     WHERE id = $2 AND empresa_id = $3',
    fq
  ) USING p_monto, p_factura_id, p_empresa_id;

  EXECUTE format(
    'UPDATE %s.nota_credito SET estado_erp = ''aprobada'', updated_at = now()
     WHERE id = $1 AND empresa_id = $2 AND estado_erp <> ''anulada_borrador''',
    fq
  ) USING p_nota_credito_id, p_empresa_id;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.nota_credito_tras_aprobacion_set_transaccional(p_data_schema text, p_ne_id uuid, p_nc_id uuid, p_factura_id uuid, p_empresa_id uuid, p_monto numeric, p_ultima_consulta jsonb, p_sifen_aprobado_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_temp'
AS $function$
DECLARE
  sch text := btrim(p_data_schema);
  prev_ne text;
BEGIN
  IF sch IS NULL OR sch = '' THEN
    RAISE EXCEPTION 'nota_credito_tras_aprobacion_set_transaccional: schema vacío';
  END IF;

  EXECUTE format(
    'SELECT estado_sifen::text FROM %I.nota_credito_electronica WHERE id = $1 AND empresa_id = $2 FOR UPDATE',
    sch
  ) INTO prev_ne USING p_ne_id, p_empresa_id;

  IF prev_ne IS NULL THEN
    RAISE EXCEPTION 'nota_credito_electronica no encontrada';
  END IF;
  IF prev_ne = 'aprobado' THEN
    RETURN;
  END IF;

  EXECUTE format(
    'UPDATE %I.nota_credito_electronica SET
       estado_sifen = ''aprobado'',
       sifen_aprobado_at = $1,
       sifen_ultima_respuesta_consulta_lote = $2,
       last_response_json = $2,
       last_error = NULL,
       error = NULL,
       updated_at = now()
     WHERE id = $3 AND empresa_id = $4 AND estado_sifen <> ''aprobado''',
    sch
  ) USING p_sifen_aprobado_at, p_ultima_consulta, p_ne_id, p_empresa_id;

  PERFORM tecnolabo.nota_credito_aplicar_aprobacion_set(
    sch,
    p_nc_id,
    p_factura_id,
    p_empresa_id,
    p_monto
  );
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.puede_acceder_empresa(empresa_uuid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT tecnolabo.es_super_admin()
     OR empresa_uuid = tecnolabo.empresa_id_actual();
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.set_chat_contact_phone_normalized()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.phone_normalized := NULLIF(regexp_replace(COALESCE(NEW.phone_number, ''), '\D', '', 'g'), '');
  IF NEW.phone_normalized IS NOT NULL THEN
    NEW.phone_number := NEW.phone_normalized;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.set_crm_prospectos_updated()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  NEW.fecha_actualizacion = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.sorteos_ensure_order_from_chat(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa_id          uuid := (p->>'empresa_id')::uuid;
  v_sorteo_id           uuid := (p->>'sorteo_id')::uuid;
  v_conv_id             uuid := (p->>'chat_conversation_id')::uuid;
  v_flow_code           text := nullif(trim(p->>'flow_code'), '');
  v_idem                text := nullif(trim(p->>'idempotency_key'), '');
  v_wa                  text := trim(p->>'whatsapp_numero');
  v_nombre              text := trim(p->>'nombre_completo');
  v_cedula              text := nullif(trim(p->>'cedula'), '');
  v_ciudad              text := nullif(trim(p->>'ciudad'), '');
  v_qty                 int := coalesce((p->>'cantidad_boletos')::int, 0);
  v_comp_url            text := nullif(trim(p->>'comprobante_url'), '');
  v_validado_por        text := coalesce(nullif(trim(p->>'validado_por'), ''), 'chat_flow');

  v_monto_explicit      numeric := NULL;
  v_promo_nombre        text := nullif(trim(p->>'promo_nombre'), '');
  v_precio_regular_ref  numeric := NULL;

  v_revendedor_id       uuid := NULL;
  v_codigo_ref_snap     text := NULL;

  s                     record;
  v_entrada_id          uuid;
  v_numero_orden        int;
  v_cliente_id          uuid;
  v_monto_total         numeric;
  v_precio_fuente_ins   text;
  v_lista_calc          numeric;
  i                     int;
  v_num                 int;
  v_num_str             text;
  v_existing            record;
  v_cant_existente      int;
  v_mt_existente        numeric;
  v_promo_existente     text;
  v_pf_existente        text;
BEGIN
  IF v_empresa_id IS NULL OR v_sorteo_id IS NULL OR v_conv_id IS NULL OR v_idem IS NULL OR v_idem = '' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Faltan empresa_id, sorteo_id, chat_conversation_id o idempotency_key');
  END IF;
  IF v_wa = '' OR v_nombre = '' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Faltan whatsapp_numero o nombre_completo');
  END IF;
  IF v_qty < 1 THEN
    RETURN jsonb_build_object('ok', false, 'message', 'cantidad_boletos debe ser mayor a 0');
  END IF;

  IF p ? 'monto_compra' THEN
    BEGIN
      v_monto_explicit := NULLIF(trim(p->>'monto_compra'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_monto_explicit := NULL;
    END;
  END IF;
  IF v_monto_explicit IS NOT NULL AND v_monto_explicit <= 0 THEN
    v_monto_explicit := NULL;
  END IF;

  IF p ? 'precio_regular_referencia' THEN
    BEGIN
      v_precio_regular_ref := NULLIF(trim(p->>'precio_regular_referencia'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_precio_regular_ref := NULL;
    END;
  END IF;
  IF v_precio_regular_ref IS NOT NULL AND v_precio_regular_ref <= 0 THEN
    v_precio_regular_ref := NULL;
  END IF;

  v_codigo_ref_snap := nullif(trim(p->>'codigo_referido'), '');
  IF p ? 'revendedor_id' AND nullif(trim(p->>'revendedor_id'), '') IS NOT NULL THEN
    BEGIN
      v_revendedor_id := (p->>'revendedor_id')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_revendedor_id := NULL;
    END;
  END IF;

  SELECT e.id, e.numero_orden, e.estado_pago
  INTO v_existing
  FROM tecnolabo.sorteo_entradas e
  WHERE e.idempotency_key = v_idem
  LIMIT 1;

  IF FOUND THEN
    SELECT
      e.cantidad_boletos,
      e.monto_total,
      e.promo_nombre,
      e.precio_fuente
    INTO v_cant_existente, v_mt_existente, v_promo_existente, v_pf_existente
    FROM tecnolabo.sorteo_entradas e
    WHERE e.id = (v_existing).id;

    RETURN jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'message', 'Orden ya existía (idempotencia)',
      'entrada', jsonb_build_object(
        'id', (v_existing).id,
        'numero_orden', (v_existing).numero_orden,
        'cantidad_boletos', coalesce(v_cant_existente, v_qty),
        'monto_total', v_mt_existente,
        'promo_nombre', coalesce(v_promo_existente, ''),
        'precio_fuente', coalesce(v_pf_existente, 'lista'),
        'estado_pago', (v_existing).estado_pago
      ),
      'cupones', (
        SELECT coalesce(jsonb_agg(
          jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
          ORDER BY c.numero_cupon
        ), '[]'::jsonb)
        FROM tecnolabo.sorteo_cupones c
        WHERE c.entrada_id = (v_existing).id
      )
    );
  END IF;

  SELECT * INTO s FROM tecnolabo.sorteos WHERE id = v_sorteo_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Sorteo no encontrado');
  END IF;
  IF s.empresa_id IS DISTINCT FROM v_empresa_id THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no pertenece a la empresa indicada');
  END IF;
  IF s.estado IS DISTINCT FROM 'activo' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no está activo');
  END IF;
  IF s.total_boletos_vendidos + v_qty > s.max_boletos THEN
    RETURN jsonb_build_object('ok', false, 'message', 'No hay boletos disponibles para esta cantidad');
  END IF;

  v_lista_calc := s.precio_por_boleto * v_qty;

  IF v_monto_explicit IS NOT NULL THEN
    v_monto_total := v_monto_explicit;
    v_precio_fuente_ins := 'promo';
    IF v_precio_regular_ref IS NULL THEN
      v_precio_regular_ref := v_lista_calc;
    END IF;
  ELSE
    v_monto_total := v_lista_calc;
    v_precio_fuente_ins := 'lista';
    v_precio_regular_ref := NULL;
  END IF;

  SELECT id INTO v_cliente_id
  FROM tecnolabo.clientes
  WHERE empresa_id = v_empresa_id
    AND deleted_at IS NULL
    AND (
      (v_cedula IS NOT NULL AND documento IS NOT NULL AND trim(documento) = v_cedula)
      OR (trim(telefono) = v_wa)
    )
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    INSERT INTO tecnolabo.clientes (
      empresa_id, tipo_cliente, nombre_contacto, nombre, documento, telefono, ciudad, origen
    ) VALUES (
      v_empresa_id, 'persona', v_nombre, v_nombre, v_cedula, v_wa, v_ciudad, 'SORTEO_CHAT'
    )
    RETURNING id INTO v_cliente_id;
  END IF;

  v_numero_orden := s.ultimo_numero_orden + 1;

  IF v_revendedor_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM tecnolabo.sorteo_revendedores r
      WHERE r.id = v_revendedor_id
        AND r.empresa_id = v_empresa_id
        AND r.sorteo_id = v_sorteo_id
        AND r.activo = true
    ) THEN
      v_revendedor_id := NULL;
      v_codigo_ref_snap := NULL;
    END IF;
  ELSE
    v_codigo_ref_snap := NULL;
  END IF;

  INSERT INTO tecnolabo.sorteo_entradas (
    empresa_id,
    sorteo_id,
    conversacion_id,
    cliente_id,
    whatsapp_numero,
    nombre_participante,
    documento,
    cantidad_boletos,
    monto_total,
    moneda,
    estado_pago,
    comprobante_url,
    validado_por,
    numero_orden,
    chat_conversation_id,
    flow_code,
    idempotency_key,
    promo_nombre,
    precio_fuente,
    precio_regular_referencia,
    revendedor_id,
    codigo_referido_snapshot
  ) VALUES (
    v_empresa_id,
    v_sorteo_id,
    NULL,
    v_cliente_id,
    v_wa,
    v_nombre,
    v_cedula,
    v_qty,
    v_monto_total,
    'PYG',
    'pendiente_revision',
    v_comp_url,
    v_validado_por,
    v_numero_orden,
    v_conv_id,
    v_flow_code,
    v_idem,
    v_promo_nombre,
    v_precio_fuente_ins,
    v_precio_regular_ref,
    v_revendedor_id,
    v_codigo_ref_snap
  )
  RETURNING id INTO v_entrada_id;

  FOR i IN 1..v_qty LOOP
    v_num := s.ultimo_numero_cupon + i;
    v_num_str := lpad(v_num::text, 4, '0');
    INSERT INTO tecnolabo.sorteo_cupones (empresa_id, sorteo_id, entrada_id, numero_cupon)
    VALUES (v_empresa_id, v_sorteo_id, v_entrada_id, v_num_str);
  END LOOP;

  UPDATE tecnolabo.sorteos SET
    total_boletos_vendidos = total_boletos_vendidos + v_qty,
    ultimo_numero_cupon = s.ultimo_numero_cupon + v_qty,
    ultimo_numero_orden = v_numero_orden,
    updated_at = now()
  WHERE id = v_sorteo_id;

  RETURN jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'message', 'Orden y cupones creados',
    'entrada', jsonb_build_object(
      'id', v_entrada_id,
      'numero_orden', v_numero_orden,
      'cantidad_boletos', v_qty,
      'monto_total', v_monto_total,
      'promo_nombre', coalesce(v_promo_nombre, ''),
      'precio_fuente', v_precio_fuente_ins,
      'estado_pago', 'pendiente_revision'
    ),
    'cupones', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
        ORDER BY c.numero_cupon
      ), '[]'::jsonb)
      FROM tecnolabo.sorteo_cupones c
      WHERE c.entrada_id = v_entrada_id
    )
  );

EXCEPTION
  WHEN unique_violation THEN
    SELECT e.id, e.numero_orden, e.estado_pago
    INTO v_existing
    FROM tecnolabo.sorteo_entradas e
    WHERE e.idempotency_key = v_idem
    LIMIT 1;
    IF FOUND THEN
      SELECT
        e.cantidad_boletos,
        e.monto_total,
        e.promo_nombre,
        e.precio_fuente
      INTO v_cant_existente, v_mt_existente, v_promo_existente, v_pf_existente
      FROM tecnolabo.sorteo_entradas e
      WHERE e.id = (v_existing).id;
      RETURN jsonb_build_object(
        'ok', true,
        'idempotent', true,
        'message', 'Orden ya existía (carrera concurrente)',
        'entrada', jsonb_build_object(
          'id', (v_existing).id,
          'numero_orden', (v_existing).numero_orden,
          'cantidad_boletos', coalesce(v_cant_existente, v_qty),
          'monto_total', v_mt_existente,
          'promo_nombre', coalesce(v_promo_existente, ''),
          'precio_fuente', coalesce(v_pf_existente, 'lista'),
          'estado_pago', (v_existing).estado_pago
        ),
        'cupones', (
          SELECT coalesce(jsonb_agg(
            jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
            ORDER BY c.numero_cupon
          ), '[]'::jsonb)
          FROM tecnolabo.sorteo_cupones c
          WHERE c.entrada_id = (v_existing).id
        )
      );
    END IF;
    RETURN jsonb_build_object('ok', false, 'message', 'Error de unicidad al crear orden');
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.sorteos_registrar_compra_n8n(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa_id       uuid := (p->>'empresa_id')::uuid;
  v_sorteo_id        uuid := (p->>'sorteo_id')::uuid;
  v_wa               text := trim(p->>'whatsapp_numero');
  v_nombre           text := trim(p->>'nombre_completo');
  v_cedula           text := nullif(trim(p->>'cedula'), '');
  v_celular          text := nullif(trim(p->>'celular'), '');
  v_ciudad           text := nullif(trim(p->>'ciudad'), '');
  v_qty              int := coalesce((p->>'cantidad_boletos')::int, 0);
  v_fecha_pago       timestamptz := nullif(p->>'fecha_pago', '')::timestamptz;
  v_monto_pago       numeric := coalesce((p->>'monto_pago')::numeric, 0);
  v_banco            text := nullif(trim(p->>'banco_origen'), '');
  v_comp_url         text := p->>'comprobante_url';
  v_ultimo_msg       text := p->>'ultimo_mensaje';

  s                  record;
  v_cliente_id       uuid;
  v_conv_id          uuid;
  v_entrada_id       uuid;
  v_monto_total      numeric;
  i                  int;
  v_num              int;
  v_num_str          text;
BEGIN
  IF v_empresa_id IS NULL OR v_sorteo_id IS NULL OR v_wa = '' OR v_nombre = '' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Faltan datos obligatorios (empresa_id, sorteo_id, whatsapp_numero, nombre_completo)');
  END IF;
  IF v_qty < 1 THEN
    RETURN jsonb_build_object('ok', false, 'message', 'cantidad_boletos debe ser mayor a 0');
  END IF;

  SELECT * INTO s FROM tecnolabo.sorteos WHERE id = v_sorteo_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Sorteo no encontrado');
  END IF;
  IF s.empresa_id IS DISTINCT FROM v_empresa_id THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no pertenece a la empresa indicada');
  END IF;
  IF s.estado IS DISTINCT FROM 'activo' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no está activo');
  END IF;
  IF s.total_boletos_vendidos + v_qty > s.max_boletos THEN
    RETURN jsonb_build_object('ok', false, 'message', 'No hay boletos disponibles para esta cantidad');
  END IF;

  v_monto_total := s.precio_por_boleto * v_qty;

  -- Cliente: por documento o teléfono en la empresa
  SELECT id INTO v_cliente_id
  FROM tecnolabo.clientes
  WHERE empresa_id = v_empresa_id
    AND deleted_at IS NULL
    AND (
      (v_cedula IS NOT NULL AND documento IS NOT NULL AND trim(documento) = v_cedula)
      OR (v_celular IS NOT NULL AND telefono IS NOT NULL AND trim(telefono) = v_celular)
    )
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    INSERT INTO tecnolabo.clientes (
      empresa_id, tipo_cliente, nombre_contacto, nombre, documento, telefono, ciudad, origen
    ) VALUES (
      v_empresa_id, 'persona', v_nombre, v_nombre, v_cedula, coalesce(v_celular, v_wa), v_ciudad, 'SORTEO'
    )
    RETURNING id INTO v_cliente_id;
  END IF;

  SELECT id INTO v_conv_id
  FROM tecnolabo.sorteo_conversaciones
  WHERE sorteo_id = v_sorteo_id AND whatsapp_numero = v_wa AND activa = true
  LIMIT 1;

  IF v_conv_id IS NULL THEN
    INSERT INTO tecnolabo.sorteo_conversaciones (
      empresa_id, sorteo_id, whatsapp_numero, cliente_id, estado, ultimo_mensaje, cantidad_boletos, datos_cliente
    ) VALUES (
      v_empresa_id, v_sorteo_id, v_wa, v_cliente_id, 'paid_confirmed', v_ultimo_msg, v_qty,
      jsonb_build_object('nombre_completo', v_nombre, 'cedula', v_cedula, 'celular', v_celular, 'ciudad', v_ciudad)
    )
    RETURNING id INTO v_conv_id;
  ELSE
    UPDATE tecnolabo.sorteo_conversaciones SET
      cliente_id = coalesce(v_cliente_id, cliente_id),
      estado = 'paid_confirmed',
      ultimo_mensaje = coalesce(v_ultimo_msg, ultimo_mensaje),
      cantidad_boletos = v_qty,
      datos_cliente = coalesce(datos_cliente, '{}'::jsonb) || jsonb_build_object(
        'nombre_completo', v_nombre, 'cedula', v_cedula, 'celular', v_celular, 'ciudad', v_ciudad
      ),
      updated_at = now()
    WHERE id = v_conv_id;
  END IF;

  INSERT INTO tecnolabo.sorteo_entradas (
    empresa_id, sorteo_id, conversacion_id, cliente_id, whatsapp_numero, nombre_participante, documento,
    cantidad_boletos, monto_total, moneda, estado_pago, fecha_pago, monto_pagado, banco_origen, comprobante_url, validado_por
  ) VALUES (
    v_empresa_id, v_sorteo_id, v_conv_id, v_cliente_id, v_wa, v_nombre, v_cedula,
    v_qty, v_monto_total, 'PYG', 'confirmado', v_fecha_pago, v_monto_pago, v_banco, v_comp_url, 'n8n'
  )
  RETURNING id INTO v_entrada_id;

  FOR i IN 1..v_qty LOOP
    v_num := s.ultimo_numero_cupon + i;
    v_num_str := lpad(v_num::text, 4, '0');
    INSERT INTO tecnolabo.sorteo_cupones (empresa_id, sorteo_id, entrada_id, numero_cupon)
    VALUES (v_empresa_id, v_sorteo_id, v_entrada_id, v_num_str);
  END LOOP;

  UPDATE tecnolabo.sorteos SET
    total_boletos_vendidos = total_boletos_vendidos + v_qty,
    ultimo_numero_cupon = s.ultimo_numero_cupon + v_qty,
    updated_at = now()
  WHERE id = v_sorteo_id;

  RETURN jsonb_build_object(
    'ok', true,
    'message', 'Compra registrada correctamente',
    'cliente', jsonb_build_object('id', v_cliente_id, 'nombre', v_nombre),
    'conversacion', jsonb_build_object('id', v_conv_id, 'estado', 'paid_confirmed'),
    'entrada', jsonb_build_object(
      'id', v_entrada_id,
      'cantidad_boletos', v_qty,
      'monto_total', v_monto_total,
      'estado_pago', 'confirmado'
    ),
    'cupones', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
        ORDER BY c.numero_cupon
      ), '[]'::jsonb)
      FROM tecnolabo.sorteo_cupones c
      WHERE c.entrada_id = v_entrada_id
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.touch_cajas_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.touch_pedidos_caja_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.touch_producto_presentaciones_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.trg_clientes_tipo_servicio_requiere_catalogo()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  sch   text := TG_TABLE_SCHEMA;
  tslug text;
  ok    boolean;
BEGIN
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') AND NEW.empresa_id IS NOT NULL THEN
    tslug := NEW.tipo_servicio_cliente;
    IF tslug IS NULL OR btrim(tslug) = '' THEN
      NEW.tipo_servicio_cliente := NULL;
    ELSE
      NEW.tipo_servicio_cliente := lower(btrim(tslug));
      tslug := NEW.tipo_servicio_cliente;
      EXECUTE format(
        $f$
        SELECT EXISTS(
          SELECT 1
          FROM %I.cliente_tipos_servicio_catalogo t
          WHERE t.empresa_id = $1
            AND t.slug = $2
        )
        $f$,
        sch
      ) INTO ok USING NEW.empresa_id, tslug;
      IF NOT coalesce(ok, false) THEN
        RAISE EXCEPTION 'tipo_servicio_cliente inexistente en el catálogo: % (empresa %, schema %)', tslug, NEW.empresa_id, sch
          USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION tecnolabo.trg_usuario_modulos_validar_modulo_empresa()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa_id uuid;
BEGIN
  SELECT u.empresa_id INTO v_empresa_id
  FROM tecnolabo.usuarios u
  WHERE u.id = NEW.usuario_id;

  IF v_empresa_id IS NULL THEN
    RAISE EXCEPTION 'usuario_modulos: el usuario % no tiene empresa asignada', NEW.usuario_id
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM tecnolabo.empresa_modulos em
    WHERE em.empresa_id = v_empresa_id
      AND em.modulo_id = NEW.modulo_id
      AND em.activo IS TRUE
  ) THEN
    RAISE EXCEPTION 'usuario_modulos: el módulo % no está habilitado para la empresa del usuario', NEW.modulo_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

-- ── TRIGGERS ─────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS "cajas_touch" ON "tecnolabo"."cajas";
CREATE TRIGGER cajas_touch BEFORE UPDATE ON tecnolabo.cajas FOR EACH ROW EXECUTE FUNCTION tecnolabo.touch_cajas_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_agents_updated" ON "tecnolabo"."chat_agents";
CREATE TRIGGER tr_chat_agents_updated BEFORE UPDATE ON tecnolabo.chat_agents FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_campaign_jobs_updated" ON "tecnolabo"."chat_campaign_jobs";
CREATE TRIGGER tr_chat_campaign_jobs_updated BEFORE UPDATE ON tecnolabo.chat_campaign_jobs FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_campaign_recipients_updated" ON "tecnolabo"."chat_campaign_recipients";
CREATE TRIGGER tr_chat_campaign_recipients_updated BEFORE UPDATE ON tecnolabo.chat_campaign_recipients FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_campaign_templates_updated" ON "tecnolabo"."chat_campaign_templates";
CREATE TRIGGER tr_chat_campaign_templates_updated BEFORE UPDATE ON tecnolabo.chat_campaign_templates FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_campaigns_updated" ON "tecnolabo"."chat_campaigns";
CREATE TRIGGER tr_chat_campaigns_updated BEFORE UPDATE ON tecnolabo.chat_campaigns FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_channel_quick_replies_updated" ON "tecnolabo"."chat_channel_quick_replies";
CREATE TRIGGER tr_chat_channel_quick_replies_updated BEFORE UPDATE ON tecnolabo.chat_channel_quick_replies FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_channels_updated" ON "tecnolabo"."chat_channels";
CREATE TRIGGER tr_chat_channels_updated BEFORE UPDATE ON tecnolabo.chat_channels FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_comp_val_updated" ON "tecnolabo"."chat_comprobante_validaciones";
CREATE TRIGGER tr_chat_comp_val_updated BEFORE UPDATE ON tecnolabo.chat_comprobante_validaciones FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_contacts_phone_normalized" ON "tecnolabo"."chat_contacts";
CREATE TRIGGER tr_chat_contacts_phone_normalized BEFORE INSERT OR UPDATE OF phone_number ON tecnolabo.chat_contacts FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_chat_contact_phone_normalized();
DROP TRIGGER IF EXISTS "tr_chat_contacts_updated" ON "tecnolabo"."chat_contacts";
CREATE TRIGGER tr_chat_contacts_updated BEFORE UPDATE ON tecnolabo.chat_contacts FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_conversations_updated" ON "tecnolabo"."chat_conversations";
CREATE TRIGGER tr_chat_conversations_updated BEFORE UPDATE ON tecnolabo.chat_conversations FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_empresa_operator_roles_updated" ON "tecnolabo"."chat_empresa_operator_roles";
CREATE TRIGGER tr_chat_empresa_operator_roles_updated BEFORE UPDATE ON tecnolabo.chat_empresa_operator_roles FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_cfr_rules_updated" ON "tecnolabo"."chat_flow_recontact_rules";
CREATE TRIGGER tr_cfr_rules_updated BEFORE UPDATE ON tecnolabo.chat_flow_recontact_rules FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_flows_updated" ON "tecnolabo"."chat_flows";
CREATE TRIGGER tr_chat_flows_updated BEFORE UPDATE ON tecnolabo.chat_flows FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_omn_sched_updated" ON "tecnolabo"."chat_omnicanal_work_schedules";
CREATE TRIGGER tr_chat_omn_sched_updated BEFORE UPDATE ON tecnolabo.chat_omnicanal_work_schedules FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_queues_updated" ON "tecnolabo"."chat_queues";
CREATE TRIGGER tr_chat_queues_updated BEFORE UPDATE ON tecnolabo.chat_queues FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_chat_usuario_omnicanal_updated" ON "tecnolabo"."chat_usuario_omnicanal";
CREATE TRIGGER tr_chat_usuario_omnicanal_updated BEFORE UPDATE ON tecnolabo.chat_usuario_omnicanal FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "cliente_perfil_tributario_updated_at" ON "tecnolabo"."cliente_perfil_tributario";
CREATE TRIGGER cliente_perfil_tributario_updated_at BEFORE UPDATE ON tecnolabo.cliente_perfil_tributario FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "cliente_tipos_servicio_catalogo_updated_at" ON "tecnolabo"."cliente_tipos_servicio_catalogo";
CREATE TRIGGER cliente_tipos_servicio_catalogo_updated_at BEFORE UPDATE ON tecnolabo.cliente_tipos_servicio_catalogo FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "trg_clientes_tipo_servicio_catalogo" ON "tecnolabo"."clientes";
CREATE TRIGGER trg_clientes_tipo_servicio_catalogo BEFORE INSERT OR UPDATE OF tipo_servicio_cliente ON tecnolabo.clientes FOR EACH ROW EXECUTE FUNCTION tecnolabo.trg_clientes_tipo_servicio_requiere_catalogo();
DROP TRIGGER IF EXISTS "tr_comision_equipos_updated" ON "tecnolabo"."comision_equipos";
CREATE TRIGGER tr_comision_equipos_updated BEFORE UPDATE ON tecnolabo.comision_equipos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_comision_escalas_updated" ON "tecnolabo"."comision_escalas";
CREATE TRIGGER tr_comision_escalas_updated BEFORE UPDATE ON tecnolabo.comision_escalas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_comision_periodos_updated" ON "tecnolabo"."comision_periodos";
CREATE TRIGGER tr_comision_periodos_updated BEFORE UPDATE ON tecnolabo.comision_periodos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_comision_politicas_updated" ON "tecnolabo"."comision_politicas";
CREATE TRIGGER tr_comision_politicas_updated BEFORE UPDATE ON tecnolabo.comision_politicas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "compras_updated_at" ON "tecnolabo"."compras";
CREATE TRIGGER compras_updated_at BEFORE UPDATE ON tecnolabo.compras FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "crm_etapas_updated_at" ON "tecnolabo"."crm_etapas";
CREATE TRIGGER crm_etapas_updated_at BEFORE UPDATE ON tecnolabo.crm_etapas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "crm_notas_updated_at" ON "tecnolabo"."crm_notas";
CREATE TRIGGER crm_notas_updated_at BEFORE UPDATE ON tecnolabo.crm_notas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "crm_prospectos_updated_at" ON "tecnolabo"."crm_prospectos";
CREATE TRIGGER crm_prospectos_updated_at BEFORE UPDATE ON tecnolabo.crm_prospectos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_crm_prospectos_updated();
DROP TRIGGER IF EXISTS "empresa_sifen_config_updated_at" ON "tecnolabo"."empresa_sifen_config";
CREATE TRIGGER empresa_sifen_config_updated_at BEFORE UPDATE ON tecnolabo.empresa_sifen_config FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "factura_electronica_updated_at" ON "tecnolabo"."factura_electronica";
CREATE TRIGGER factura_electronica_updated_at BEFORE UPDATE ON tecnolabo.factura_electronica FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "facturas_updated_at" ON "tecnolabo"."facturas";
CREATE TRIGGER facturas_updated_at BEFORE UPDATE ON tecnolabo.facturas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_marketing_calendarios_updated" ON "tecnolabo"."marketing_calendarios";
CREATE TRIGGER tr_marketing_calendarios_updated BEFORE UPDATE ON tecnolabo.marketing_calendarios FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_marketing_piezas_updated" ON "tecnolabo"."marketing_piezas";
CREATE TRIGGER tr_marketing_piezas_updated BEFORE UPDATE ON tecnolabo.marketing_piezas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "marketing_tasks_updated_at" ON "tecnolabo"."marketing_tasks";
CREATE TRIGGER marketing_tasks_updated_at BEFORE UPDATE ON tecnolabo.marketing_tasks FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "movimientos_updated_at" ON "tecnolabo"."movimientos_inventario";
CREATE TRIGGER movimientos_updated_at BEFORE UPDATE ON tecnolabo.movimientos_inventario FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "nota_credito_updated_at" ON "tecnolabo"."nota_credito";
CREATE TRIGGER nota_credito_updated_at BEFORE UPDATE ON tecnolabo.nota_credito FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "nota_credito_electronica_updated_at" ON "tecnolabo"."nota_credito_electronica";
CREATE TRIGGER nota_credito_electronica_updated_at BEFORE UPDATE ON tecnolabo.nota_credito_electronica FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "pedidos_caja_touch" ON "tecnolabo"."pedidos_caja";
CREATE TRIGGER pedidos_caja_touch BEFORE UPDATE ON tecnolabo.pedidos_caja FOR EACH ROW EXECUTE FUNCTION tecnolabo.touch_pedidos_caja_updated_at();
DROP TRIGGER IF EXISTS "planes_updated_at" ON "tecnolabo"."planes";
CREATE TRIGGER planes_updated_at BEFORE UPDATE ON tecnolabo.planes FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "producto_presentaciones_touch" ON "tecnolabo"."producto_presentaciones";
CREATE TRIGGER producto_presentaciones_touch BEFORE UPDATE ON tecnolabo.producto_presentaciones FOR EACH ROW EXECUTE FUNCTION tecnolabo.touch_producto_presentaciones_updated_at();
DROP TRIGGER IF EXISTS "productos_updated_at" ON "tecnolabo"."productos";
CREATE TRIGGER productos_updated_at BEFORE UPDATE ON tecnolabo.productos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "proveedor_categorias_updated_at" ON "tecnolabo"."proveedor_categorias";
CREATE TRIGGER proveedor_categorias_updated_at BEFORE UPDATE ON tecnolabo.proveedor_categorias FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "proveedor_productos_updated_at" ON "tecnolabo"."proveedor_productos";
CREATE TRIGGER proveedor_productos_updated_at BEFORE UPDATE ON tecnolabo.proveedor_productos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "proveedores_updated_at" ON "tecnolabo"."proveedores";
CREATE TRIGGER proveedores_updated_at BEFORE UPDATE ON tecnolabo.proveedores FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_proyecto_comentarios_updated" ON "tecnolabo"."proyecto_comentarios";
CREATE TRIGGER tr_proyecto_comentarios_updated BEFORE UPDATE ON tecnolabo.proyecto_comentarios FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_proyecto_estados_updated" ON "tecnolabo"."proyecto_estados";
CREATE TRIGGER tr_proyecto_estados_updated BEFORE UPDATE ON tecnolabo.proyecto_estados FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_proyecto_prioridades_config_updated" ON "tecnolabo"."proyecto_prioridades_config";
CREATE TRIGGER tr_proyecto_prioridades_config_updated BEFORE UPDATE ON tecnolabo.proyecto_prioridades_config FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_proyecto_tareas_updated" ON "tecnolabo"."proyecto_tareas";
CREATE TRIGGER tr_proyecto_tareas_updated BEFORE UPDATE ON tecnolabo.proyecto_tareas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_proyecto_tipos_updated" ON "tecnolabo"."proyecto_tipos";
CREATE TRIGGER tr_proyecto_tipos_updated BEFORE UPDATE ON tecnolabo.proyecto_tipos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_proyectos_updated" ON "tecnolabo"."proyectos";
CREATE TRIGGER tr_proyectos_updated BEFORE UPDATE ON tecnolabo.proyectos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "trg_receta_items_updated_at" ON "tecnolabo"."receta_items";
CREATE TRIGGER trg_receta_items_updated_at BEFORE UPDATE ON tecnolabo.receta_items FOR EACH ROW EXECUTE FUNCTION tecnolabo._touch_updated_at();
DROP TRIGGER IF EXISTS "trg_recetas_updated_at" ON "tecnolabo"."recetas";
CREATE TRIGGER trg_recetas_updated_at BEFORE UPDATE ON tecnolabo.recetas FOR EACH ROW EXECUTE FUNCTION tecnolabo._touch_updated_at();
DROP TRIGGER IF EXISTS "tr_sorteo_conv_updated" ON "tecnolabo"."sorteo_conversaciones";
CREATE TRIGGER tr_sorteo_conv_updated BEFORE UPDATE ON tecnolabo.sorteo_conversaciones FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_sorteo_ent_updated" ON "tecnolabo"."sorteo_entradas";
CREATE TRIGGER tr_sorteo_ent_updated BEFORE UPDATE ON tecnolabo.sorteo_entradas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_sorteo_revendedores_updated" ON "tecnolabo"."sorteo_revendedores";
CREATE TRIGGER tr_sorteo_revendedores_updated BEFORE UPDATE ON tecnolabo.sorteo_revendedores FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_sorteo_ticket_deliveries_updated" ON "tecnolabo"."sorteo_ticket_deliveries";
CREATE TRIGGER tr_sorteo_ticket_deliveries_updated BEFORE UPDATE ON tecnolabo.sorteo_ticket_deliveries FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_sorteos_updated" ON "tecnolabo"."sorteos";
CREATE TRIGGER tr_sorteos_updated BEFORE UPDATE ON tecnolabo.sorteos FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tipificaciones_updated_at" ON "tecnolabo"."tipificaciones";
CREATE TRIGGER tipificaciones_updated_at BEFORE UPDATE ON tecnolabo.tipificaciones FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "tr_usuario_modulos_validar_empresa" ON "tecnolabo"."usuario_modulos";
CREATE TRIGGER tr_usuario_modulos_validar_empresa BEFORE INSERT OR UPDATE OF modulo_id, usuario_id ON tecnolabo.usuario_modulos FOR EACH ROW EXECUTE FUNCTION tecnolabo.trg_usuario_modulos_validar_modulo_empresa();
DROP TRIGGER IF EXISTS "ventas_updated_at" ON "tecnolabo"."ventas";
CREATE TRIGGER ventas_updated_at BEFORE UPDATE ON tecnolabo.ventas FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();
DROP TRIGGER IF EXISTS "ventas_items_updated_at" ON "tecnolabo"."ventas_items";
CREATE TRIGGER ventas_items_updated_at BEFORE UPDATE ON tecnolabo.ventas_items FOR EACH ROW EXECUTE FUNCTION tecnolabo.set_updated_at();

-- ── ROW LEVEL SECURITY ───────────────────────────────────────────────────────

ALTER TABLE "tecnolabo"."caja_movimientos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."cajas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."categorias_productos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_agents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_campaign_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_campaign_jobs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_campaign_recipients" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_campaign_templates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_campaigns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_channel_quick_replies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_channels" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_comprobante_validaciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_contacts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_conversation_closures" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_conversations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_empresa_operator_roles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_data" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_node_blocks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_nodes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_options" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_recontact_rules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_recontact_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flow_sessions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_flows" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_messages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_omnicanal_work_schedules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_queue_channels" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_queue_closure_states" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_queue_closure_substates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_queue_supervisors" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_queues" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_routing_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_supervisor_agents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."chat_usuario_omnicanal" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."cliente_historial" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."cliente_obligaciones_tributarias" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."cliente_perfil_tributario" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."cliente_tipos_servicio_catalogo" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."clientes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."cobros_clientes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_ajustes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_equipo_miembros" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_equipos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_escalas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_lineas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_periodos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_politica_versiones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."comision_politicas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."compras" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."crm_etapas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."crm_notas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."crm_prospectos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."cuentas_por_cobrar" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."dashboard_views" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."empresa_autoimpresor_config" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."empresa_dashboard_views" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."empresa_facturacion_modo" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."empresa_modulos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."empresa_sifen_config" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."empresas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."entidades_bancarias" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."factura_autoimpresor" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."factura_correlativos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."factura_electronica" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."factura_electronica_evento" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."factura_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."facturas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."gastos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."imports_audit" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."inventario_stock_ubicacion" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."inventario_ubicaciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."marketing_calendarios" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."marketing_comentarios" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."marketing_historial_estados" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."marketing_piezas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."marketing_tasks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."modulos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."movimientos_inventario" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."nota_credito" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."nota_credito_electronica" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."nota_credito_evento" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."notificaciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."obligaciones_tributarias_catalogo" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."omnichannel_routes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."ordenes_compra" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."pagos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."pedidos_caja" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."planes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."presupuesto_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."presupuestos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."produccion_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."producciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."producto_categorias" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."producto_presentaciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."productos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."productos_codigo_secuencia" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proveedor_categoria_rel" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proveedor_categorias" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proveedor_productos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proveedores" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyecto_archivos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyecto_comentarios" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyecto_estado_historial" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyecto_estados" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyecto_prioridades_config" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyecto_tareas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyecto_tipos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."proyectos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."receta_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."recetas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."recibos_dinero" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sifen_jobs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sorteo_conversaciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sorteo_cupones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sorteo_entradas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sorteo_revendedor_clicks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sorteo_revendedores" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sorteo_ticket_deliveries" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."sorteos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."suscripciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."tipificaciones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."usuario_dashboard_views" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."usuario_modulos" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."usuarios" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."ventas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."ventas_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tecnolabo"."ventas_pagos_detalle" ENABLE ROW LEVEL SECURITY;

-- ── POLICIES ─────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "chat_agents_delete" ON "tecnolabo"."chat_agents";
CREATE POLICY "chat_agents_delete" ON "tecnolabo"."chat_agents"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_agents_insert" ON "tecnolabo"."chat_agents";
CREATE POLICY "chat_agents_insert" ON "tecnolabo"."chat_agents"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_agents_select" ON "tecnolabo"."chat_agents";
CREATE POLICY "chat_agents_select" ON "tecnolabo"."chat_agents"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_agents_update" ON "tecnolabo"."chat_agents";
CREATE POLICY "chat_agents_update" ON "tecnolabo"."chat_agents"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_events_delete" ON "tecnolabo"."chat_campaign_events";
CREATE POLICY "chat_campaign_events_delete" ON "tecnolabo"."chat_campaign_events"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_events_insert" ON "tecnolabo"."chat_campaign_events";
CREATE POLICY "chat_campaign_events_insert" ON "tecnolabo"."chat_campaign_events"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_events_select" ON "tecnolabo"."chat_campaign_events";
CREATE POLICY "chat_campaign_events_select" ON "tecnolabo"."chat_campaign_events"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_events_update" ON "tecnolabo"."chat_campaign_events";
CREATE POLICY "chat_campaign_events_update" ON "tecnolabo"."chat_campaign_events"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_jobs_delete" ON "tecnolabo"."chat_campaign_jobs";
CREATE POLICY "chat_campaign_jobs_delete" ON "tecnolabo"."chat_campaign_jobs"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_jobs_insert" ON "tecnolabo"."chat_campaign_jobs";
CREATE POLICY "chat_campaign_jobs_insert" ON "tecnolabo"."chat_campaign_jobs"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_jobs_select" ON "tecnolabo"."chat_campaign_jobs";
CREATE POLICY "chat_campaign_jobs_select" ON "tecnolabo"."chat_campaign_jobs"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_jobs_update" ON "tecnolabo"."chat_campaign_jobs";
CREATE POLICY "chat_campaign_jobs_update" ON "tecnolabo"."chat_campaign_jobs"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_recipients_delete" ON "tecnolabo"."chat_campaign_recipients";
CREATE POLICY "chat_campaign_recipients_delete" ON "tecnolabo"."chat_campaign_recipients"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_recipients_insert" ON "tecnolabo"."chat_campaign_recipients";
CREATE POLICY "chat_campaign_recipients_insert" ON "tecnolabo"."chat_campaign_recipients"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_recipients_select" ON "tecnolabo"."chat_campaign_recipients";
CREATE POLICY "chat_campaign_recipients_select" ON "tecnolabo"."chat_campaign_recipients"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_recipients_update" ON "tecnolabo"."chat_campaign_recipients";
CREATE POLICY "chat_campaign_recipients_update" ON "tecnolabo"."chat_campaign_recipients"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_templates_delete" ON "tecnolabo"."chat_campaign_templates";
CREATE POLICY "chat_campaign_templates_delete" ON "tecnolabo"."chat_campaign_templates"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_templates_insert" ON "tecnolabo"."chat_campaign_templates";
CREATE POLICY "chat_campaign_templates_insert" ON "tecnolabo"."chat_campaign_templates"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_templates_select" ON "tecnolabo"."chat_campaign_templates";
CREATE POLICY "chat_campaign_templates_select" ON "tecnolabo"."chat_campaign_templates"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaign_templates_update" ON "tecnolabo"."chat_campaign_templates";
CREATE POLICY "chat_campaign_templates_update" ON "tecnolabo"."chat_campaign_templates"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaigns_delete" ON "tecnolabo"."chat_campaigns";
CREATE POLICY "chat_campaigns_delete" ON "tecnolabo"."chat_campaigns"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaigns_insert" ON "tecnolabo"."chat_campaigns";
CREATE POLICY "chat_campaigns_insert" ON "tecnolabo"."chat_campaigns"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaigns_select" ON "tecnolabo"."chat_campaigns";
CREATE POLICY "chat_campaigns_select" ON "tecnolabo"."chat_campaigns"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_campaigns_update" ON "tecnolabo"."chat_campaigns";
CREATE POLICY "chat_campaigns_update" ON "tecnolabo"."chat_campaigns"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channel_quick_replies_delete" ON "tecnolabo"."chat_channel_quick_replies";
CREATE POLICY "chat_channel_quick_replies_delete" ON "tecnolabo"."chat_channel_quick_replies"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channel_quick_replies_insert" ON "tecnolabo"."chat_channel_quick_replies";
CREATE POLICY "chat_channel_quick_replies_insert" ON "tecnolabo"."chat_channel_quick_replies"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channel_quick_replies_select" ON "tecnolabo"."chat_channel_quick_replies";
CREATE POLICY "chat_channel_quick_replies_select" ON "tecnolabo"."chat_channel_quick_replies"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channel_quick_replies_update" ON "tecnolabo"."chat_channel_quick_replies";
CREATE POLICY "chat_channel_quick_replies_update" ON "tecnolabo"."chat_channel_quick_replies"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channels_delete" ON "tecnolabo"."chat_channels";
CREATE POLICY "chat_channels_delete" ON "tecnolabo"."chat_channels"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channels_insert" ON "tecnolabo"."chat_channels";
CREATE POLICY "chat_channels_insert" ON "tecnolabo"."chat_channels"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channels_select" ON "tecnolabo"."chat_channels";
CREATE POLICY "chat_channels_select" ON "tecnolabo"."chat_channels"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_channels_update" ON "tecnolabo"."chat_channels";
CREATE POLICY "chat_channels_update" ON "tecnolabo"."chat_channels"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_comp_val_delete" ON "tecnolabo"."chat_comprobante_validaciones";
CREATE POLICY "chat_comp_val_delete" ON "tecnolabo"."chat_comprobante_validaciones"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_comp_val_insert" ON "tecnolabo"."chat_comprobante_validaciones";
CREATE POLICY "chat_comp_val_insert" ON "tecnolabo"."chat_comprobante_validaciones"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_comp_val_select" ON "tecnolabo"."chat_comprobante_validaciones";
CREATE POLICY "chat_comp_val_select" ON "tecnolabo"."chat_comprobante_validaciones"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_comp_val_update" ON "tecnolabo"."chat_comprobante_validaciones";
CREATE POLICY "chat_comp_val_update" ON "tecnolabo"."chat_comprobante_validaciones"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_contacts_delete" ON "tecnolabo"."chat_contacts";
CREATE POLICY "chat_contacts_delete" ON "tecnolabo"."chat_contacts"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_contacts_insert" ON "tecnolabo"."chat_contacts";
CREATE POLICY "chat_contacts_insert" ON "tecnolabo"."chat_contacts"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_contacts_select" ON "tecnolabo"."chat_contacts";
CREATE POLICY "chat_contacts_select" ON "tecnolabo"."chat_contacts"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_contacts_update" ON "tecnolabo"."chat_contacts";
CREATE POLICY "chat_contacts_update" ON "tecnolabo"."chat_contacts"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_conversation_closures_insert" ON "tecnolabo"."chat_conversation_closures";
CREATE POLICY "chat_conversation_closures_insert" ON "tecnolabo"."chat_conversation_closures"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_conversation_closures_select" ON "tecnolabo"."chat_conversation_closures";
CREATE POLICY "chat_conversation_closures_select" ON "tecnolabo"."chat_conversation_closures"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_conversations_delete" ON "tecnolabo"."chat_conversations";
CREATE POLICY "chat_conversations_delete" ON "tecnolabo"."chat_conversations"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_conversations_insert" ON "tecnolabo"."chat_conversations";
CREATE POLICY "chat_conversations_insert" ON "tecnolabo"."chat_conversations"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_conversations_select" ON "tecnolabo"."chat_conversations";
CREATE POLICY "chat_conversations_select" ON "tecnolabo"."chat_conversations"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_conversations_update" ON "tecnolabo"."chat_conversations";
CREATE POLICY "chat_conversations_update" ON "tecnolabo"."chat_conversations"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_empresa_operator_roles_delete" ON "tecnolabo"."chat_empresa_operator_roles";
CREATE POLICY "chat_empresa_operator_roles_delete" ON "tecnolabo"."chat_empresa_operator_roles"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_empresa_operator_roles_insert" ON "tecnolabo"."chat_empresa_operator_roles";
CREATE POLICY "chat_empresa_operator_roles_insert" ON "tecnolabo"."chat_empresa_operator_roles"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_empresa_operator_roles_select" ON "tecnolabo"."chat_empresa_operator_roles";
CREATE POLICY "chat_empresa_operator_roles_select" ON "tecnolabo"."chat_empresa_operator_roles"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_empresa_operator_roles_update" ON "tecnolabo"."chat_empresa_operator_roles";
CREATE POLICY "chat_empresa_operator_roles_update" ON "tecnolabo"."chat_empresa_operator_roles"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_data_delete" ON "tecnolabo"."chat_flow_data";
CREATE POLICY "chat_flow_data_delete" ON "tecnolabo"."chat_flow_data"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_data_insert" ON "tecnolabo"."chat_flow_data";
CREATE POLICY "chat_flow_data_insert" ON "tecnolabo"."chat_flow_data"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_data_select" ON "tecnolabo"."chat_flow_data";
CREATE POLICY "chat_flow_data_select" ON "tecnolabo"."chat_flow_data"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_data_update" ON "tecnolabo"."chat_flow_data";
CREATE POLICY "chat_flow_data_update" ON "tecnolabo"."chat_flow_data"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_events_delete" ON "tecnolabo"."chat_flow_events";
CREATE POLICY "chat_flow_events_delete" ON "tecnolabo"."chat_flow_events"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_events_insert" ON "tecnolabo"."chat_flow_events";
CREATE POLICY "chat_flow_events_insert" ON "tecnolabo"."chat_flow_events"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_events_select" ON "tecnolabo"."chat_flow_events";
CREATE POLICY "chat_flow_events_select" ON "tecnolabo"."chat_flow_events"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_events_update" ON "tecnolabo"."chat_flow_events";
CREATE POLICY "chat_flow_events_update" ON "tecnolabo"."chat_flow_events"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_node_blocks_delete_empresa" ON "tecnolabo"."chat_flow_node_blocks";
CREATE POLICY "chat_flow_node_blocks_delete_empresa" ON "tecnolabo"."chat_flow_node_blocks"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_node_blocks_insert_empresa" ON "tecnolabo"."chat_flow_node_blocks";
CREATE POLICY "chat_flow_node_blocks_insert_empresa" ON "tecnolabo"."chat_flow_node_blocks"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_node_blocks_select_empresa" ON "tecnolabo"."chat_flow_node_blocks";
CREATE POLICY "chat_flow_node_blocks_select_empresa" ON "tecnolabo"."chat_flow_node_blocks"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_node_blocks_update_empresa" ON "tecnolabo"."chat_flow_node_blocks";
CREATE POLICY "chat_flow_node_blocks_update_empresa" ON "tecnolabo"."chat_flow_node_blocks"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_nodes_delete" ON "tecnolabo"."chat_flow_nodes";
CREATE POLICY "chat_flow_nodes_delete" ON "tecnolabo"."chat_flow_nodes"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_nodes_insert" ON "tecnolabo"."chat_flow_nodes";
CREATE POLICY "chat_flow_nodes_insert" ON "tecnolabo"."chat_flow_nodes"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_nodes_select" ON "tecnolabo"."chat_flow_nodes";
CREATE POLICY "chat_flow_nodes_select" ON "tecnolabo"."chat_flow_nodes"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_nodes_update" ON "tecnolabo"."chat_flow_nodes";
CREATE POLICY "chat_flow_nodes_update" ON "tecnolabo"."chat_flow_nodes"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_options_delete" ON "tecnolabo"."chat_flow_options";
CREATE POLICY "chat_flow_options_delete" ON "tecnolabo"."chat_flow_options"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING ((EXISTS ( SELECT 1
   FROM tecnolabo.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND tecnolabo.puede_acceder_empresa(n.empresa_id)))));
DROP POLICY IF EXISTS "chat_flow_options_insert" ON "tecnolabo"."chat_flow_options";
CREATE POLICY "chat_flow_options_insert" ON "tecnolabo"."chat_flow_options"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK ((EXISTS ( SELECT 1
   FROM tecnolabo.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND tecnolabo.puede_acceder_empresa(n.empresa_id)))));
DROP POLICY IF EXISTS "chat_flow_options_select" ON "tecnolabo"."chat_flow_options";
CREATE POLICY "chat_flow_options_select" ON "tecnolabo"."chat_flow_options"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((EXISTS ( SELECT 1
   FROM tecnolabo.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND tecnolabo.puede_acceder_empresa(n.empresa_id)))));
DROP POLICY IF EXISTS "chat_flow_options_update" ON "tecnolabo"."chat_flow_options";
CREATE POLICY "chat_flow_options_update" ON "tecnolabo"."chat_flow_options"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING ((EXISTS ( SELECT 1
   FROM tecnolabo.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND tecnolabo.puede_acceder_empresa(n.empresa_id)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM tecnolabo.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND tecnolabo.puede_acceder_empresa(n.empresa_id)))));
DROP POLICY IF EXISTS "chat_flow_recontact_rules_delete" ON "tecnolabo"."chat_flow_recontact_rules";
CREATE POLICY "chat_flow_recontact_rules_delete" ON "tecnolabo"."chat_flow_recontact_rules"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_recontact_rules_insert" ON "tecnolabo"."chat_flow_recontact_rules";
CREATE POLICY "chat_flow_recontact_rules_insert" ON "tecnolabo"."chat_flow_recontact_rules"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_recontact_rules_select" ON "tecnolabo"."chat_flow_recontact_rules";
CREATE POLICY "chat_flow_recontact_rules_select" ON "tecnolabo"."chat_flow_recontact_rules"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_recontact_rules_update" ON "tecnolabo"."chat_flow_recontact_rules";
CREATE POLICY "chat_flow_recontact_rules_update" ON "tecnolabo"."chat_flow_recontact_rules"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_recontact_runs_delete" ON "tecnolabo"."chat_flow_recontact_runs";
CREATE POLICY "chat_flow_recontact_runs_delete" ON "tecnolabo"."chat_flow_recontact_runs"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_recontact_runs_insert" ON "tecnolabo"."chat_flow_recontact_runs";
CREATE POLICY "chat_flow_recontact_runs_insert" ON "tecnolabo"."chat_flow_recontact_runs"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_recontact_runs_select" ON "tecnolabo"."chat_flow_recontact_runs";
CREATE POLICY "chat_flow_recontact_runs_select" ON "tecnolabo"."chat_flow_recontact_runs"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_recontact_runs_update" ON "tecnolabo"."chat_flow_recontact_runs";
CREATE POLICY "chat_flow_recontact_runs_update" ON "tecnolabo"."chat_flow_recontact_runs"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_sessions_delete" ON "tecnolabo"."chat_flow_sessions";
CREATE POLICY "chat_flow_sessions_delete" ON "tecnolabo"."chat_flow_sessions"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_sessions_insert" ON "tecnolabo"."chat_flow_sessions";
CREATE POLICY "chat_flow_sessions_insert" ON "tecnolabo"."chat_flow_sessions"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_sessions_select" ON "tecnolabo"."chat_flow_sessions";
CREATE POLICY "chat_flow_sessions_select" ON "tecnolabo"."chat_flow_sessions"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flow_sessions_update" ON "tecnolabo"."chat_flow_sessions";
CREATE POLICY "chat_flow_sessions_update" ON "tecnolabo"."chat_flow_sessions"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flows_delete" ON "tecnolabo"."chat_flows";
CREATE POLICY "chat_flows_delete" ON "tecnolabo"."chat_flows"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flows_insert" ON "tecnolabo"."chat_flows";
CREATE POLICY "chat_flows_insert" ON "tecnolabo"."chat_flows"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flows_select" ON "tecnolabo"."chat_flows";
CREATE POLICY "chat_flows_select" ON "tecnolabo"."chat_flows"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_flows_update" ON "tecnolabo"."chat_flows";
CREATE POLICY "chat_flows_update" ON "tecnolabo"."chat_flows"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_messages_delete" ON "tecnolabo"."chat_messages";
CREATE POLICY "chat_messages_delete" ON "tecnolabo"."chat_messages"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_messages_insert" ON "tecnolabo"."chat_messages";
CREATE POLICY "chat_messages_insert" ON "tecnolabo"."chat_messages"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_messages_select" ON "tecnolabo"."chat_messages";
CREATE POLICY "chat_messages_select" ON "tecnolabo"."chat_messages"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_messages_update" ON "tecnolabo"."chat_messages";
CREATE POLICY "chat_messages_update" ON "tecnolabo"."chat_messages"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_omn_sched_delete" ON "tecnolabo"."chat_omnicanal_work_schedules";
CREATE POLICY "chat_omn_sched_delete" ON "tecnolabo"."chat_omnicanal_work_schedules"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_omn_sched_insert" ON "tecnolabo"."chat_omnicanal_work_schedules";
CREATE POLICY "chat_omn_sched_insert" ON "tecnolabo"."chat_omnicanal_work_schedules"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_omn_sched_select" ON "tecnolabo"."chat_omnicanal_work_schedules";
CREATE POLICY "chat_omn_sched_select" ON "tecnolabo"."chat_omnicanal_work_schedules"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_omn_sched_update" ON "tecnolabo"."chat_omnicanal_work_schedules";
CREATE POLICY "chat_omn_sched_update" ON "tecnolabo"."chat_omnicanal_work_schedules"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_channels_delete" ON "tecnolabo"."chat_queue_channels";
CREATE POLICY "chat_queue_channels_delete" ON "tecnolabo"."chat_queue_channels"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_channels_insert" ON "tecnolabo"."chat_queue_channels";
CREATE POLICY "chat_queue_channels_insert" ON "tecnolabo"."chat_queue_channels"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_channels_select" ON "tecnolabo"."chat_queue_channels";
CREATE POLICY "chat_queue_channels_select" ON "tecnolabo"."chat_queue_channels"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_channels_update" ON "tecnolabo"."chat_queue_channels";
CREATE POLICY "chat_queue_channels_update" ON "tecnolabo"."chat_queue_channels"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_states_delete" ON "tecnolabo"."chat_queue_closure_states";
CREATE POLICY "chat_queue_closure_states_delete" ON "tecnolabo"."chat_queue_closure_states"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_states_insert" ON "tecnolabo"."chat_queue_closure_states";
CREATE POLICY "chat_queue_closure_states_insert" ON "tecnolabo"."chat_queue_closure_states"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_states_select" ON "tecnolabo"."chat_queue_closure_states";
CREATE POLICY "chat_queue_closure_states_select" ON "tecnolabo"."chat_queue_closure_states"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_states_update" ON "tecnolabo"."chat_queue_closure_states";
CREATE POLICY "chat_queue_closure_states_update" ON "tecnolabo"."chat_queue_closure_states"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_substates_delete" ON "tecnolabo"."chat_queue_closure_substates";
CREATE POLICY "chat_queue_closure_substates_delete" ON "tecnolabo"."chat_queue_closure_substates"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_substates_insert" ON "tecnolabo"."chat_queue_closure_substates";
CREATE POLICY "chat_queue_closure_substates_insert" ON "tecnolabo"."chat_queue_closure_substates"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_substates_select" ON "tecnolabo"."chat_queue_closure_substates";
CREATE POLICY "chat_queue_closure_substates_select" ON "tecnolabo"."chat_queue_closure_substates"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_closure_substates_update" ON "tecnolabo"."chat_queue_closure_substates";
CREATE POLICY "chat_queue_closure_substates_update" ON "tecnolabo"."chat_queue_closure_substates"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_supervisors_delete" ON "tecnolabo"."chat_queue_supervisors";
CREATE POLICY "chat_queue_supervisors_delete" ON "tecnolabo"."chat_queue_supervisors"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_supervisors_insert" ON "tecnolabo"."chat_queue_supervisors";
CREATE POLICY "chat_queue_supervisors_insert" ON "tecnolabo"."chat_queue_supervisors"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_supervisors_select" ON "tecnolabo"."chat_queue_supervisors";
CREATE POLICY "chat_queue_supervisors_select" ON "tecnolabo"."chat_queue_supervisors"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queue_supervisors_update" ON "tecnolabo"."chat_queue_supervisors";
CREATE POLICY "chat_queue_supervisors_update" ON "tecnolabo"."chat_queue_supervisors"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queues_delete" ON "tecnolabo"."chat_queues";
CREATE POLICY "chat_queues_delete" ON "tecnolabo"."chat_queues"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queues_insert" ON "tecnolabo"."chat_queues";
CREATE POLICY "chat_queues_insert" ON "tecnolabo"."chat_queues"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queues_select" ON "tecnolabo"."chat_queues";
CREATE POLICY "chat_queues_select" ON "tecnolabo"."chat_queues"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_queues_update" ON "tecnolabo"."chat_queues";
CREATE POLICY "chat_queues_update" ON "tecnolabo"."chat_queues"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_routing_events_insert" ON "tecnolabo"."chat_routing_events";
CREATE POLICY "chat_routing_events_insert" ON "tecnolabo"."chat_routing_events"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_routing_events_select" ON "tecnolabo"."chat_routing_events";
CREATE POLICY "chat_routing_events_select" ON "tecnolabo"."chat_routing_events"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_supervisor_agents_delete" ON "tecnolabo"."chat_supervisor_agents";
CREATE POLICY "chat_supervisor_agents_delete" ON "tecnolabo"."chat_supervisor_agents"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_supervisor_agents_insert" ON "tecnolabo"."chat_supervisor_agents";
CREATE POLICY "chat_supervisor_agents_insert" ON "tecnolabo"."chat_supervisor_agents"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_supervisor_agents_select" ON "tecnolabo"."chat_supervisor_agents";
CREATE POLICY "chat_supervisor_agents_select" ON "tecnolabo"."chat_supervisor_agents"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_supervisor_agents_update" ON "tecnolabo"."chat_supervisor_agents";
CREATE POLICY "chat_supervisor_agents_update" ON "tecnolabo"."chat_supervisor_agents"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_usuario_omnicanal_delete" ON "tecnolabo"."chat_usuario_omnicanal";
CREATE POLICY "chat_usuario_omnicanal_delete" ON "tecnolabo"."chat_usuario_omnicanal"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_usuario_omnicanal_insert" ON "tecnolabo"."chat_usuario_omnicanal";
CREATE POLICY "chat_usuario_omnicanal_insert" ON "tecnolabo"."chat_usuario_omnicanal"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_usuario_omnicanal_select" ON "tecnolabo"."chat_usuario_omnicanal";
CREATE POLICY "chat_usuario_omnicanal_select" ON "tecnolabo"."chat_usuario_omnicanal"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "chat_usuario_omnicanal_update" ON "tecnolabo"."chat_usuario_omnicanal";
CREATE POLICY "chat_usuario_omnicanal_update" ON "tecnolabo"."chat_usuario_omnicanal"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_historial_insert" ON "tecnolabo"."cliente_historial";
CREATE POLICY "cliente_historial_insert" ON "tecnolabo"."cliente_historial"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_historial_select" ON "tecnolabo"."cliente_historial";
CREATE POLICY "cliente_historial_select" ON "tecnolabo"."cliente_historial"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_obligaciones_tributarias_delete" ON "tecnolabo"."cliente_obligaciones_tributarias";
CREATE POLICY "cliente_obligaciones_tributarias_delete" ON "tecnolabo"."cliente_obligaciones_tributarias"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_obligaciones_tributarias_insert" ON "tecnolabo"."cliente_obligaciones_tributarias";
CREATE POLICY "cliente_obligaciones_tributarias_insert" ON "tecnolabo"."cliente_obligaciones_tributarias"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_obligaciones_tributarias_select" ON "tecnolabo"."cliente_obligaciones_tributarias";
CREATE POLICY "cliente_obligaciones_tributarias_select" ON "tecnolabo"."cliente_obligaciones_tributarias"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_obligaciones_tributarias_update" ON "tecnolabo"."cliente_obligaciones_tributarias";
CREATE POLICY "cliente_obligaciones_tributarias_update" ON "tecnolabo"."cliente_obligaciones_tributarias"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_perfil_tributario_delete" ON "tecnolabo"."cliente_perfil_tributario";
CREATE POLICY "cliente_perfil_tributario_delete" ON "tecnolabo"."cliente_perfil_tributario"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_perfil_tributario_insert" ON "tecnolabo"."cliente_perfil_tributario";
CREATE POLICY "cliente_perfil_tributario_insert" ON "tecnolabo"."cliente_perfil_tributario"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_perfil_tributario_select" ON "tecnolabo"."cliente_perfil_tributario";
CREATE POLICY "cliente_perfil_tributario_select" ON "tecnolabo"."cliente_perfil_tributario"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_perfil_tributario_update" ON "tecnolabo"."cliente_perfil_tributario";
CREATE POLICY "cliente_perfil_tributario_update" ON "tecnolabo"."cliente_perfil_tributario"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_tipos_servicio_catalogo_delete" ON "tecnolabo"."cliente_tipos_servicio_catalogo";
CREATE POLICY "cliente_tipos_servicio_catalogo_delete" ON "tecnolabo"."cliente_tipos_servicio_catalogo"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_tipos_servicio_catalogo_insert" ON "tecnolabo"."cliente_tipos_servicio_catalogo";
CREATE POLICY "cliente_tipos_servicio_catalogo_insert" ON "tecnolabo"."cliente_tipos_servicio_catalogo"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_tipos_servicio_catalogo_select" ON "tecnolabo"."cliente_tipos_servicio_catalogo";
CREATE POLICY "cliente_tipos_servicio_catalogo_select" ON "tecnolabo"."cliente_tipos_servicio_catalogo"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "cliente_tipos_servicio_catalogo_update" ON "tecnolabo"."cliente_tipos_servicio_catalogo";
CREATE POLICY "cliente_tipos_servicio_catalogo_update" ON "tecnolabo"."cliente_tipos_servicio_catalogo"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "clientes_delete" ON "tecnolabo"."clientes";
CREATE POLICY "clientes_delete" ON "tecnolabo"."clientes"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "clientes_insert" ON "tecnolabo"."clientes";
CREATE POLICY "clientes_insert" ON "tecnolabo"."clientes"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "clientes_select" ON "tecnolabo"."clientes";
CREATE POLICY "clientes_select" ON "tecnolabo"."clientes"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "clientes_update" ON "tecnolabo"."clientes";
CREATE POLICY "clientes_update" ON "tecnolabo"."clientes"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_ajustes_delete" ON "tecnolabo"."comision_ajustes";
CREATE POLICY "comision_ajustes_delete" ON "tecnolabo"."comision_ajustes"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_ajustes_insert" ON "tecnolabo"."comision_ajustes";
CREATE POLICY "comision_ajustes_insert" ON "tecnolabo"."comision_ajustes"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_ajustes_select" ON "tecnolabo"."comision_ajustes";
CREATE POLICY "comision_ajustes_select" ON "tecnolabo"."comision_ajustes"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_ajustes_update" ON "tecnolabo"."comision_ajustes";
CREATE POLICY "comision_ajustes_update" ON "tecnolabo"."comision_ajustes"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipo_miembros_delete" ON "tecnolabo"."comision_equipo_miembros";
CREATE POLICY "comision_equipo_miembros_delete" ON "tecnolabo"."comision_equipo_miembros"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipo_miembros_insert" ON "tecnolabo"."comision_equipo_miembros";
CREATE POLICY "comision_equipo_miembros_insert" ON "tecnolabo"."comision_equipo_miembros"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipo_miembros_select" ON "tecnolabo"."comision_equipo_miembros";
CREATE POLICY "comision_equipo_miembros_select" ON "tecnolabo"."comision_equipo_miembros"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipo_miembros_update" ON "tecnolabo"."comision_equipo_miembros";
CREATE POLICY "comision_equipo_miembros_update" ON "tecnolabo"."comision_equipo_miembros"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipos_delete" ON "tecnolabo"."comision_equipos";
CREATE POLICY "comision_equipos_delete" ON "tecnolabo"."comision_equipos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipos_insert" ON "tecnolabo"."comision_equipos";
CREATE POLICY "comision_equipos_insert" ON "tecnolabo"."comision_equipos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipos_select" ON "tecnolabo"."comision_equipos";
CREATE POLICY "comision_equipos_select" ON "tecnolabo"."comision_equipos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_equipos_update" ON "tecnolabo"."comision_equipos";
CREATE POLICY "comision_equipos_update" ON "tecnolabo"."comision_equipos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_escalas_delete" ON "tecnolabo"."comision_escalas";
CREATE POLICY "comision_escalas_delete" ON "tecnolabo"."comision_escalas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_escalas_insert" ON "tecnolabo"."comision_escalas";
CREATE POLICY "comision_escalas_insert" ON "tecnolabo"."comision_escalas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_escalas_select" ON "tecnolabo"."comision_escalas";
CREATE POLICY "comision_escalas_select" ON "tecnolabo"."comision_escalas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_escalas_update" ON "tecnolabo"."comision_escalas";
CREATE POLICY "comision_escalas_update" ON "tecnolabo"."comision_escalas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_lineas_delete" ON "tecnolabo"."comision_lineas";
CREATE POLICY "comision_lineas_delete" ON "tecnolabo"."comision_lineas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_lineas_insert" ON "tecnolabo"."comision_lineas";
CREATE POLICY "comision_lineas_insert" ON "tecnolabo"."comision_lineas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_lineas_select" ON "tecnolabo"."comision_lineas";
CREATE POLICY "comision_lineas_select" ON "tecnolabo"."comision_lineas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_lineas_update" ON "tecnolabo"."comision_lineas";
CREATE POLICY "comision_lineas_update" ON "tecnolabo"."comision_lineas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_periodos_delete" ON "tecnolabo"."comision_periodos";
CREATE POLICY "comision_periodos_delete" ON "tecnolabo"."comision_periodos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_periodos_insert" ON "tecnolabo"."comision_periodos";
CREATE POLICY "comision_periodos_insert" ON "tecnolabo"."comision_periodos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_periodos_select" ON "tecnolabo"."comision_periodos";
CREATE POLICY "comision_periodos_select" ON "tecnolabo"."comision_periodos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_periodos_update" ON "tecnolabo"."comision_periodos";
CREATE POLICY "comision_periodos_update" ON "tecnolabo"."comision_periodos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politica_versiones_delete" ON "tecnolabo"."comision_politica_versiones";
CREATE POLICY "comision_politica_versiones_delete" ON "tecnolabo"."comision_politica_versiones"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politica_versiones_insert" ON "tecnolabo"."comision_politica_versiones";
CREATE POLICY "comision_politica_versiones_insert" ON "tecnolabo"."comision_politica_versiones"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politica_versiones_select" ON "tecnolabo"."comision_politica_versiones";
CREATE POLICY "comision_politica_versiones_select" ON "tecnolabo"."comision_politica_versiones"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politica_versiones_update" ON "tecnolabo"."comision_politica_versiones";
CREATE POLICY "comision_politica_versiones_update" ON "tecnolabo"."comision_politica_versiones"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politicas_delete" ON "tecnolabo"."comision_politicas";
CREATE POLICY "comision_politicas_delete" ON "tecnolabo"."comision_politicas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politicas_insert" ON "tecnolabo"."comision_politicas";
CREATE POLICY "comision_politicas_insert" ON "tecnolabo"."comision_politicas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politicas_select" ON "tecnolabo"."comision_politicas";
CREATE POLICY "comision_politicas_select" ON "tecnolabo"."comision_politicas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "comision_politicas_update" ON "tecnolabo"."comision_politicas";
CREATE POLICY "comision_politicas_update" ON "tecnolabo"."comision_politicas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "compras_delete" ON "tecnolabo"."compras";
CREATE POLICY "compras_delete" ON "tecnolabo"."compras"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "compras_insert" ON "tecnolabo"."compras";
CREATE POLICY "compras_insert" ON "tecnolabo"."compras"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "compras_select" ON "tecnolabo"."compras";
CREATE POLICY "compras_select" ON "tecnolabo"."compras"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "compras_update" ON "tecnolabo"."compras";
CREATE POLICY "compras_update" ON "tecnolabo"."compras"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_etapas_delete" ON "tecnolabo"."crm_etapas";
CREATE POLICY "crm_etapas_delete" ON "tecnolabo"."crm_etapas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_etapas_insert" ON "tecnolabo"."crm_etapas";
CREATE POLICY "crm_etapas_insert" ON "tecnolabo"."crm_etapas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_etapas_select" ON "tecnolabo"."crm_etapas";
CREATE POLICY "crm_etapas_select" ON "tecnolabo"."crm_etapas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_etapas_update" ON "tecnolabo"."crm_etapas";
CREATE POLICY "crm_etapas_update" ON "tecnolabo"."crm_etapas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_notas_delete" ON "tecnolabo"."crm_notas";
CREATE POLICY "crm_notas_delete" ON "tecnolabo"."crm_notas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_notas_insert" ON "tecnolabo"."crm_notas";
CREATE POLICY "crm_notas_insert" ON "tecnolabo"."crm_notas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_notas_select" ON "tecnolabo"."crm_notas";
CREATE POLICY "crm_notas_select" ON "tecnolabo"."crm_notas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_notas_update" ON "tecnolabo"."crm_notas";
CREATE POLICY "crm_notas_update" ON "tecnolabo"."crm_notas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_prospectos_delete" ON "tecnolabo"."crm_prospectos";
CREATE POLICY "crm_prospectos_delete" ON "tecnolabo"."crm_prospectos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_prospectos_insert" ON "tecnolabo"."crm_prospectos";
CREATE POLICY "crm_prospectos_insert" ON "tecnolabo"."crm_prospectos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_prospectos_select" ON "tecnolabo"."crm_prospectos";
CREATE POLICY "crm_prospectos_select" ON "tecnolabo"."crm_prospectos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "crm_prospectos_update" ON "tecnolabo"."crm_prospectos";
CREATE POLICY "crm_prospectos_update" ON "tecnolabo"."crm_prospectos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "dashboard_views_all_super" ON "tecnolabo"."dashboard_views";
CREATE POLICY "dashboard_views_all_super" ON "tecnolabo"."dashboard_views"
  AS PERMISSIVE
  FOR ALL
  TO public
  USING (tecnolabo.es_super_admin())
  WITH CHECK (tecnolabo.es_super_admin());
DROP POLICY IF EXISTS "dashboard_views_select_auth" ON "tecnolabo"."dashboard_views";
CREATE POLICY "dashboard_views_select_auth" ON "tecnolabo"."dashboard_views"
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (true);
DROP POLICY IF EXISTS "edv_delete" ON "tecnolabo"."empresa_dashboard_views";
CREATE POLICY "edv_delete" ON "tecnolabo"."empresa_dashboard_views"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING ((tecnolabo.es_super_admin() OR tecnolabo.puede_acceder_empresa(empresa_id)));
DROP POLICY IF EXISTS "edv_mutate" ON "tecnolabo"."empresa_dashboard_views";
CREATE POLICY "edv_mutate" ON "tecnolabo"."empresa_dashboard_views"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK ((tecnolabo.es_super_admin() OR tecnolabo.puede_acceder_empresa(empresa_id)));
DROP POLICY IF EXISTS "edv_select" ON "tecnolabo"."empresa_dashboard_views";
CREATE POLICY "edv_select" ON "tecnolabo"."empresa_dashboard_views"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "edv_update" ON "tecnolabo"."empresa_dashboard_views";
CREATE POLICY "edv_update" ON "tecnolabo"."empresa_dashboard_views"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING ((tecnolabo.es_super_admin() OR tecnolabo.puede_acceder_empresa(empresa_id)))
  WITH CHECK ((tecnolabo.es_super_admin() OR tecnolabo.puede_acceder_empresa(empresa_id)));
DROP POLICY IF EXISTS "empresa_modulos_delete" ON "tecnolabo"."empresa_modulos";
CREATE POLICY "empresa_modulos_delete" ON "tecnolabo"."empresa_modulos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresa_modulos_insert" ON "tecnolabo"."empresa_modulos";
CREATE POLICY "empresa_modulos_insert" ON "tecnolabo"."empresa_modulos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresa_modulos_select" ON "tecnolabo"."empresa_modulos";
CREATE POLICY "empresa_modulos_select" ON "tecnolabo"."empresa_modulos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresa_modulos_update" ON "tecnolabo"."empresa_modulos";
CREATE POLICY "empresa_modulos_update" ON "tecnolabo"."empresa_modulos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresa_sifen_config_delete" ON "tecnolabo"."empresa_sifen_config";
CREATE POLICY "empresa_sifen_config_delete" ON "tecnolabo"."empresa_sifen_config"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresa_sifen_config_insert" ON "tecnolabo"."empresa_sifen_config";
CREATE POLICY "empresa_sifen_config_insert" ON "tecnolabo"."empresa_sifen_config"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresa_sifen_config_select" ON "tecnolabo"."empresa_sifen_config";
CREATE POLICY "empresa_sifen_config_select" ON "tecnolabo"."empresa_sifen_config"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresa_sifen_config_update" ON "tecnolabo"."empresa_sifen_config";
CREATE POLICY "empresa_sifen_config_update" ON "tecnolabo"."empresa_sifen_config"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "empresas_delete" ON "tecnolabo"."empresas";
CREATE POLICY "empresas_delete" ON "tecnolabo"."empresas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.es_super_admin());
DROP POLICY IF EXISTS "empresas_insert" ON "tecnolabo"."empresas";
CREATE POLICY "empresas_insert" ON "tecnolabo"."empresas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.es_super_admin());
DROP POLICY IF EXISTS "empresas_select" ON "tecnolabo"."empresas";
CREATE POLICY "empresas_select" ON "tecnolabo"."empresas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((tecnolabo.es_super_admin() OR (id = tecnolabo.empresa_id_actual())));
DROP POLICY IF EXISTS "empresas_update" ON "tecnolabo"."empresas";
CREATE POLICY "empresas_update" ON "tecnolabo"."empresas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(id));
DROP POLICY IF EXISTS "entidades_bancarias_delete" ON "tecnolabo"."entidades_bancarias";
CREATE POLICY "entidades_bancarias_delete" ON "tecnolabo"."entidades_bancarias"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "entidades_bancarias_insert" ON "tecnolabo"."entidades_bancarias";
CREATE POLICY "entidades_bancarias_insert" ON "tecnolabo"."entidades_bancarias"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "entidades_bancarias_select" ON "tecnolabo"."entidades_bancarias";
CREATE POLICY "entidades_bancarias_select" ON "tecnolabo"."entidades_bancarias"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "entidades_bancarias_update" ON "tecnolabo"."entidades_bancarias";
CREATE POLICY "entidades_bancarias_update" ON "tecnolabo"."entidades_bancarias"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_delete" ON "tecnolabo"."factura_electronica";
CREATE POLICY "factura_electronica_delete" ON "tecnolabo"."factura_electronica"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_insert" ON "tecnolabo"."factura_electronica";
CREATE POLICY "factura_electronica_insert" ON "tecnolabo"."factura_electronica"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_select" ON "tecnolabo"."factura_electronica";
CREATE POLICY "factura_electronica_select" ON "tecnolabo"."factura_electronica"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_update" ON "tecnolabo"."factura_electronica";
CREATE POLICY "factura_electronica_update" ON "tecnolabo"."factura_electronica"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_evento_delete" ON "tecnolabo"."factura_electronica_evento";
CREATE POLICY "factura_electronica_evento_delete" ON "tecnolabo"."factura_electronica_evento"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_evento_insert" ON "tecnolabo"."factura_electronica_evento";
CREATE POLICY "factura_electronica_evento_insert" ON "tecnolabo"."factura_electronica_evento"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_evento_select" ON "tecnolabo"."factura_electronica_evento";
CREATE POLICY "factura_electronica_evento_select" ON "tecnolabo"."factura_electronica_evento"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_electronica_evento_update" ON "tecnolabo"."factura_electronica_evento";
CREATE POLICY "factura_electronica_evento_update" ON "tecnolabo"."factura_electronica_evento"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_items_delete" ON "tecnolabo"."factura_items";
CREATE POLICY "factura_items_delete" ON "tecnolabo"."factura_items"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_items_insert" ON "tecnolabo"."factura_items";
CREATE POLICY "factura_items_insert" ON "tecnolabo"."factura_items"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_items_select" ON "tecnolabo"."factura_items";
CREATE POLICY "factura_items_select" ON "tecnolabo"."factura_items"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "factura_items_update" ON "tecnolabo"."factura_items";
CREATE POLICY "factura_items_update" ON "tecnolabo"."factura_items"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "facturas_delete" ON "tecnolabo"."facturas";
CREATE POLICY "facturas_delete" ON "tecnolabo"."facturas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "facturas_insert" ON "tecnolabo"."facturas";
CREATE POLICY "facturas_insert" ON "tecnolabo"."facturas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "facturas_select" ON "tecnolabo"."facturas";
CREATE POLICY "facturas_select" ON "tecnolabo"."facturas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "facturas_update" ON "tecnolabo"."facturas";
CREATE POLICY "facturas_update" ON "tecnolabo"."facturas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "gastos_delete" ON "tecnolabo"."gastos";
CREATE POLICY "gastos_delete" ON "tecnolabo"."gastos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "gastos_insert" ON "tecnolabo"."gastos";
CREATE POLICY "gastos_insert" ON "tecnolabo"."gastos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "gastos_select" ON "tecnolabo"."gastos";
CREATE POLICY "gastos_select" ON "tecnolabo"."gastos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "gastos_update" ON "tecnolabo"."gastos";
CREATE POLICY "gastos_update" ON "tecnolabo"."gastos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_calendarios_delete" ON "tecnolabo"."marketing_calendarios";
CREATE POLICY "marketing_calendarios_delete" ON "tecnolabo"."marketing_calendarios"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_calendarios_insert" ON "tecnolabo"."marketing_calendarios";
CREATE POLICY "marketing_calendarios_insert" ON "tecnolabo"."marketing_calendarios"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_calendarios_select" ON "tecnolabo"."marketing_calendarios";
CREATE POLICY "marketing_calendarios_select" ON "tecnolabo"."marketing_calendarios"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_calendarios_update" ON "tecnolabo"."marketing_calendarios";
CREATE POLICY "marketing_calendarios_update" ON "tecnolabo"."marketing_calendarios"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_comentarios_delete" ON "tecnolabo"."marketing_comentarios";
CREATE POLICY "marketing_comentarios_delete" ON "tecnolabo"."marketing_comentarios"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_comentarios_insert" ON "tecnolabo"."marketing_comentarios";
CREATE POLICY "marketing_comentarios_insert" ON "tecnolabo"."marketing_comentarios"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_comentarios_select" ON "tecnolabo"."marketing_comentarios";
CREATE POLICY "marketing_comentarios_select" ON "tecnolabo"."marketing_comentarios"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_comentarios_update" ON "tecnolabo"."marketing_comentarios";
CREATE POLICY "marketing_comentarios_update" ON "tecnolabo"."marketing_comentarios"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_historial_estados_delete" ON "tecnolabo"."marketing_historial_estados";
CREATE POLICY "marketing_historial_estados_delete" ON "tecnolabo"."marketing_historial_estados"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_historial_estados_insert" ON "tecnolabo"."marketing_historial_estados";
CREATE POLICY "marketing_historial_estados_insert" ON "tecnolabo"."marketing_historial_estados"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_historial_estados_select" ON "tecnolabo"."marketing_historial_estados";
CREATE POLICY "marketing_historial_estados_select" ON "tecnolabo"."marketing_historial_estados"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_historial_estados_update" ON "tecnolabo"."marketing_historial_estados";
CREATE POLICY "marketing_historial_estados_update" ON "tecnolabo"."marketing_historial_estados"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_piezas_delete" ON "tecnolabo"."marketing_piezas";
CREATE POLICY "marketing_piezas_delete" ON "tecnolabo"."marketing_piezas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_piezas_insert" ON "tecnolabo"."marketing_piezas";
CREATE POLICY "marketing_piezas_insert" ON "tecnolabo"."marketing_piezas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_piezas_select" ON "tecnolabo"."marketing_piezas";
CREATE POLICY "marketing_piezas_select" ON "tecnolabo"."marketing_piezas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_piezas_update" ON "tecnolabo"."marketing_piezas";
CREATE POLICY "marketing_piezas_update" ON "tecnolabo"."marketing_piezas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_tasks_delete" ON "tecnolabo"."marketing_tasks";
CREATE POLICY "marketing_tasks_delete" ON "tecnolabo"."marketing_tasks"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_tasks_insert" ON "tecnolabo"."marketing_tasks";
CREATE POLICY "marketing_tasks_insert" ON "tecnolabo"."marketing_tasks"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_tasks_select" ON "tecnolabo"."marketing_tasks";
CREATE POLICY "marketing_tasks_select" ON "tecnolabo"."marketing_tasks"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "marketing_tasks_update" ON "tecnolabo"."marketing_tasks";
CREATE POLICY "marketing_tasks_update" ON "tecnolabo"."marketing_tasks"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "modulos_delete" ON "tecnolabo"."modulos";
CREATE POLICY "modulos_delete" ON "tecnolabo"."modulos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.es_super_admin());
DROP POLICY IF EXISTS "modulos_insert" ON "tecnolabo"."modulos";
CREATE POLICY "modulos_insert" ON "tecnolabo"."modulos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.es_super_admin());
DROP POLICY IF EXISTS "modulos_select" ON "tecnolabo"."modulos";
CREATE POLICY "modulos_select" ON "tecnolabo"."modulos"
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (true);
DROP POLICY IF EXISTS "modulos_update" ON "tecnolabo"."modulos";
CREATE POLICY "modulos_update" ON "tecnolabo"."modulos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.es_super_admin())
  WITH CHECK (tecnolabo.es_super_admin());
DROP POLICY IF EXISTS "movimientos_delete" ON "tecnolabo"."movimientos_inventario";
CREATE POLICY "movimientos_delete" ON "tecnolabo"."movimientos_inventario"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "movimientos_insert" ON "tecnolabo"."movimientos_inventario";
CREATE POLICY "movimientos_insert" ON "tecnolabo"."movimientos_inventario"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "movimientos_select" ON "tecnolabo"."movimientos_inventario";
CREATE POLICY "movimientos_select" ON "tecnolabo"."movimientos_inventario"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "movimientos_update" ON "tecnolabo"."movimientos_inventario";
CREATE POLICY "movimientos_update" ON "tecnolabo"."movimientos_inventario"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_delete" ON "tecnolabo"."nota_credito";
CREATE POLICY "nota_credito_delete" ON "tecnolabo"."nota_credito"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_insert" ON "tecnolabo"."nota_credito";
CREATE POLICY "nota_credito_insert" ON "tecnolabo"."nota_credito"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_select" ON "tecnolabo"."nota_credito";
CREATE POLICY "nota_credito_select" ON "tecnolabo"."nota_credito"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_update" ON "tecnolabo"."nota_credito";
CREATE POLICY "nota_credito_update" ON "tecnolabo"."nota_credito"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_electronica_delete" ON "tecnolabo"."nota_credito_electronica";
CREATE POLICY "nota_credito_electronica_delete" ON "tecnolabo"."nota_credito_electronica"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_electronica_insert" ON "tecnolabo"."nota_credito_electronica";
CREATE POLICY "nota_credito_electronica_insert" ON "tecnolabo"."nota_credito_electronica"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_electronica_select" ON "tecnolabo"."nota_credito_electronica";
CREATE POLICY "nota_credito_electronica_select" ON "tecnolabo"."nota_credito_electronica"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_electronica_update" ON "tecnolabo"."nota_credito_electronica";
CREATE POLICY "nota_credito_electronica_update" ON "tecnolabo"."nota_credito_electronica"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_evento_delete" ON "tecnolabo"."nota_credito_evento";
CREATE POLICY "nota_credito_evento_delete" ON "tecnolabo"."nota_credito_evento"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_evento_insert" ON "tecnolabo"."nota_credito_evento";
CREATE POLICY "nota_credito_evento_insert" ON "tecnolabo"."nota_credito_evento"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_evento_select" ON "tecnolabo"."nota_credito_evento";
CREATE POLICY "nota_credito_evento_select" ON "tecnolabo"."nota_credito_evento"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "nota_credito_evento_update" ON "tecnolabo"."nota_credito_evento";
CREATE POLICY "nota_credito_evento_update" ON "tecnolabo"."nota_credito_evento"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "obligaciones_tributarias_catalogo_select" ON "tecnolabo"."obligaciones_tributarias_catalogo";
CREATE POLICY "obligaciones_tributarias_catalogo_select" ON "tecnolabo"."obligaciones_tributarias_catalogo"
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (true);
DROP POLICY IF EXISTS "obligaciones_tributarias_catalogo_select_sr" ON "tecnolabo"."obligaciones_tributarias_catalogo";
CREATE POLICY "obligaciones_tributarias_catalogo_select_sr" ON "tecnolabo"."obligaciones_tributarias_catalogo"
  AS PERMISSIVE
  FOR SELECT
  TO service_role
  USING (true);
DROP POLICY IF EXISTS "pagos_delete" ON "tecnolabo"."pagos";
CREATE POLICY "pagos_delete" ON "tecnolabo"."pagos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "pagos_insert" ON "tecnolabo"."pagos";
CREATE POLICY "pagos_insert" ON "tecnolabo"."pagos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "pagos_select" ON "tecnolabo"."pagos";
CREATE POLICY "pagos_select" ON "tecnolabo"."pagos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "pagos_update" ON "tecnolabo"."pagos";
CREATE POLICY "pagos_update" ON "tecnolabo"."pagos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "planes_delete" ON "tecnolabo"."planes";
CREATE POLICY "planes_delete" ON "tecnolabo"."planes"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "planes_insert" ON "tecnolabo"."planes";
CREATE POLICY "planes_insert" ON "tecnolabo"."planes"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "planes_select" ON "tecnolabo"."planes";
CREATE POLICY "planes_select" ON "tecnolabo"."planes"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "planes_update" ON "tecnolabo"."planes";
CREATE POLICY "planes_update" ON "tecnolabo"."planes"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "productos_delete" ON "tecnolabo"."productos";
CREATE POLICY "productos_delete" ON "tecnolabo"."productos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "productos_insert" ON "tecnolabo"."productos";
CREATE POLICY "productos_insert" ON "tecnolabo"."productos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "productos_select" ON "tecnolabo"."productos";
CREATE POLICY "productos_select" ON "tecnolabo"."productos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "productos_update" ON "tecnolabo"."productos";
CREATE POLICY "productos_update" ON "tecnolabo"."productos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categoria_rel_delete" ON "tecnolabo"."proveedor_categoria_rel";
CREATE POLICY "proveedor_categoria_rel_delete" ON "tecnolabo"."proveedor_categoria_rel"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categoria_rel_insert" ON "tecnolabo"."proveedor_categoria_rel";
CREATE POLICY "proveedor_categoria_rel_insert" ON "tecnolabo"."proveedor_categoria_rel"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categoria_rel_select" ON "tecnolabo"."proveedor_categoria_rel";
CREATE POLICY "proveedor_categoria_rel_select" ON "tecnolabo"."proveedor_categoria_rel"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categoria_rel_update" ON "tecnolabo"."proveedor_categoria_rel";
CREATE POLICY "proveedor_categoria_rel_update" ON "tecnolabo"."proveedor_categoria_rel"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categorias_delete" ON "tecnolabo"."proveedor_categorias";
CREATE POLICY "proveedor_categorias_delete" ON "tecnolabo"."proveedor_categorias"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categorias_insert" ON "tecnolabo"."proveedor_categorias";
CREATE POLICY "proveedor_categorias_insert" ON "tecnolabo"."proveedor_categorias"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categorias_select" ON "tecnolabo"."proveedor_categorias";
CREATE POLICY "proveedor_categorias_select" ON "tecnolabo"."proveedor_categorias"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_categorias_update" ON "tecnolabo"."proveedor_categorias";
CREATE POLICY "proveedor_categorias_update" ON "tecnolabo"."proveedor_categorias"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_productos_delete" ON "tecnolabo"."proveedor_productos";
CREATE POLICY "proveedor_productos_delete" ON "tecnolabo"."proveedor_productos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_productos_insert" ON "tecnolabo"."proveedor_productos";
CREATE POLICY "proveedor_productos_insert" ON "tecnolabo"."proveedor_productos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_productos_select" ON "tecnolabo"."proveedor_productos";
CREATE POLICY "proveedor_productos_select" ON "tecnolabo"."proveedor_productos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedor_productos_update" ON "tecnolabo"."proveedor_productos";
CREATE POLICY "proveedor_productos_update" ON "tecnolabo"."proveedor_productos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedores_delete" ON "tecnolabo"."proveedores";
CREATE POLICY "proveedores_delete" ON "tecnolabo"."proveedores"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedores_insert" ON "tecnolabo"."proveedores";
CREATE POLICY "proveedores_insert" ON "tecnolabo"."proveedores"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedores_select" ON "tecnolabo"."proveedores";
CREATE POLICY "proveedores_select" ON "tecnolabo"."proveedores"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proveedores_update" ON "tecnolabo"."proveedores";
CREATE POLICY "proveedores_update" ON "tecnolabo"."proveedores"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_archivos_delete" ON "tecnolabo"."proyecto_archivos";
CREATE POLICY "proyecto_archivos_delete" ON "tecnolabo"."proyecto_archivos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_archivos_insert" ON "tecnolabo"."proyecto_archivos";
CREATE POLICY "proyecto_archivos_insert" ON "tecnolabo"."proyecto_archivos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_archivos_select" ON "tecnolabo"."proyecto_archivos";
CREATE POLICY "proyecto_archivos_select" ON "tecnolabo"."proyecto_archivos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_archivos_update" ON "tecnolabo"."proyecto_archivos";
CREATE POLICY "proyecto_archivos_update" ON "tecnolabo"."proyecto_archivos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_comentarios_delete" ON "tecnolabo"."proyecto_comentarios";
CREATE POLICY "proyecto_comentarios_delete" ON "tecnolabo"."proyecto_comentarios"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_comentarios_insert" ON "tecnolabo"."proyecto_comentarios";
CREATE POLICY "proyecto_comentarios_insert" ON "tecnolabo"."proyecto_comentarios"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_comentarios_select" ON "tecnolabo"."proyecto_comentarios";
CREATE POLICY "proyecto_comentarios_select" ON "tecnolabo"."proyecto_comentarios"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_comentarios_update" ON "tecnolabo"."proyecto_comentarios";
CREATE POLICY "proyecto_comentarios_update" ON "tecnolabo"."proyecto_comentarios"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estado_historial_delete" ON "tecnolabo"."proyecto_estado_historial";
CREATE POLICY "proyecto_estado_historial_delete" ON "tecnolabo"."proyecto_estado_historial"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estado_historial_insert" ON "tecnolabo"."proyecto_estado_historial";
CREATE POLICY "proyecto_estado_historial_insert" ON "tecnolabo"."proyecto_estado_historial"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estado_historial_select" ON "tecnolabo"."proyecto_estado_historial";
CREATE POLICY "proyecto_estado_historial_select" ON "tecnolabo"."proyecto_estado_historial"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estado_historial_update" ON "tecnolabo"."proyecto_estado_historial";
CREATE POLICY "proyecto_estado_historial_update" ON "tecnolabo"."proyecto_estado_historial"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estados_delete" ON "tecnolabo"."proyecto_estados";
CREATE POLICY "proyecto_estados_delete" ON "tecnolabo"."proyecto_estados"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estados_insert" ON "tecnolabo"."proyecto_estados";
CREATE POLICY "proyecto_estados_insert" ON "tecnolabo"."proyecto_estados"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estados_select" ON "tecnolabo"."proyecto_estados";
CREATE POLICY "proyecto_estados_select" ON "tecnolabo"."proyecto_estados"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_estados_update" ON "tecnolabo"."proyecto_estados";
CREATE POLICY "proyecto_estados_update" ON "tecnolabo"."proyecto_estados"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_prioridades_config_delete" ON "tecnolabo"."proyecto_prioridades_config";
CREATE POLICY "proyecto_prioridades_config_delete" ON "tecnolabo"."proyecto_prioridades_config"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_prioridades_config_insert" ON "tecnolabo"."proyecto_prioridades_config";
CREATE POLICY "proyecto_prioridades_config_insert" ON "tecnolabo"."proyecto_prioridades_config"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_prioridades_config_select" ON "tecnolabo"."proyecto_prioridades_config";
CREATE POLICY "proyecto_prioridades_config_select" ON "tecnolabo"."proyecto_prioridades_config"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_prioridades_config_update" ON "tecnolabo"."proyecto_prioridades_config";
CREATE POLICY "proyecto_prioridades_config_update" ON "tecnolabo"."proyecto_prioridades_config"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tareas_delete" ON "tecnolabo"."proyecto_tareas";
CREATE POLICY "proyecto_tareas_delete" ON "tecnolabo"."proyecto_tareas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tareas_insert" ON "tecnolabo"."proyecto_tareas";
CREATE POLICY "proyecto_tareas_insert" ON "tecnolabo"."proyecto_tareas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tareas_select" ON "tecnolabo"."proyecto_tareas";
CREATE POLICY "proyecto_tareas_select" ON "tecnolabo"."proyecto_tareas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tareas_update" ON "tecnolabo"."proyecto_tareas";
CREATE POLICY "proyecto_tareas_update" ON "tecnolabo"."proyecto_tareas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tipos_delete" ON "tecnolabo"."proyecto_tipos";
CREATE POLICY "proyecto_tipos_delete" ON "tecnolabo"."proyecto_tipos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tipos_insert" ON "tecnolabo"."proyecto_tipos";
CREATE POLICY "proyecto_tipos_insert" ON "tecnolabo"."proyecto_tipos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tipos_select" ON "tecnolabo"."proyecto_tipos";
CREATE POLICY "proyecto_tipos_select" ON "tecnolabo"."proyecto_tipos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyecto_tipos_update" ON "tecnolabo"."proyecto_tipos";
CREATE POLICY "proyecto_tipos_update" ON "tecnolabo"."proyecto_tipos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyectos_delete" ON "tecnolabo"."proyectos";
CREATE POLICY "proyectos_delete" ON "tecnolabo"."proyectos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyectos_insert" ON "tecnolabo"."proyectos";
CREATE POLICY "proyectos_insert" ON "tecnolabo"."proyectos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyectos_select" ON "tecnolabo"."proyectos";
CREATE POLICY "proyectos_select" ON "tecnolabo"."proyectos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "proyectos_update" ON "tecnolabo"."proyectos";
CREATE POLICY "proyectos_update" ON "tecnolabo"."proyectos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "receta_items_delete" ON "tecnolabo"."receta_items";
CREATE POLICY "receta_items_delete" ON "tecnolabo"."receta_items"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "receta_items_insert" ON "tecnolabo"."receta_items";
CREATE POLICY "receta_items_insert" ON "tecnolabo"."receta_items"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "receta_items_select" ON "tecnolabo"."receta_items";
CREATE POLICY "receta_items_select" ON "tecnolabo"."receta_items"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "receta_items_update" ON "tecnolabo"."receta_items";
CREATE POLICY "receta_items_update" ON "tecnolabo"."receta_items"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "recetas_delete" ON "tecnolabo"."recetas";
CREATE POLICY "recetas_delete" ON "tecnolabo"."recetas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "recetas_insert" ON "tecnolabo"."recetas";
CREATE POLICY "recetas_insert" ON "tecnolabo"."recetas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "recetas_select" ON "tecnolabo"."recetas";
CREATE POLICY "recetas_select" ON "tecnolabo"."recetas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "recetas_update" ON "tecnolabo"."recetas";
CREATE POLICY "recetas_update" ON "tecnolabo"."recetas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_conv_delete" ON "tecnolabo"."sorteo_conversaciones";
CREATE POLICY "sorteo_conv_delete" ON "tecnolabo"."sorteo_conversaciones"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_conv_insert" ON "tecnolabo"."sorteo_conversaciones";
CREATE POLICY "sorteo_conv_insert" ON "tecnolabo"."sorteo_conversaciones"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_conv_select" ON "tecnolabo"."sorteo_conversaciones";
CREATE POLICY "sorteo_conv_select" ON "tecnolabo"."sorteo_conversaciones"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_conv_update" ON "tecnolabo"."sorteo_conversaciones";
CREATE POLICY "sorteo_conv_update" ON "tecnolabo"."sorteo_conversaciones"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_cup_delete" ON "tecnolabo"."sorteo_cupones";
CREATE POLICY "sorteo_cup_delete" ON "tecnolabo"."sorteo_cupones"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_cup_insert" ON "tecnolabo"."sorteo_cupones";
CREATE POLICY "sorteo_cup_insert" ON "tecnolabo"."sorteo_cupones"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_cup_select" ON "tecnolabo"."sorteo_cupones";
CREATE POLICY "sorteo_cup_select" ON "tecnolabo"."sorteo_cupones"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_cup_update" ON "tecnolabo"."sorteo_cupones";
CREATE POLICY "sorteo_cup_update" ON "tecnolabo"."sorteo_cupones"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ent_delete" ON "tecnolabo"."sorteo_entradas";
CREATE POLICY "sorteo_ent_delete" ON "tecnolabo"."sorteo_entradas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ent_insert" ON "tecnolabo"."sorteo_entradas";
CREATE POLICY "sorteo_ent_insert" ON "tecnolabo"."sorteo_entradas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ent_select" ON "tecnolabo"."sorteo_entradas";
CREATE POLICY "sorteo_ent_select" ON "tecnolabo"."sorteo_entradas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ent_update" ON "tecnolabo"."sorteo_entradas";
CREATE POLICY "sorteo_ent_update" ON "tecnolabo"."sorteo_entradas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_clicks_delete" ON "tecnolabo"."sorteo_revendedor_clicks";
CREATE POLICY "sorteo_rev_clicks_delete" ON "tecnolabo"."sorteo_revendedor_clicks"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_clicks_insert" ON "tecnolabo"."sorteo_revendedor_clicks";
CREATE POLICY "sorteo_rev_clicks_insert" ON "tecnolabo"."sorteo_revendedor_clicks"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_clicks_select" ON "tecnolabo"."sorteo_revendedor_clicks";
CREATE POLICY "sorteo_rev_clicks_select" ON "tecnolabo"."sorteo_revendedor_clicks"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_clicks_update" ON "tecnolabo"."sorteo_revendedor_clicks";
CREATE POLICY "sorteo_rev_clicks_update" ON "tecnolabo"."sorteo_revendedor_clicks"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_delete" ON "tecnolabo"."sorteo_revendedores";
CREATE POLICY "sorteo_rev_delete" ON "tecnolabo"."sorteo_revendedores"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_insert" ON "tecnolabo"."sorteo_revendedores";
CREATE POLICY "sorteo_rev_insert" ON "tecnolabo"."sorteo_revendedores"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_select" ON "tecnolabo"."sorteo_revendedores";
CREATE POLICY "sorteo_rev_select" ON "tecnolabo"."sorteo_revendedores"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_rev_update" ON "tecnolabo"."sorteo_revendedores";
CREATE POLICY "sorteo_rev_update" ON "tecnolabo"."sorteo_revendedores"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ticket_deliveries_delete" ON "tecnolabo"."sorteo_ticket_deliveries";
CREATE POLICY "sorteo_ticket_deliveries_delete" ON "tecnolabo"."sorteo_ticket_deliveries"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ticket_deliveries_insert" ON "tecnolabo"."sorteo_ticket_deliveries";
CREATE POLICY "sorteo_ticket_deliveries_insert" ON "tecnolabo"."sorteo_ticket_deliveries"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ticket_deliveries_select" ON "tecnolabo"."sorteo_ticket_deliveries";
CREATE POLICY "sorteo_ticket_deliveries_select" ON "tecnolabo"."sorteo_ticket_deliveries"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteo_ticket_deliveries_update" ON "tecnolabo"."sorteo_ticket_deliveries";
CREATE POLICY "sorteo_ticket_deliveries_update" ON "tecnolabo"."sorteo_ticket_deliveries"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteos_delete" ON "tecnolabo"."sorteos";
CREATE POLICY "sorteos_delete" ON "tecnolabo"."sorteos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteos_insert" ON "tecnolabo"."sorteos";
CREATE POLICY "sorteos_insert" ON "tecnolabo"."sorteos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteos_select" ON "tecnolabo"."sorteos";
CREATE POLICY "sorteos_select" ON "tecnolabo"."sorteos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "sorteos_update" ON "tecnolabo"."sorteos";
CREATE POLICY "sorteos_update" ON "tecnolabo"."sorteos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "suscripciones_delete" ON "tecnolabo"."suscripciones";
CREATE POLICY "suscripciones_delete" ON "tecnolabo"."suscripciones"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "suscripciones_insert" ON "tecnolabo"."suscripciones";
CREATE POLICY "suscripciones_insert" ON "tecnolabo"."suscripciones"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "suscripciones_select" ON "tecnolabo"."suscripciones";
CREATE POLICY "suscripciones_select" ON "tecnolabo"."suscripciones"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "suscripciones_update" ON "tecnolabo"."suscripciones";
CREATE POLICY "suscripciones_update" ON "tecnolabo"."suscripciones"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "tipificaciones_delete" ON "tecnolabo"."tipificaciones";
CREATE POLICY "tipificaciones_delete" ON "tecnolabo"."tipificaciones"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "tipificaciones_insert" ON "tecnolabo"."tipificaciones";
CREATE POLICY "tipificaciones_insert" ON "tecnolabo"."tipificaciones"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "tipificaciones_select" ON "tecnolabo"."tipificaciones";
CREATE POLICY "tipificaciones_select" ON "tecnolabo"."tipificaciones"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "tipificaciones_update" ON "tecnolabo"."tipificaciones";
CREATE POLICY "tipificaciones_update" ON "tecnolabo"."tipificaciones"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "udv_delete" ON "tecnolabo"."usuario_dashboard_views";
CREATE POLICY "udv_delete" ON "tecnolabo"."usuario_dashboard_views"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));
DROP POLICY IF EXISTS "udv_insert" ON "tecnolabo"."usuario_dashboard_views";
CREATE POLICY "udv_insert" ON "tecnolabo"."usuario_dashboard_views"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));
DROP POLICY IF EXISTS "udv_select" ON "tecnolabo"."usuario_dashboard_views";
CREATE POLICY "udv_select" ON "tecnolabo"."usuario_dashboard_views"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((tecnolabo.es_super_admin() OR (usuario_id IN ( SELECT usuarios.id
   FROM tecnolabo.usuarios
  WHERE (lower(TRIM(BOTH FROM COALESCE(usuarios.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text))))))));
DROP POLICY IF EXISTS "udv_update" ON "tecnolabo"."usuario_dashboard_views";
CREATE POLICY "udv_update" ON "tecnolabo"."usuario_dashboard_views"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))))
  WITH CHECK ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));
DROP POLICY IF EXISTS "usuario_modulos_delete" ON "tecnolabo"."usuario_modulos";
CREATE POLICY "usuario_modulos_delete" ON "tecnolabo"."usuario_modulos"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = tecnolabo.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));
DROP POLICY IF EXISTS "usuario_modulos_insert" ON "tecnolabo"."usuario_modulos";
CREATE POLICY "usuario_modulos_insert" ON "tecnolabo"."usuario_modulos"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = tecnolabo.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));
DROP POLICY IF EXISTS "usuario_modulos_select" ON "tecnolabo"."usuario_modulos";
CREATE POLICY "usuario_modulos_select" ON "tecnolabo"."usuario_modulos"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((tecnolabo.es_super_admin() OR (usuario_id IN ( SELECT usuarios.id
   FROM tecnolabo.usuarios
  WHERE (lower(TRIM(BOTH FROM COALESCE(usuarios.email, ''::text))) = tecnolabo.jwt_email_normalized())))));
DROP POLICY IF EXISTS "usuario_modulos_update" ON "tecnolabo"."usuario_modulos";
CREATE POLICY "usuario_modulos_update" ON "tecnolabo"."usuario_modulos"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = tecnolabo.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))))
  WITH CHECK ((tecnolabo.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (tecnolabo.usuarios ua
     JOIN tecnolabo.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = tecnolabo.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));
DROP POLICY IF EXISTS "usuarios_delete" ON "tecnolabo"."usuarios";
CREATE POLICY "usuarios_delete" ON "tecnolabo"."usuarios"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.es_super_admin());
DROP POLICY IF EXISTS "usuarios_insert" ON "tecnolabo"."usuarios";
CREATE POLICY "usuarios_insert" ON "tecnolabo"."usuarios"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK ((tecnolabo.es_super_admin() OR ((empresa_id = tecnolabo.empresa_id_actual()) AND (empresa_id IS NOT NULL))));
DROP POLICY IF EXISTS "usuarios_select" ON "tecnolabo"."usuarios";
CREATE POLICY "usuarios_select" ON "tecnolabo"."usuarios"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((tecnolabo.es_super_admin() OR (empresa_id = tecnolabo.empresa_id_actual()) OR ((empresa_id IS NULL) AND (rol = 'super_admin'::text)) OR (auth_user_id = auth.uid())));
DROP POLICY IF EXISTS "usuarios_update" ON "tecnolabo"."usuarios";
CREATE POLICY "usuarios_update" ON "tecnolabo"."usuarios"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING ((tecnolabo.es_super_admin() OR (empresa_id = tecnolabo.empresa_id_actual()) OR ((empresa_id IS NULL) AND (rol = 'super_admin'::text))))
  WITH CHECK ((tecnolabo.es_super_admin() OR (empresa_id = tecnolabo.empresa_id_actual()) OR ((empresa_id IS NULL) AND (rol = 'super_admin'::text))));
DROP POLICY IF EXISTS "ventas_delete" ON "tecnolabo"."ventas";
CREATE POLICY "ventas_delete" ON "tecnolabo"."ventas"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_insert" ON "tecnolabo"."ventas";
CREATE POLICY "ventas_insert" ON "tecnolabo"."ventas"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_select" ON "tecnolabo"."ventas";
CREATE POLICY "ventas_select" ON "tecnolabo"."ventas"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_update" ON "tecnolabo"."ventas";
CREATE POLICY "ventas_update" ON "tecnolabo"."ventas"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_items_delete" ON "tecnolabo"."ventas_items";
CREATE POLICY "ventas_items_delete" ON "tecnolabo"."ventas_items"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_items_insert" ON "tecnolabo"."ventas_items";
CREATE POLICY "ventas_items_insert" ON "tecnolabo"."ventas_items"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_items_select" ON "tecnolabo"."ventas_items";
CREATE POLICY "ventas_items_select" ON "tecnolabo"."ventas_items"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_items_update" ON "tecnolabo"."ventas_items";
CREATE POLICY "ventas_items_update" ON "tecnolabo"."ventas_items"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_pagos_detalle_delete" ON "tecnolabo"."ventas_pagos_detalle";
CREATE POLICY "ventas_pagos_detalle_delete" ON "tecnolabo"."ventas_pagos_detalle"
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_pagos_detalle_insert" ON "tecnolabo"."ventas_pagos_detalle";
CREATE POLICY "ventas_pagos_detalle_insert" ON "tecnolabo"."ventas_pagos_detalle"
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_pagos_detalle_select" ON "tecnolabo"."ventas_pagos_detalle";
CREATE POLICY "ventas_pagos_detalle_select" ON "tecnolabo"."ventas_pagos_detalle"
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id));
DROP POLICY IF EXISTS "ventas_pagos_detalle_update" ON "tecnolabo"."ventas_pagos_detalle";
CREATE POLICY "ventas_pagos_detalle_update" ON "tecnolabo"."ventas_pagos_detalle"
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING (tecnolabo.puede_acceder_empresa(empresa_id))
  WITH CHECK (tecnolabo.puede_acceder_empresa(empresa_id));

-- ── GRANTS ───────────────────────────────────────────────────────────────────

GRANT ALL ON ALL TABLES IN SCHEMA "tecnolabo" TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA "tecnolabo" TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA "tecnolabo" TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA "tecnolabo"
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA "tecnolabo"
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

COMMIT;
