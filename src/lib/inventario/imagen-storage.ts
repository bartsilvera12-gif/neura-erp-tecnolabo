/**
 * Storage helpers para imagenes de producto.
 *
 * Bucket: `productos-imagenes` (privado).
 * Path:   `{empresa_id}/{producto_id}/principal.{ext}`
 *
 * Aislamiento por tenant: el primer segmento del path es `empresa_id` y los
 * endpoints siempre validan el `empresa_id` del usuario antes de leer/escribir.
 */
import type { AppSupabaseClient } from "@/lib/supabase/schema";

export const PRODUCTOS_IMAGENES_BUCKET = "productos-imagenes";

export const ALLOWED_IMAGE_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
export const ALLOWED_IMAGE_EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // 5 MB

let bucketEnsured = false;

/**
 * Crea el bucket privado si no existe. Idempotente. Cachea el flag en memoria
 * del proceso para no llamar listBuckets en cada request.
 *
 * Requiere un cliente con service role (puede ser el del tenant ya que las
 * operaciones de storage usan la misma key).
 */
export async function ensureProductosImagenesBucket(supabase: AppSupabaseClient): Promise<void> {
  if (bucketEnsured) return;
  try {
    const { data: existing } = await supabase.storage.getBucket(PRODUCTOS_IMAGENES_BUCKET);
    if (existing) {
      bucketEnsured = true;
      return;
    }
  } catch {
    // fallthrough — intentar crear
  }
  const { error: createErr } = await supabase.storage.createBucket(PRODUCTOS_IMAGENES_BUCKET, {
    public: false,
    fileSizeLimit: MAX_IMAGE_BYTES,
    allowedMimeTypes: ["image/jpeg", "image/png", "image/webp"],
  });
  if (createErr && !/already exists|duplicate/i.test(createErr.message)) {
    throw new Error(`No se pudo crear el bucket: ${createErr.message}`);
  }
  bucketEnsured = true;
}

export function buildProductoImagenPath(empresaId: string, productoId: string, mime: string): string {
  const ext = ALLOWED_IMAGE_EXT[mime] ?? "bin";
  return `${empresaId}/${productoId}/principal.${ext}`;
}

/**
 * Genera URL firmada para visualizar la imagen. TTL por defecto 1h.
 * Devuelve null si el path es inválido o si falla.
 */
export async function signProductoImagen(
  supabase: AppSupabaseClient,
  imagenPath: string | null | undefined,
  ttlSeconds = 3600
): Promise<string | null> {
  if (!imagenPath) return null;
  try {
    const { data, error } = await supabase.storage
      .from(PRODUCTOS_IMAGENES_BUCKET)
      .createSignedUrl(imagenPath, ttlSeconds);
    if (error || !data?.signedUrl) return null;
    return data.signedUrl;
  } catch {
    return null;
  }
}

/**
 * Resuelve la URL pública de imagen para una lista de productos del sitio.
 *
 * El ERP guarda la imagen en `imagen_path` (bucket privado) y deja `imagen_url`
 * en null; la web lee `imagen_url`. Este helper firma en lote los `imagen_path`
 * pendientes y los devuelve en `imagen_url`, dejando el path fuera de la
 * respuesta. Si un producto ya trae `imagen_url`, se respeta.
 *
 * TTL largo (7 días) para que la URL firmada sobreviva al cache del CDN y a la
 * sesión del visitante.
 */
export async function resolverImagenesPublicas<
  T extends { imagen_url?: string | null; imagen_path?: string | null }
>(
  supabase: AppSupabaseClient,
  productos: T[],
  ttlSeconds = 60 * 60 * 24 * 7
): Promise<Array<Omit<T, "imagen_path">>> {
  const pendientes = Array.from(
    new Set(
      productos
        .filter((p) => !p.imagen_url && p.imagen_path)
        .map((p) => p.imagen_path as string)
    )
  );
  const firmadas = new Map<string, string>();
  if (pendientes.length > 0) {
    try {
      const { data } = await supabase.storage
        .from(PRODUCTOS_IMAGENES_BUCKET)
        .createSignedUrls(pendientes, ttlSeconds);
      pendientes.forEach((path, i) => {
        const url = data?.[i]?.signedUrl;
        if (url) firmadas.set(path, url);
      });
    } catch {
      // Sin firma: los productos afectados caen al placeholder del sitio.
    }
  }
  return productos.map(({ imagen_path, ...rest }) => ({
    ...rest,
    imagen_url:
      rest.imagen_url ?? (imagen_path ? firmadas.get(imagen_path) ?? null : null),
  }));
}

/**
 * Resuelve la imagen visible de una lista de ítems que referencian productos
 * (presupuestos, pedidos, etc.). Para cada ítem, en orden de preferencia:
 *   1. `imagen_url` directa (p. ej. URL externa) → se respeta.
 *   2. `imagen_path` propio del ítem → se firma (bucket privado).
 *   3. `producto_id` → se toma el `imagen_path` del producto y se firma
 *      (cubre ítems creados antes de heredar la imagen).
 * Muta cada ítem seteando `imagen_url` con la URL firmada efímera. Silencioso
 * ante fallos: un ítem sin imagen simplemente queda sin `imagen_url`.
 */
export async function firmarImagenesItems(
  supabase: AppSupabaseClient,
  empresaId: string,
  items: Array<Record<string, unknown>>,
  ttlSeconds = 3600
): Promise<void> {
  try {
    const pathPorProducto = new Map<string, string>();
    const sinResolver = items.filter((it) => !it.imagen_url && !it.imagen_path && it.producto_id);
    const prodIds = Array.from(new Set(sinResolver.map((it) => String(it.producto_id))));
    if (prodIds.length > 0) {
      const pr = await supabase
        .from("productos")
        .select("id, imagen_path")
        .eq("empresa_id", empresaId)
        .in("id", prodIds);
      for (const row of (pr.data ?? []) as Array<{ id: string; imagen_path: string | null }>) {
        if (row.imagen_path) pathPorProducto.set(String(row.id), row.imagen_path);
      }
    }
    await Promise.all(
      items.map(async (it) => {
        if (it.imagen_url) return;
        const path =
          (it.imagen_path as string | null) ||
          (it.producto_id ? pathPorProducto.get(String(it.producto_id)) ?? null : null);
        if (path) {
          it.imagen_url = (await signProductoImagen(supabase, String(path), ttlSeconds)) ?? null;
        }
      })
    );
  } catch {
    // Sin imágenes firmadas los ítems salen igual, solo sin foto.
  }
}

/**
 * Valida que el path pertenezca a la empresa indicada (primer segmento).
 * Previene cross-tenant en operaciones que reciben paths arbitrarios.
 */
export function pathBelongsToEmpresa(path: string | null | undefined, empresaId: string): boolean {
  if (!path) return false;
  const seg = path.split("/")[0];
  return seg === empresaId;
}
