/**
 * Backfill de `es_prueba` para documentos electrónicos históricos.
 *
 * Marca como PRUEBA (SIFEN ambiente test) los documentos ya emitidos, usando la
 * ÚNICA señal fiable persistida del flujo de test: el QR con sufijo '-test'
 * (…/consultas-test/qr?…), que en este sistema vive DENTRO del XML firmado
 * (bucket `sifen`, columna factura_electronica.xml_firmado_path), no en la
 * columna `qr_data`. Como respaldo también detecta el literal de prueba
 * "SIN VALOR COMERCIAL NI FISCAL" incrustado en el XML de test.
 *
 * NO usa estado='anulada' ni el modo 'sin_factura_fiscal' como proxy: un
 * documento real anulado sigue siendo real y NO se toca.
 *
 * Requiere en .env.local: SUPABASE_DB_URL, NEXT_PUBLIC_SUPABASE_URL,
 * SUPABASE_SERVICE_ROLE_KEY. Corre en un entorno SEGURO (no producción sin
 * autorización). Requisito previo: aplicar la migración
 * 20260910130000_facturas_es_prueba.sql (agrega la columna es_prueba).
 *
 * Uso:
 *   npx tsx scripts/backfill-facturas-es-prueba.ts            # dry-run (no escribe)
 *   npx tsx scripts/backfill-facturas-es-prueba.ts --apply    # aplica cambios
 *   npx tsx scripts/backfill-facturas-es-prueba.ts <schema> --apply
 */
import { config } from "dotenv";
import path from "path";
import pg from "pg";
import { createClient } from "@supabase/supabase-js";

config({ path: path.resolve(process.cwd(), ".env.local") });

const SIFEN_BUCKET = "sifen";
// Señales de PRUEBA dentro del XML firmado.
const SIGNAL_QR_TEST = "/consultas-test/";
const SIGNAL_LITERAL = "SIN VALOR COMERCIAL NI FISCAL";

async function main() {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const schemaArg = args.find((a) => !a.startsWith("--")) ?? "";

  const dbUrl = process.env.SUPABASE_DB_URL?.trim();
  const sbUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const sbKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!dbUrl) throw new Error("Falta SUPABASE_DB_URL en .env.local");
  if (!sbUrl || !sbKey) throw new Error("Falta NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY en .env.local");

  const client = new pg.Client({
    connectionString: dbUrl,
    ssl: dbUrl.includes("supabase") ? { rejectUnauthorized: false } : undefined,
  });
  await client.connect();
  const storage = createClient(sbUrl, sbKey);

  try {
    // Resolver schema de negocio (igual criterio que qa-tecnolabo).
    const sres = await client.query(
      `SELECT n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname='factura_electronica' AND c.relkind='r'
          AND n.nspname NOT IN ('public','pg_catalog','information_schema')
        ORDER BY 1`,
    );
    const candidatos = sres.rows.map((r) => r.nspname as string);
    const pedido = (schemaArg || process.env.QA_SCHEMA || process.env.NEURA_CLIENT_SCHEMA || "").trim();
    const schema = pedido && candidatos.includes(pedido)
      ? pedido
      : candidatos.includes("tecnolabo")
      ? "tecnolabo"
      : candidatos[0];
    if (!schema) throw new Error("No se encontró un schema con factura_electronica.");
    console.log(`Schema: ${schema} · modo: ${apply ? "APPLY (escribe)" : "DRY-RUN (no escribe)"}\n`);

    // Verificar que la columna exista (migración aplicada).
    const col = await client.query(
      `SELECT 1 FROM information_schema.columns WHERE table_schema=$1 AND table_name='factura_electronica' AND column_name='es_prueba'`,
      [schema],
    );
    if (col.rowCount === 0) {
      throw new Error("Falta factura_electronica.es_prueba. Aplicá primero la migración 20260910130000_facturas_es_prueba.sql.");
    }

    // Candidatos: documentos firmados aún no marcados.
    const rows = (
      await client.query(
        `SELECT id, empresa_id, factura_id, xml_firmado_path
           FROM "${schema}".factura_electronica
          WHERE es_prueba = false AND xml_firmado_path IS NOT NULL AND btrim(xml_firmado_path) <> ''
          ORDER BY created_at ASC`,
      )
    ).rows as Array<{ id: string; empresa_id: string; factura_id: string | null; xml_firmado_path: string }>;

    console.log(`Documentos firmados a inspeccionar: ${rows.length}\n`);

    let prueba = 0;
    let reales = 0;
    let sinXml = 0;
    const marcarFE: string[] = [];
    const marcarFactura: string[] = [];

    for (const r of rows) {
      const dl = await storage.storage.from(SIFEN_BUCKET).download(r.xml_firmado_path);
      if (dl.error || !dl.data) {
        sinXml++;
        console.warn(`  ⚠ ${r.id}: no se pudo descargar ${r.xml_firmado_path} (${dl.error?.message ?? "sin datos"})`);
        continue;
      }
      const xml = Buffer.from(await dl.data.arrayBuffer()).toString("utf8");
      const esPrueba = xml.includes(SIGNAL_QR_TEST) || xml.includes(SIGNAL_LITERAL);
      if (esPrueba) {
        prueba++;
        marcarFE.push(r.id);
        if (r.factura_id) marcarFactura.push(r.factura_id);
        console.log(`  ✔ PRUEBA  ${r.id}  (factura ${r.factura_id ?? "—"})`);
      } else {
        reales++;
      }
    }

    console.log(`\nResumen: ${prueba} de prueba · ${reales} reales · ${sinXml} sin XML accesible.`);

    if (!apply) {
      console.log("\nDRY-RUN: no se escribió nada. Volvé a correr con --apply para marcar es_prueba.");
      return;
    }
    if (marcarFE.length === 0) {
      console.log("\nNada para marcar.");
      return;
    }

    await client.query("BEGIN");
    await client.query(
      `UPDATE "${schema}".factura_electronica SET es_prueba = true WHERE id = ANY($1::uuid[])`,
      [marcarFE],
    );
    if (marcarFactura.length > 0) {
      await client.query(
        `UPDATE "${schema}".facturas SET es_prueba = true WHERE id = ANY($1::uuid[])`,
        [marcarFactura],
      );
    }
    await client.query("COMMIT");
    console.log(`\nAplicado: ${marcarFE.length} documentos y ${marcarFactura.length} facturas marcados como prueba.`);
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
