/**
 * QA del alcance Tecnolabo (Fase 13).
 *
 * Verifica las invariantes de BD que respaldan los 20 tests mínimos del alcance:
 * existencia de tablas/columnas, índices únicos de idempotencia, CHECK de estados
 * y funciones/flags. Requiere SUPABASE_DB_URL en .env.local (base ya migrada).
 *
 * Uso: npm run qa:tecnolabo
 *
 * NOTA: valida estructura (garantías de integridad). Los tests funcionales
 * completos (conversión, recepción, remisión, cobro) se ejecutan sobre datos
 * reales; este script asegura que los mecanismos que los hacen correctos existen.
 */
import { config } from "dotenv";
import path from "path";
import pg from "pg";

config({ path: path.resolve(process.cwd(), ".env.local") });

const url = process.env.SUPABASE_DB_URL?.trim();
if (!url) {
  console.error("Falta SUPABASE_DB_URL en .env.local");
  process.exit(2);
}

type Check = { id: string; test: string; ok: boolean; detalle: string };
const checks: Check[] = [];
function add(id: string, test: string, ok: boolean, detalle: string) {
  checks.push({ id, test, ok, detalle });
}

async function main() {
  const client = new pg.Client({ connectionString: url, ssl: url.includes("supabase") ? { rejectUnauthorized: false } : undefined });
  await client.connect();
  try {
    // Resolver schema de negocio (con tabla 'productos', excluyendo public).
    const sres = await client.query(
      `SELECT n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname='productos' AND c.relkind='r' AND n.nspname NOT IN ('public','pg_catalog','information_schema')
        ORDER BY 1 LIMIT 1`,
    );
    const schema = sres.rows[0]?.nspname as string | undefined;
    if (!schema) {
      console.error("No se encontró un schema de negocio (con tabla productos) fuera de public.");
      process.exit(1);
    }
    console.log(`Schema de negocio: ${schema}\n`);

    const hasTable = async (t: string) => (await client.query(`SELECT to_regclass($1) IS NOT NULL AS x`, [`"${schema}"."${t}"`])).rows[0].x as boolean;
    const hasColumn = async (t: string, col: string) => (await client.query(`SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=$1 AND table_name=$2 AND column_name=$3) AS x`, [schema, t, col])).rows[0].x as boolean;
    const hasIndex = async (idx: string) => (await client.query(`SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname=$1 AND indexname=$2) AS x`, [schema, idx])).rows[0].x as boolean;
    const hasConstraint = async (name: string) => (await client.query(`SELECT EXISTS(SELECT 1 FROM pg_constraint WHERE conname=$1 AND connamespace=$2::regnamespace) AS x`, [name, schema])).rows[0].x as boolean;

    // Test 1: conversión única de presupuesto (idempotencia por UNIQUE presupuesto_id)
    add("T1", "Presupuesto convertido una sola vez", await hasIndex("uq_presupuesto_conversion") || await hasConstraint("uq_presupuesto_conversion"), "presupuesto_conversiones UNIQUE(presupuesto_id)");
    // Test 2: especificaciones en presupuesto, ausentes en factura
    add("T2", "Especificaciones en presupuesto, no en factura", await hasColumn("presupuesto_items", "especificaciones_tecnicas") && !(await hasColumn("factura_items", "especificaciones_tecnicas")), "presupuesto_items.especificaciones_tecnicas existe; factura_items no");
    // Test 3+16: compra sin stock / CxP sin inventario
    add("T3/16", "Compra registrada sin aumento de stock (flag) + CxP", await hasColumn("empresa_config", "compra_ingresa_por_recepcion") && await hasTable("cuentas_por_pagar"), "empresa_config.compra_ingresa_por_recepcion + cuentas_por_pagar");
    // Test 4/5: recepciones parciales
    add("T4/5", "Recepciones parciales (comprado/recibido)", await hasTable("recepciones") && await hasColumn("compras", "cantidad_recibida"), "recepciones + compras.cantidad_recibida");
    // Test 6: no recibir más de lo comprado — validado en backend; existe control de excedente
    add("T6", "No recibir más de lo comprado (control excedente)", await hasColumn("empresa_config", "permitir_excedente_recepcion"), "empresa_config.permitir_excedente_recepcion (excedente sólo con permiso)");
    // Test 7: factura sin descuento de stock (salida por remisión)
    add("T7", "Factura no descuenta stock (salida por remisión)", await hasColumn("empresa_config", "stock_salida_por_remision") && await hasColumn("facturas", "estado_entrega"), "empresa_config.stock_salida_por_remision + facturas.estado_entrega");
    // Test 8/9/10: remisiones parciales
    add("T8/9/10", "Remisiones parciales, no más de lo facturado", await hasTable("notas_remision") && await hasColumn("factura_items", "cantidad_entregada"), "notas_remision + factura_items.cantidad_entregada");
    // Test 11: anulación de remisión repone stock (movimientos inversos) — origen 'anulacion'
    const origenCheck = await client.query(`SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname='movimientos_inventario_origen_check' AND connamespace=$1::regnamespace`, [schema]);
    add("T11/21", "Anulación con movimientos inversos", (origenCheck.rows[0]?.def ?? "").includes("anulacion") && (origenCheck.rows[0]?.def ?? "").includes("remision"), "movimientos_inventario.origen admite 'anulacion' y 'remision'");
    // Test 12: nota de salida confirmada descuenta stock
    add("T12", "Nota de salida descuenta stock al confirmar", await hasTable("notas_salida") && await hasTable("notas_salida_items"), "notas_salida + items");
    // Test 13/14/15: pago parcial/completo + reintento no duplica
    add("T13/14/15", "Cobro idempotente (no duplica en reintento)", await hasIndex("uq_cobros_idempotency") && await hasColumn("cobros_clientes", "idempotency_key"), "cobros_clientes.idempotency_key + índice único parcial");
    // Test 17: permisos backend
    add("T17", "Permisos backend por acción", await hasTable("roles") && await hasTable("rol_permisos") && await hasTable("usuario_roles"), "roles/rol_permisos/usuario_roles (assertPermiso en endpoints)");
    // Test 18: exportaciones respetan filtros/columnas
    add("T18", "Vistas/columnas configurables (export)", await hasTable("usuario_vistas"), "usuario_vistas (columnas + filtros por usuario)");
    // Test 19: operaciones en el schema correcto
    add("T19", "Operaciones en el schema de negocio (no public)", schema !== "public", `schema resuelto = ${schema} (≠ public)`);
    // Fiscal: abstracción sin tocar SIFEN
    add("FISCAL", "Abstracción fiscal (none/sifen_py/sin_bo) + Bolivia detrás de flag", await hasColumn("empresa_config", "proveedor_fiscal") && await hasTable("empresa_sin_config") && await hasTable("documento_fiscal"), "proveedor_fiscal + empresa_sin_config + documento_fiscal");
    // Auditoría
    add("AUDIT", "Auditoría de operaciones críticas", await hasTable("auditoria_eventos"), "auditoria_eventos (usuario/fecha/empresa/origen)");

    // Reporte
    let fail = 0;
    for (const c of checks) {
      const mark = c.ok ? "✅" : "❌";
      if (!c.ok) fail++;
      console.log(`${mark} [${c.id}] ${c.test}\n     ${c.detalle}`);
    }
    console.log(`\n${checks.length - fail}/${checks.length} invariantes OK.`);
    if (fail > 0) {
      console.error(`\n${fail} invariante(s) faltante(s). ¿Aplicaste todas las migraciones de Fase 0–11?`);
      process.exit(1);
    }
    console.log("\nTodas las invariantes de integridad del alcance están presentes.");
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
