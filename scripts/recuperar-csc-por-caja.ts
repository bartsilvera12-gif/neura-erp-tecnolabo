/**
 * Recupera el CSC exacto que el SET aceptó, a partir de un documento YA APROBADO.
 *
 * Caso de uso: la configuración se perdió y el CSC se volvió a cargar a mano. El
 * CSC es hexadecimal con caja mezclada (p. ej. `8f86E137AfD2f5cF68EE08E5Ea907e35`),
 * así que al retipearlo es fácil equivocar la caja de alguna letra o un dígito.
 * El valor "se ve igual" pero el `cHashQR` cambia, y el SET rechaza todo DE nuevo
 * con «El hash del código QR incluido el de la cadena de caracteres es inválido».
 *
 * Un DE que el SET APROBÓ antes del incidente lleva en su `dCarQR` un `cHashQR`
 * calculado con el CSC correcto. Esta herramienta prueba variantes del CSC actual
 * contra ese hash y devuelve la que lo reproduce: ese es el CSC bueno.
 *
 * Solo prueba variantes del CSC que YA está configurado (caja de sus letras y,
 * con --typo, un único carácter distinto). No descubre un CSC desconocido.
 *
 * Uso:
 *   npx tsx scripts/recuperar-csc-por-caja.ts <xml-aprobado> --csc <CSC actual> [--typo]
 *   npx tsx scripts/recuperar-csc-por-caja.ts <ruta-en-bucket> --desde-bd [--typo]
 */
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { config } from "dotenv";
import pg from "pg";
import { createClient } from "@supabase/supabase-js";

config({ path: resolve(process.cwd(), ".env.local") });

const SIFEN_BUCKET = "sifen";
const ID_CSC_CANDIDATOS = ["0001", "0002"] as const;
const HEX = "0123456789abcdefABCDEF";

function desescaparXml(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n: string) => String.fromCharCode(parseInt(n, 10)))
    .replace(/&amp;/g, "&");
}

