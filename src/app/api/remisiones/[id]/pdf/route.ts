import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { getRemision } from "@/lib/ventas/server/remisiones-pg";

function esc(v: unknown): string {
  return String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}
const ESTADO_LABEL: Record<string, string> = { borrador: "Borrador", confirmada: "Confirmada", anulada: "Anulada" };

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const data = await getRemision(schema, ctx.auth.empresa_id, id);
    if (!data) return NextResponse.json(errorResponse("Remisión no encontrada."), { status: 404 });

    let negocio = "Empresa";
    try {
      const eq = await ctx.supabase.from("empresas").select("nombre_empresa").eq("id", ctx.auth.empresa_id).maybeSingle();
      negocio = (eq.data as { nombre_empresa?: string } | null)?.nombre_empresa ?? "Empresa";
    } catch { /* fallback */ }

    const r = data.remision as Record<string, unknown>;
    const items = data.items as Record<string, unknown>[];
    const filas = items
      .map((it) => `<tr><td>${esc(it.producto_nombre)}${it.sku ? `<span class="sku"> · ${esc(it.sku)}</span>` : ""}</td><td class="r">${Number(it.cantidad).toLocaleString("es-PY", { maximumFractionDigits: 3 })}</td><td>${esc(it.observacion ?? "")}</td></tr>`)
      .join("");

    const html = `<!doctype html><html lang="es"><head><meta charset="utf-8" />
<title>Nota de remisión ${esc(r.numero)}</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; color: #1f2937; margin: 0; padding: 28px; font-size: 13px; }
  .head { display: flex; justify-content: space-between; border-bottom: 3px solid #4FAEB2; padding-bottom: 12px; }
  h1 { font-size: 20px; margin: 0; }
  .muted { color: #6b7280; font-size: 12px; }
  .badge { display: inline-block; border-radius: 999px; padding: 2px 10px; font-size: 11px; font-weight: 600; background: #eef2ff; color: #4338ca; }
  table { width: 100%; border-collapse: collapse; margin-top: 16px; }
  th, td { padding: 7px 8px; border-bottom: 1px solid #e5e7eb; text-align: left; vertical-align: top; }
  th { background: #f8fafc; font-size: 11px; text-transform: uppercase; color: #6b7280; }
  .r { text-align: right; }
  .sku { color: #9ca3af; font-size: 11px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 24px; margin-top: 14px; }
  .firmas { display: flex; justify-content: space-between; gap: 40px; margin-top: 60px; }
  .firma { flex: 1; text-align: center; }
  .firma .linea { border-top: 1px solid #374151; margin-top: 40px; padding-top: 6px; font-size: 12px; }
  @media print { body { padding: 0; } }
</style></head><body>
  <div class="head">
    <div><div style="font-size:16px;font-weight:700;color:#4FAEB2">${esc(negocio)}</div><div class="muted">Nota de remisión (entrega de mercadería)</div></div>
    <div style="text-align:right"><h1>Nota de remisión</h1><div class="muted">${esc(r.numero)}</div><div style="margin-top:4px"><span class="badge">${esc(ESTADO_LABEL[String(r.estado)] ?? r.estado)}</span></div></div>
  </div>
  <div class="grid">
    <div><b>Factura:</b> ${esc(data.numero_factura ?? "—")}</div>
    <div><b>Fecha:</b> ${(() => { try { return new Date(String(r.fecha)).toLocaleString("es-PY"); } catch { return esc(r.fecha); } })()}</div>
    <div><b>Cliente:</b> ${esc(r.cliente_nombre ?? "—")}</div>
    <div><b>Entrega:</b> ${esc(r.usuario_confirmador_nombre ?? r.usuario_creador_nombre ?? "—")}</div>
  </div>
  <table><thead><tr><th>Producto</th><th class="r">Cantidad</th><th>Observación</th></tr></thead><tbody>${filas || `<tr><td colspan="3">Sin ítems</td></tr>`}</tbody></table>
  ${r.observacion ? `<div class="muted" style="margin-top:12px"><b>Observaciones:</b> ${esc(r.observacion)}</div>` : ""}
  <div class="firmas"><div class="firma"><div class="linea">Entregado por</div></div><div class="firma"><div class="linea">Recibido por</div></div></div>
  <script>if (new URL(location.href).searchParams.get('auto')) setTimeout(() => window.print(), 300);</script>
</body></html>`;
    return new NextResponse(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (err) {
    console.error("[/api/remisiones/[id]/pdf]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo generar el documento."), { status: 500 });
  }
}
