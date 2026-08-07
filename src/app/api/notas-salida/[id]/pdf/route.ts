import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { getNotaSalida } from "@/lib/inventario/server/notas-salida-pg";

function esc(v: unknown): string {
  return String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}
const MOTIVO_LABEL: Record<string, string> = {
  uso_interno: "Uso interno", muestra: "Muestra", prestamo: "Préstamo", daño: "Daño",
  perdida: "Pérdida", consumo: "Consumo", ajuste: "Ajuste", otro: "Otro",
};
const ESTADO_LABEL: Record<string, string> = { borrador: "Borrador", confirmada: "Confirmada", anulada: "Anulada" };

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const data = await getNotaSalida(schema, ctx.auth.empresa_id, id);
    if (!data) return NextResponse.json(errorResponse("Nota de salida no encontrada."), { status: 404 });

    let negocio = "Empresa";
    try {
      const eq = await ctx.supabase.from("empresas").select("nombre_empresa").eq("id", ctx.auth.empresa_id).maybeSingle();
      negocio = (eq.data as { nombre_empresa?: string } | null)?.nombre_empresa ?? "Empresa";
    } catch { /* fallback */ }

    const n = data.nota as Record<string, unknown>;
    const items = data.items as Record<string, unknown>[];
    const filas = items
      .map((it) => `<tr><td>${esc(it.producto_nombre)}${it.sku ? `<span class="sku"> · ${esc(it.sku)}</span>` : ""}</td><td class="r">${Number(it.cantidad).toLocaleString("es-PY", { maximumFractionDigits: 3 })}</td><td>${esc(it.observacion ?? "")}</td></tr>`)
      .join("");

    const html = `<!doctype html><html lang="es"><head><meta charset="utf-8" />
<title>Nota de salida ${esc(n.numero)}</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; color: #1f2937; margin: 0; padding: 28px; font-size: 13px; }
  .head { display: flex; justify-content: space-between; border-bottom: 3px solid #1E2125; padding-bottom: 12px; }
  h1 { font-size: 20px; margin: 0; }
  .muted { color: #6b7280; font-size: 12px; }
  .badge { display: inline-block; border-radius: 999px; padding: 2px 10px; font-size: 11px; font-weight: 600; background: #fef2f2; color: #b91c1c; }
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
    <div><div style="font-size:16px;font-weight:700;color:#1E2125">${esc(negocio)}</div><div class="muted">Nota de salida de inventario</div></div>
    <div style="text-align:right"><h1>Nota de salida</h1><div class="muted">${esc(n.numero)}</div><div style="margin-top:4px"><span class="badge">${esc(ESTADO_LABEL[String(n.estado)] ?? n.estado)}</span></div></div>
  </div>
  <div class="grid">
    <div><b>Motivo:</b> ${esc(MOTIVO_LABEL[String(n.motivo)] ?? n.motivo)}</div>
    <div><b>Fecha:</b> ${(() => { try { return new Date(String(n.fecha)).toLocaleString("es-PY"); } catch { return esc(n.fecha); } })()}</div>
    <div><b>Creada por:</b> ${esc(n.usuario_creador_nombre ?? "—")}</div>
    <div><b>Confirmada por:</b> ${esc(n.usuario_confirmador_nombre ?? "—")}</div>
  </div>
  <table><thead><tr><th>Producto</th><th class="r">Cantidad</th><th>Observación</th></tr></thead><tbody>${filas || `<tr><td colspan="3">Sin ítems</td></tr>`}</tbody></table>
  ${n.observacion ? `<div class="muted" style="margin-top:12px"><b>Observaciones:</b> ${esc(n.observacion)}</div>` : ""}
  <div class="firmas"><div class="firma"><div class="linea">Autoriza</div></div><div class="firma"><div class="linea">Recibe / Retira</div></div></div>
  <script>if (new URL(location.href).searchParams.get('auto')) setTimeout(() => window.print(), 300);</script>
</body></html>`;
    return new NextResponse(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (err) {
    console.error("[/api/notas-salida/[id]/pdf]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo generar el documento."), { status: 500 });
  }
}
