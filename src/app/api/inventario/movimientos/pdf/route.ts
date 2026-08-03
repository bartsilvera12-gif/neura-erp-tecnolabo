import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { applyTokenSearch } from "@/lib/productos/token-search";

const COLUMNAS: Record<string, { label: string; align?: "r" }> = {
  fecha: { label: "Fecha" },
  producto_nombre: { label: "Producto" },
  producto_sku: { label: "SKU" },
  tipo: { label: "Tipo" },
  cantidad: { label: "Cantidad", align: "r" },
  costo_unitario: { label: "Costo unit.", align: "r" },
  origen: { label: "Origen" },
  referencia: { label: "Documento" },
  documento_tipo: { label: "Tipo doc." },
  observacion: { label: "Observación" },
  usuario_nombre: { label: "Usuario" },
};
const DEFAULT_COLS = ["fecha", "producto_nombre", "tipo", "cantidad", "origen", "referencia"];

function esc(v: unknown): string {
  return String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}
function cell(col: string, row: Record<string, unknown>): string {
  if (col === "fecha") {
    try {
      return new Date(String(row.fecha)).toLocaleString("es-PY", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
    } catch {
      return esc(row.fecha);
    }
  }
  if (col === "cantidad" || col === "costo_unitario") return Number(row[col] ?? 0).toLocaleString("es-PY", { maximumFractionDigits: 3 });
  return esc(row[col]);
}

/** GET /api/inventario/movimientos/pdf — export imprimible respetando filtros + columnas. */
export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const empresaId = ctx.auth.empresa_id;
    const url = new URL(request.url);

    const cols = (url.searchParams.get("columns") ?? "").split(",").map((c) => c.trim()).filter((c) => COLUMNAS[c]);
    const columnas = cols.length ? cols : DEFAULT_COLS;

    const q = (url.searchParams.get("q") ?? "").trim();
    const tipo = (url.searchParams.get("tipo") ?? "").trim();
    const origen = (url.searchParams.get("origen") ?? "").trim();
    const depositoId = (url.searchParams.get("deposito_id") ?? "").trim();
    const documentoTipo = (url.searchParams.get("documento_tipo") ?? "").trim();
    const productoId = (url.searchParams.get("producto_id") ?? "").trim();
    const fechaDesde = (url.searchParams.get("fecha_desde") ?? "").trim();
    const fechaHasta = (url.searchParams.get("fecha_hasta") ?? "").trim();

    let query = ctx.supabase
      .from("movimientos_inventario")
      .select(
        "producto_nombre, producto_sku, tipo, cantidad, costo_unitario, origen, referencia, documento_tipo, observacion, fecha, usuario_nombre",
      )
      .eq("empresa_id", empresaId);
    if (tipo) query = query.eq("tipo", tipo);
    if (origen) query = query.eq("origen", origen);
    if (depositoId) query = query.eq("deposito_id", depositoId);
    if (documentoTipo) query = query.eq("documento_tipo", documentoTipo);
    if (productoId) query = query.eq("producto_id", productoId);
    if (q) query = applyTokenSearch(query, q, ["producto_nombre", "producto_sku"]);
    if (fechaDesde) query = query.gte("fecha", `${fechaDesde}T00:00:00`);
    if (fechaHasta) query = query.lte("fecha", `${fechaHasta}T23:59:59.999`);
    query = query.order("fecha", { ascending: false }).limit(2000);

    const { data, error } = await query;
    if (error) throw new Error(error.message);
    const rows = (data ?? []) as Record<string, unknown>[];

    let negocio = "Empresa";
    try {
      const eq = await ctx.supabase.from("empresas").select("nombre_empresa").eq("id", empresaId).maybeSingle();
      negocio = (eq.data as { nombre_empresa?: string } | null)?.nombre_empresa ?? "Empresa";
    } catch {
      /* fallback */
    }

    const thead = columnas.map((c) => `<th class="${COLUMNAS[c].align === "r" ? "r" : ""}">${esc(COLUMNAS[c].label)}</th>`).join("");
    const tbody = rows
      .map((row) => `<tr>${columnas.map((c) => `<td class="${COLUMNAS[c].align === "r" ? "r" : ""}">${cell(c, row)}</td>`).join("")}</tr>`)
      .join("");

    const html = `<!doctype html><html lang="es"><head><meta charset="utf-8" />
<title>Movimientos de inventario</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; color: #1f2937; margin: 0; padding: 24px; font-size: 12px; }
  .head { display: flex; justify-content: space-between; border-bottom: 3px solid #4FAEB2; padding-bottom: 10px; margin-bottom: 12px; }
  h1 { font-size: 18px; margin: 0; }
  .muted { color: #6b7280; font-size: 11px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 5px 7px; border-bottom: 1px solid #e5e7eb; text-align: left; }
  th { background: #f8fafc; font-size: 10px; text-transform: uppercase; color: #6b7280; }
  .r { text-align: right; }
  @media print { body { padding: 0; } }
</style></head><body>
  <div class="head">
    <div><div style="font-size:15px;font-weight:700;color:#4FAEB2">${esc(negocio)}</div><div class="muted">Movimientos de inventario</div></div>
    <div class="muted" style="text-align:right">${rows.length} movimiento(s)${rows.length >= 2000 ? " (máx. 2000)" : ""}</div>
  </div>
  <table><thead><tr>${thead}</tr></thead><tbody>${tbody || `<tr><td colspan="${columnas.length}">Sin movimientos</td></tr>`}</tbody></table>
  <script>if (new URL(location.href).searchParams.get('auto')) setTimeout(() => window.print(), 300);</script>
</body></html>`;
    return new NextResponse(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (err) {
    console.error("[/api/inventario/movimientos/pdf]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo generar el PDF."), { status: 500 });
  }
}
