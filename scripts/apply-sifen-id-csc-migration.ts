/**
 * Aplica supabase/migrations/20260919120000_sifen_id_csc.sql al proyecto remoto
 * (agrega `empresa_sifen_config.id_csc`, el IdCSC que va en la URL del QR).
 * Requiere en .env.local: SUPABASE_DB_URL o (SUPABASE_DB_PASSWORD + NEXT_PUBLIC_SUPABASE_URL)
 *
 * npm run db:apply-sifen-id-csc
 */
import { config } from "dotenv";
import { readFileSync } from "fs";
import { join } from "path";
import pg from "pg";

config({ path: join(process.cwd(), ".env.local") });

const { Client } = pg;

const MIGRATION = "20260919120000_sifen_id_csc.sql";

function getDbUrl(): string {
  const direct = process.env.SUPABASE_DB_URL?.trim();
  if (direct) return direct;
  const password = process.env.SUPABASE_DB_PASSWORD?.trim();
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const m = base?.match(/https:\/\/([^.]+)\.supabase\.co/i);
  if (!password || !m?.[1]) {
    throw new Error(
      "Falta SUPABASE_DB_URL o (SUPABASE_DB_PASSWORD + NEXT_PUBLIC_SUPABASE_URL) en .env.local"
    );
  }
  const ref = m[1];
  return `postgresql://postgres:${encodeURIComponent(password)}@db.${ref}.supabase.co:5432/postgres`;
}

async function main() {
  const sqlPath = join(process.cwd(), "supabase", "migrations", MIGRATION);
  const sql = readFileSync(sqlPath, "utf-8");
  const url = getDbUrl();
  const client = new Client({
    connectionString: url,
    ssl: url.includes("supabase") ? { rejectUnauthorized: false } : undefined,
  });
  await client.connect();

  console.log("Ejecutando", MIGRATION, "...");
  await client.query(sql);

  // La tabla vive en el schema del cliente (no en `public`), así que se verifica
  // en todos los schemas donde exista.
  const after = await client.query(
    `SELECT table_schema, column_name
       FROM information_schema.columns
      WHERE table_name = 'empresa_sifen_config'
        AND column_name = 'id_csc'
        AND table_schema NOT IN ('public', 'pg_catalog', 'information_schema')
      ORDER BY table_schema`
  );
  if (after.rows.length === 0) {
    throw new Error("La columna id_csc no quedó creada en ningún schema de cliente.");
  }
  for (const r of after.rows) {
    console.log(`OK ${r.table_schema}.empresa_sifen_config.id_csc`);
  }

  await client.end();
  console.log("OK: migración aplicada.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
