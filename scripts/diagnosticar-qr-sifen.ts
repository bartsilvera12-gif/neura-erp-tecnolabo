/**
 * Diagnostica el rechazo del SET «El hash del código QR incluido el de la cadena
 * de caracteres es inválido» sobre un XML ya firmado.
 *
 * El SET valida el QR así: toma la cadena de la URL desde `nVersion=` hasta
 * `IdCSC=xxxx`, le concatena el CSC que tiene registrado para ESE IdCSC y ese
 * timbrado, calcula SHA-256 y lo compara con el `cHashQR` de la URL. Por eso el
 * rechazo casi siempre significa una de estas tres cosas:
 *
 *   1. El CSC cargado no es el que el SET tiene registrado (typo, recortado,
 *      copiado con espacios, o todavía el CSC de pruebas en producción).
 *   2. El CSC cargado es el CSC2 pero se envía `IdCSC=0001` (o al revés).
 *   3. El QR se generó con datos distintos a los del XML que se envió
 *      (por ejemplo un `DigestValue` viejo tras regenerar el documento).
 *
 * Uso:
 *   npm run sifen:diagnosticar-qr -- <archivo.xml | ruta-en-bucket> [CSC ...]
 *
 * El primer argumento puede ser un archivo local o directamente el
 * `factura_electronica.xml_firmado_path` (p. ej.
 * `{empresa_id}/{factura_id}/documento-firmado.xml`): en ese caso se descarga
 * del bucket `sifen` usando NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
 * de .env.local.
 *
 * Sin CSC candidatos solo verifica la coherencia interna del QR (punto 3).
 * Con uno o varios CSC prueba cada combinación CSC × IdCSC (0001/0002) y dice
 * cuál reproduce el `cHashQR` que está dentro del XML. Los CSC NO se imprimen
 * completos (solo los primeros 4 caracteres y la longitud).
 */
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { config } from "dotenv";
import { createClient } from "@supabase/supabase-js";
import { buildSifenDcarQrParts } from "@/lib/sifen/sifen-dcar-qr";

config({ path: resolve(process.cwd(), ".env.local") });

const SIFEN_BUCKET = "sifen";

const ID_CSC_CANDIDATOS = ["0001", "0002"] as const;

/** La URL del QR va escapada dentro de `<dCarQR>`; hay que deshacer ese escape. */
function desescaparXml(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n: string) => String.fromCharCode(parseInt(n, 10)))
    .replace(/&amp;/g, "&");
}

/**
 * Devuelve el XML: archivo local si existe, si no lo baja del bucket `sifen`
 * tratando el argumento como `xml_firmado_path`.
 */
async function leerXml(arg: string): Promise<string> {
  const local = resolve(process.cwd(), arg);
  if (existsSync(local)) return readFileSync(local, "utf8");

  const sbUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const sbKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!sbUrl || !sbKey) {
    throw new Error(
      `No existe el archivo "${arg}" y falta NEXT_PUBLIC_SUPABASE_URL / ` +
        "SUPABASE_SERVICE_ROLE_KEY en .env.local para bajarlo del bucket."
    );
  }
  const objectPath = arg.replace(/^sifen\//, "");
  console.log(`Descargando ${SIFEN_BUCKET}/${objectPath} ...`);
  const storage = createClient(sbUrl, sbKey);
  const { data, error } = await storage.storage.from(SIFEN_BUCKET).download(objectPath);
  if (error || !data) {
    throw new Error(`No se pudo descargar del bucket: ${error?.message ?? "objeto no encontrado"}`);
  }
  return Buffer.from(await data.arrayBuffer()).toString("utf8");
}

function leerDCarQr(xml: string): string {
  const m = /<dCarQR>([\s\S]*?)<\/dCarQR>/i.exec(xml);
  if (!m?.[1]) {
    throw new Error("El XML no tiene <dCarQR> (¿no fue firmado todavía?)");
  }
  return desescaparXml(m[1].trim());
}

function partirQr(url: string): { params: string; cHashQR: string } {
  const i = url.indexOf("?");
  const query = i >= 0 ? url.slice(i + 1) : url;
  const j = query.lastIndexOf("&cHashQR=");
  if (j < 0) throw new Error("La URL del QR no contiene &cHashQR=");
  return { params: query.slice(0, j), cHashQR: query.slice(j + "&cHashQR=".length) };
}

function sha256(s: string): string {
  return createHash("sha256").update(s, "utf8").digest("hex");
}

async function main(): Promise<void> {
  const [rutaArg, ...cscs] = process.argv.slice(2);
  if (!rutaArg) {
    console.error("Uso: npm run sifen:diagnosticar-qr -- <ruta-xml-firmado> [CSC ...]");
    process.exit(1);
  }

  const xml = await leerXml(rutaArg);
  const enXml = partirQr(leerDCarQr(xml));
  const ambiente = enXml.params.includes("consultas-test") ? "test" : "produccion";

  console.log("== QR presente en el XML ==");
  console.log("cadena  :", enXml.params);
  console.log("cHashQR :", enXml.cHashQR);
  console.log("IdCSC   :", /IdCSC=(\d{4})/.exec(enXml.params)?.[1] ?? "(ausente)");
  console.log();

  // Punto 3: ¿la cadena del QR corresponde a los datos del XML firmado?
  // Se reconstruye con un CSC ficticio: solo interesa comparar la cadena, no el hash.
  const reconstruido = buildSifenDcarQrParts(xml, {
    ambiente: ambiente === "test" ? "test" : "produccion",
    csc: "x",
    idCsc: /IdCSC=(\d{4})/.exec(enXml.params)?.[1],
  });
  if (reconstruido.params === enXml.params) {
    console.log("OK: la cadena del QR coincide con los datos del XML firmado.");
  } else {
    console.log("PROBLEMA: la cadena del QR NO coincide con los datos del XML firmado.");
    console.log("esperada:", reconstruido.params);
    console.log("→ Regenerá y volvé a firmar el documento (el QR quedó de una versión anterior).");
  }
  console.log();

  if (cscs.length === 0) {
    console.log("Pasá uno o más CSC como argumentos para probar cuál reproduce el cHashQR.");
    return;
  }

  console.log("== Prueba de CSC × IdCSC ==");
  let algunaCoincidencia = false;
  for (const cscRaw of cscs) {
    const csc = cscRaw.trim();
    if (csc !== cscRaw) {
      console.log(`aviso: el CSC "${cscRaw}" tenía espacios alrededor (se usa recortado).`);
    }
    for (const idCsc of ID_CSC_CANDIDATOS) {
      const params = enXml.params.replace(/IdCSC=\d{4}/, `IdCSC=${idCsc}`);
      const hash = sha256(params + csc);
      const ok = hash === enXml.cHashQR;
      if (ok) algunaCoincidencia = true;
      console.log(
        `${ok ? "COINCIDE " : "no coincide"}  CSC=${csc.slice(0, 4)}…(${csc.length} car.)  IdCSC=${idCsc}`
      );
    }
  }
  console.log();
  if (algunaCoincidencia) {
    console.log(
      "El par marcado COINCIDE es el que hay que dejar en Configuración → Facturación electrónica\n" +
        "(campos CSC e ID del CSC). Si el SET igual rechaza, ese CSC no es el que el SET\n" +
        "tiene registrado para el timbrado: pedí/regenerá el CSC en Marangatu."
    );
  } else {
    console.log(
      "Ningún CSC probado reproduce el cHashQR del XML: el documento se firmó con otro CSC.\n" +
        "Cargá el CSC correcto y volvé a generar, firmar y enviar el documento."
    );
  }
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
