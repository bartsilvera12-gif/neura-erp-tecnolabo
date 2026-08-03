-- =============================================================================
-- Datos iniciales de Tecnolabo: empresa, modulos y catalogos minimos.
--
-- empresa_id exclusivo de Tecnolabo: 2473b6f2-b0c4-4c20-ade7-3cd581a5327b
-- Generado nuevo: NO se reutiliza el empresa_id de Ferrecolor ni de Instemaq.
--
-- Solo catalogos de sistema (modulos, vistas de dashboard, etapas CRM y tipos
-- de servicio). NO incluye clientes, productos, proveedores, ventas, compras,
-- pagos, cajas, comprobantes, facturas, conversaciones ni usuarios.
--
-- Datos fiscales (RUC, telefono, email, direccion) quedan NULL a proposito:
-- se cargan con la informacion real de Tecnolabo; no se heredan ni se inventan.
--
-- Idempotente: re-ejecutable sin duplicar filas.
-- =============================================================================

BEGIN;

-- ── Empresa ──────────────────────────────────────────────────────────────────
INSERT INTO "tecnolabo"."empresas"
  (id, nombre_empresa, ruc, telefono, email, direccion, pais, plan, estado, data_schema)
SELECT
  '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'Tecnolabo', NULL, NULL, NULL, NULL,
  'PARAGUAY', NULL, 'ACTIVA', 'tecnolabo'
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."empresas" WHERE id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid);

-- ── Catalogo de modulos (nivel producto, ids nuevos) ─────────────────────────
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '722c1e88-a971-4ca6-b1d4-563bb1b9a5e6'::uuid, 'campanas', 'Campañas WhatsApp', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'campanas');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'f4dc82b5-cf1e-4e7c-a739-d0e2234aa307'::uuid, 'clientes', 'Clientes', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'clientes');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'fe38a9db-479c-4ede-b4e7-77a7e857919e'::uuid, 'cobros', 'Cobros', 'Cuentas por cobrar y cobros de clientes'
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'cobros');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'f14eb94b-3eaa-4ab2-bcca-5f2bc1413ac1'::uuid, 'comisiones', 'Comisiones', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'comisiones');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'a915709a-c2f1-4fc0-8fe1-c3a1dd75ac91'::uuid, 'compras', 'Compras', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'compras');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'de8e2db7-7a14-401d-b1f4-c498d0564b79'::uuid, 'configuracion', 'Configuración', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'configuracion');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'd5ef85c3-c6b8-4ded-a688-f2854af1cd89'::uuid, 'conversaciones', 'Conversaciones', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'conversaciones');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '4cfb81ac-6d26-4c5e-a91a-74cea8d51b14'::uuid, 'conversaciones-finalizadas', 'Conversaciones finalizadas', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'conversaciones-finalizadas');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'f7ee5533-a435-4891-89ad-d6737fa5f0d9'::uuid, 'crm', 'CRM Funnel', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'crm');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'd1e82f5d-eeea-4cb1-be7b-c7de19d97175'::uuid, 'dashboard', 'Dashboard', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'dashboard');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'ef90ba07-6456-488d-924e-ad2313fed424'::uuid, 'gastos', 'Gastos', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'gastos');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '08ca9d03-7773-4023-b231-4eb5a909c902'::uuid, 'gestion-clientes', 'Gestión Clientes', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'gestion-clientes');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'f09209eb-98b9-49b4-aaaa-fe91d738b215'::uuid, 'historial-omnicanal', 'Historial omnicanal', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'historial-omnicanal');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '8bd628fe-226d-46b8-a804-c6e4ee746d3f'::uuid, 'inventario', 'Inventario', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'inventario');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'c389f4c8-1ba7-4b83-b79e-ce660affbbc5'::uuid, 'marketing', 'Marketing Ops', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'marketing');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '4d68d8cd-fef7-4326-90a8-96f88df8d8c4'::uuid, 'marketing_ops', 'Marketing Ops', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'marketing_ops');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '5da1ef29-2b21-4357-8f7d-b3bbb1e3af12'::uuid, 'monitoreo', 'Monitoreo', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'monitoreo');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '4eb47c79-8992-435f-a400-c8bed4942fe0'::uuid, 'notas_credito', 'Notas de crédito', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'notas_credito');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'd6d797de-b725-434a-adc4-9fb25cfcf324'::uuid, 'omnicanal', 'Omnicanal (paquete)', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'omnicanal');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'e13e4f60-a6e5-4463-a074-271ea5c690dc'::uuid, 'pagos', 'Pagos', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'pagos');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '3cedd45f-69c8-4fc7-a89b-b4e43d1b6273'::uuid, 'planes', 'Planes', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'planes');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'da2ae91f-ef33-4e73-b5ba-4e37c66815ab'::uuid, 'presupuestos', 'Presupuestos', 'Presupuestos / cotizaciones comerciales'
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'presupuestos');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '9eb7c03e-4685-466f-b7e0-0eefc625de34'::uuid, 'proyectos', 'Proyectos', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'proyectos');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '4dd7221c-290d-4124-9609-75a225797a38'::uuid, 'recetas', 'Recetas', 'Recetas y costeo de productos'
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'recetas');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '83432cea-220c-4b91-8df5-75a197e6b246'::uuid, 'reportes', 'Reportes', 'Reportería operativa (estado de cuenta, proveedores)'
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'reportes');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '3ae07c8e-5dce-4951-bcd6-2a04dfb1e367'::uuid, 'sorteos', 'Sorteos', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'sorteos');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT 'a9036957-a0ee-4b74-ab8a-d93ea19910eb'::uuid, 'usuarios', 'Usuarios', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'usuarios');
INSERT INTO "tecnolabo"."modulos" (id, slug, nombre, descripcion)
SELECT '64b6240e-ee7d-4cdd-b1d2-bcd0d16da476'::uuid, 'ventas', 'Ventas', NULL
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."modulos" WHERE slug = 'ventas');

