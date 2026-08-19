/**
 * Logo del cliente embebido como data URI para los documentos imprimibles.
 *
 * Por qué embeber en vez de referenciar la URL:
 *  - Detrás del proxy, `new URL(request.url).origin` en un route handler devuelve
 *    la URL INTERNA del contenedor, así que un `<img src="{origin}/logo.jpeg">`
 *    apunta a un host que el navegador no resuelve y el logo no aparece.
 *  - Al imprimir, algunos navegadores no esperan a que carguen imágenes remotas.
 *  - El documento queda autocontenido si se guarda como PDF o se envía por mail.
 *
 * El archivo se lee una sola vez y queda en memoria (pesa ~52 KB).
 */
import fs from "node:fs";
import path from "node:path";
import { CLIENTE_LOGO_URL } from "@/lib/branding/cliente";

let cache: string | null | undefined;

function mimePorExtension(rel: string): string {
  if (/\.png$/i.test(rel)) return "image/png";
  if (/\.svg$/i.test(rel)) return "image/svg+xml";
  if (/\.webp$/i.test(rel)) return "image/webp";
  return "image/jpeg";
}

/**
 * Devuelve el `src` a usar en el `<img>` del membrete: data URI si se pudo leer
 * el archivo, y si no la ruta relativa (que igual funciona servida desde la
 * misma app). `null` si el cliente no tiene logo configurado.
 */
export function logoClienteSrc(): string | null {
  if (cache !== undefined) return cache;

  const rel = String(CLIENTE_LOGO_URL ?? "").trim();
  if (!rel) {
    cache = null;
    return cache;
  }

  const limpio = rel.replace(/^\/+/, "");
  try {
    const p = path.join(process.cwd(), "public", limpio);
    if (fs.existsSync(p)) {
      const bytes = fs.readFileSync(p);
      cache = `data:${mimePorExtension(limpio)};base64,${bytes.toString("base64")}`;
      return cache;
    }
  } catch {
    /* se cae a la ruta relativa */
  }

  cache = rel.startsWith("/") ? rel : `/${limpio}`;
  return cache;
}