async function leerXml(arg: string): Promise<string> {
  const local = resolve(process.cwd(), arg);
  if (existsSync(local)) return readFileSync(local, "utf8");
  const sbUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const sbKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!sbUrl || !sbKey) {
    throw new Error(
      `No existe el archivo "${arg}" y falta NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY en .env.local.`
    );
  }
  const { data, error } = await createClient(sbUrl, sbKey)
    .storage.from(SIFEN_BUCKET)
    .download(arg.replace(/^sifen\//, ""));
  if (error || !data) {
    throw new Error(`No se pudo descargar del bucket: ${error?.message ?? "objeto no encontrado"}`);
  }
  return Buffer.from(await data.arrayBuffer()).toString("utf8");
}

function citarIdent(ident: string): string {
  return `"${ident.replace(/"/g, '""')}"`;
}

async function cscDesdeBd(rucEmisor: string): Promise<string[]> {
  const dbUrl = process.env.SUPABASE_DB_URL?.trim();
  if (!dbUrl) throw new Error("Falta SUPABASE_DB_URL en .env.local para leer el CSC de la base.");
  const client = new pg.Client({
    connectionString: dbUrl,
    ssl: dbUrl.includes("supabase") ? { rejectUnauthorized: false } : undefined,
  });
  await client.connect();
  try {
    const schemas = await client.query(
      `SELECT n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'empresa_sifen_config' AND c.relkind = 'r'
          AND n.nspname NOT IN ('public','pg_catalog','information_schema')
        ORDER BY 1`
    );
    const out: string[] = [];
    for (const { nspname } of schemas.rows as { nspname: string }[]) {
      const r = await client.query(
        `SELECT csc FROM ${citarIdent(nspname)}.empresa_sifen_config
          WHERE replace(ruc, '-', '') LIKE $1 || '%' AND coalesce(btrim(csc), '') <> ''`,
        [rucEmisor]
      );
      for (const row of r.rows as { csc: string }[]) out.push(String(row.csc).trim());
    }
    return out;
  } finally {
    await client.end();
  }
}

/** Reemplaza el IdCSC de la cadena por cada candidato, una sola vez. */
function cadenasPorIdCsc(params: string): { idCsc: string; cadena: string }[] {
  return ID_CSC_CANDIDATOS.map((idCsc) => ({
    idCsc,
    cadena: params.replace(/IdCSC=\d{4}/, `IdCSC=${idCsc}`),
  }));
}

function sha256(s: string): string {
  return createHash("sha256").update(s, "utf8").digest("hex");
}

/** Todas las combinaciones de caja de las letras de `csc` (2^n, n = cantidad de letras). */
function* variantesDeCaja(csc: string): Generator<string> {
  const pos = [...csc].map((c, i) => (/[a-zA-Z]/.test(c) ? i : -1)).filter((i) => i >= 0);
  const total = 2 ** pos.length;
  for (let mask = 0; mask < total; mask++) {
    const chars = [...csc];
    for (let b = 0; b < pos.length; b++) {
      const i = pos[b]!;
      chars[i] = mask & (1 << b) ? chars[i]!.toUpperCase() : chars[i]!.toLowerCase();
    }
    yield chars.join("");
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const conTypo = args.includes("--typo");
  const desdeBd = args.includes("--desde-bd");
  const iCsc = args.indexOf("--csc");
  const cscArg = iCsc >= 0 ? args[iCsc + 1] : undefined;
  const ruta = args.filter((a, i) => !a.startsWith("--") && i !== iCsc + 1)[0];

  if (!ruta || (!cscArg && !desdeBd)) {
    console.error(
      "Uso: npx tsx scripts/recuperar-csc-por-caja.ts <xml-aprobado> (--csc <CSC> | --desde-bd) [--typo]"
    );
    process.exit(1);
  }

  const xml = await leerXml(ruta);
  const url = desescaparXml(/<dCarQR>([\s\S]*?)<\/dCarQR>/i.exec(xml)?.[1]?.trim() ?? "");
  if (!url) throw new Error("El XML no tiene <dCarQR>.");
  const query = url.slice(url.indexOf("?") + 1);
  const corte = query.lastIndexOf("&cHashQR=");
  if (corte < 0) throw new Error("La URL del QR no contiene &cHashQR=");
  const params = query.slice(0, corte);
  const objetivo = query.slice(corte + "&cHashQR=".length);

  let csc = cscArg?.trim() ?? "";
  if (!csc) {
    const ruc = /<dRucEm>([^<]+)<\/dRucEm>/.exec(xml)?.[1]?.trim();
    if (!ruc) throw new Error("No se pudo leer <dRucEm> del XML.");
    csc = (await cscDesdeBd(ruc))[0] ?? "";
    if (!csc) throw new Error(`No hay CSC configurado para el RUC ${ruc}.`);
  }

  const cadenas = cadenasPorIdCsc(params);
  console.log(`Documento de referencia: ${/Id=(\d{44})/.exec(params)?.[1] ?? "(sin CDC)"}`);
  console.log(`cHashQR objetivo       : ${objetivo}`);
  console.log(`CSC base               : ${csc.slice(0, 4)}…(${csc.length} car.)`);
  console.log();

  // Paso 1: solo la caja de las letras.
  let probadas = 0;
  for (const variante of variantesDeCaja(csc)) {
    for (const { idCsc, cadena } of cadenas) {
      probadas++;
      if (sha256(cadena + variante) === objetivo) {
        console.log(`ENCONTRADO (variación de caja, ${probadas} pruebas)`);
        console.log(`  CSC   : ${variante}`);
        console.log(`  IdCSC : ${idCsc}`);
        console.log(`  ${variante === csc ? "Es el CSC ya cargado." : "DISTINTO del cargado: reemplazalo por este."}`);
        return;
      }
    }
  }
  console.log(`Sin coincidencia probando solo la caja (${probadas} combinaciones).`);

  if (!conTypo) {
    console.log("Volvé a correr con --typo para probar además un carácter equivocado.");
    return;
  }

  // Paso 2: la caja, más un único carácter hexadecimal distinto.
  console.log("Probando además un carácter distinto (puede tardar)...");
  for (let i = 0; i < csc.length; i++) {
    for (const ch of HEX) {
      if (ch.toLowerCase() === csc[i]!.toLowerCase()) continue;
      const mutado = csc.slice(0, i) + ch + csc.slice(i + 1);
      for (const variante of variantesDeCaja(mutado)) {
        for (const { idCsc, cadena } of cadenas) {
          if (sha256(cadena + variante) === objetivo) {
            console.log(`ENCONTRADO (carácter ${i + 1} distinto)`);
            console.log(`  CSC   : ${variante}`);
            console.log(`  IdCSC : ${idCsc}`);
            return;
          }
        }
      }
    }
  }
  console.log(
    "Sin coincidencia. El CSC cargado difiere del correcto en más de un carácter:\n" +
      "hay que conseguirlo del SET (Marangatu)."
  );
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