-- ── Modulos habilitados para la empresa ──────────────────────────────────────
-- Se replica el conjunto habilitado del ERP fuente. PENDIENTE: confirmar contra
-- el alcance contratado por Tecnolabo y desactivar los que no correspondan.
INSERT INTO "tecnolabo"."empresa_modulos" (empresa_id, modulo_id, activo)
SELECT '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, m.id, true
  FROM "tecnolabo"."modulos" m
 WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."empresa_modulos" em
                    WHERE em.empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND em.modulo_id = m.id);

-- ── Vistas de dashboard (catalogo de producto, ids nuevos) ───────────────────
INSERT INTO "tecnolabo"."dashboard_views" (id, slug, nombre, orden, activo)
SELECT 'c507c7a6-53f3-4c3f-8af1-d3518b6477d0'::uuid, 'comercial', 'Comercial', 10, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."dashboard_views" WHERE slug = 'comercial');
INSERT INTO "tecnolabo"."dashboard_views" (id, slug, nombre, orden, activo)
SELECT '4e8f6b13-c9fb-4ff6-9ab5-197f3451404b'::uuid, 'financiero', 'Financiero', 20, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."dashboard_views" WHERE slug = 'financiero');
INSERT INTO "tecnolabo"."dashboard_views" (id, slug, nombre, orden, activo)
SELECT '64f7776e-a4bb-4107-88fc-520851708699'::uuid, 'inventario', 'Inventario', 30, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."dashboard_views" WHERE slug = 'inventario');
INSERT INTO "tecnolabo"."dashboard_views" (id, slug, nombre, orden, activo)
SELECT '0d89e765-845b-40a4-8b84-a0260411d05e'::uuid, 'ventas', 'Ventas', 40, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."dashboard_views" WHERE slug = 'ventas');

INSERT INTO "tecnolabo"."empresa_dashboard_views" (empresa_id, dashboard_view_id, activo)
SELECT '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, v.id, true
  FROM "tecnolabo"."dashboard_views" v
 WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."empresa_dashboard_views" e
                    WHERE e.empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND e.dashboard_view_id = v.id);

