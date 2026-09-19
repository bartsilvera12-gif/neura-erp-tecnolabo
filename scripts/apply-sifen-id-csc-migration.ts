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

  const after = await client.query(
    `SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'empresa_sifen_config'
       AND column_name IN ('csc', 'id_csc')
     ORDER BY column_name`
  );
  console.log("Columnas:", after.rows.map((r) => r.column_name).join(", ") || "(ninguna)");

  await client.end();
  console.log("OK: migración aplicada.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