-- ── Etapas CRM (pipeline generico) ───────────────────────────────────────────
INSERT INTO "tecnolabo"."crm_etapas" (id, empresa_id, codigo, nombre, color, orden, activo)
SELECT '371e1d0a-8810-4948-8d89-23c816b38bdb'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'LEAD', 'Lead',
       'gray', 1, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."crm_etapas"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND codigo = 'LEAD');
INSERT INTO "tecnolabo"."crm_etapas" (id, empresa_id, codigo, nombre, color, orden, activo)
SELECT '2f5e80c2-d3fe-4791-b9cc-e1a5584b861d'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'CONTACTADO', 'Contactado',
       'blue', 2, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."crm_etapas"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND codigo = 'CONTACTADO');
INSERT INTO "tecnolabo"."crm_etapas" (id, empresa_id, codigo, nombre, color, orden, activo)
SELECT 'd44ab594-dd2f-445b-8b35-0d137efb78c2'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'NEGOCIACION', 'Negociación',
       'amber', 3, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."crm_etapas"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND codigo = 'NEGOCIACION');
INSERT INTO "tecnolabo"."crm_etapas" (id, empresa_id, codigo, nombre, color, orden, activo)
SELECT '74f2e989-47b6-493b-a4d5-5f032ec76b49'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'GANADO', 'Ganado',
       'green', 4, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."crm_etapas"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND codigo = 'GANADO');
INSERT INTO "tecnolabo"."crm_etapas" (id, empresa_id, codigo, nombre, color, orden, activo)
SELECT '3ebf1c4c-3ec9-4d5c-864e-92e2b2590071'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'PERDIDO', 'Perdido',
       'red', 5, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."crm_etapas"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND codigo = 'PERDIDO');

-- ── Tipos de servicio de cliente (catalogo de sistema) ───────────────────────
-- Requerido por el trigger trg_clientes_tipo_servicio_requiere_catalogo.
INSERT INTO "tecnolabo"."cliente_tipos_servicio_catalogo"
  (id, empresa_id, slug, nombre, activo, orden, es_sistema)
SELECT '2b05ba60-df84-41f2-ad3e-c2c9e9ead300'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'marketing', 'Marketing',
       true, 10, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."cliente_tipos_servicio_catalogo"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND slug = 'marketing');
INSERT INTO "tecnolabo"."cliente_tipos_servicio_catalogo"
  (id, empresa_id, slug, nombre, activo, orden, es_sistema)
SELECT 'a4aa4682-50fa-4715-87bf-a5538c5e229e'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'saas', 'SaaS',
       true, 20, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."cliente_tipos_servicio_catalogo"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND slug = 'saas');
INSERT INTO "tecnolabo"."cliente_tipos_servicio_catalogo"
  (id, empresa_id, slug, nombre, activo, orden, es_sistema)
SELECT '064b87b4-acea-4057-8d15-b8eeb2ae7684'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'branding', 'Branding',
       true, 30, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."cliente_tipos_servicio_catalogo"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND slug = 'branding');
INSERT INTO "tecnolabo"."cliente_tipos_servicio_catalogo"
  (id, empresa_id, slug, nombre, activo, orden, es_sistema)
SELECT 'b0a0394d-0891-42b6-adf9-fe32b6dd2fd0'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'web', 'Web',
       true, 40, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."cliente_tipos_servicio_catalogo"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND slug = 'web');
INSERT INTO "tecnolabo"."cliente_tipos_servicio_catalogo"
  (id, empresa_id, slug, nombre, activo, orden, es_sistema)
SELECT '8715dda9-6c99-4e4e-b9dd-430fbf394107'::uuid, '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 'otro', 'Otro',
       true, 50, true
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."cliente_tipos_servicio_catalogo"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid AND slug = 'otro');

-- ── Secuencia de codigo de productos (arranca en cero) ───────────────────────
INSERT INTO "tecnolabo"."productos_codigo_secuencia" (empresa_id, last_value)
SELECT '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid, 0
WHERE NOT EXISTS (SELECT 1 FROM "tecnolabo"."productos_codigo_secuencia"
                   WHERE empresa_id = '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid);

COMMIT;
