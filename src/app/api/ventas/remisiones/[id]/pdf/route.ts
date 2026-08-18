import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { membreteA4 } from "@/lib/documentos/membrete";
import { getRemisionVentaParaEdicion } from "@/lib/ventas/server/remisiones-venta-pg";

function esc(v: unknown): string {
  return String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}

const ESTADO_LABEL: Record<string, string> = { confirmada: "Confirmada", anulada: "Anulada", borrador: "Borrador" };

/**
 * GET /api/ventas/remisiones/[id]/pdf?auto=1
 *
 * Nota de remisión de una VENTA. Imprime SOLO lo entregado en esta remisión, y
 * deja constancia de lo que queda pendiente para que el cliente lo firme.
 */
export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const data = await getRemisionVentaParaEdicion(schema, ctx.auth.empresa_id, id);
    if (!data) return new NextResponse("Remisión no encontrada", { status: 404 });

    const r = data.remision;
    const entregadas = data.lineas.filter((l) => l.en_esta_remision > 0);
    const pendientes = data.lineas.filter((l) => l.pendiente > 0);

    const fmt = (n: number) => Number(n).toLocaleString("es-PY", { maximumFractionDigits: 3 });

    const filas = entregadas
      .map(
        (l) => `<tr>
          <td class="r">${fmt(l.en_esta_remision)}</td>
          <td>${esc(l.producto_nombre)}${l.sku ? `<span class="sku"> · ${esc(l.sku)}</span>` : ""}</td>
          <td class="r">${fmt(l.cantidad_vendida)}</td>
          <td>${esc(l.observacion ?? "")}</td>
        </tr>`,
      )
      .join("");

    const filasPend = pendientes
      .map((l) => `<tr><td class="r">${fmt(l.pendiente)}</td><td>${esc(l.producto_nombre)}</td></tr>`)
      .join("");

    const html = `<!doctype html><html lang="es"><head><meta charset="utf-8" />
<title>Nota de remisión ${esc(r.numero)}</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; color:#1f2937; margin:0; padding:28px; font-size:13px; }
  .titulo { text-align:center; font-size:18px; font-weight:700; letter-spacing:.05em; margin:14px 0 4px; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:6px 24px; margin-top:14px; }
  table { width:100%; border-collapse:collapse; margin-top:16px; }
  th, td { padding:7px 8px; border-bottom:1px solid #e5e7eb; text-align:left; vertical-align:top; }
  th { background:#f8fafc; font-size:11px; text-transform:uppercase; color:#6b7280; }
  .r { text-align:right; }
  .sku { color:#9ca3af; font-size:11px; }
  .badge { display:inline-block; border-radius:999px; padding:2px 10px; font-size:11px; font-weight:600; background:#eef2ff; color:#4338ca; }
  .anulada { background:#fef2f2; color:#b91c1c; }
  .pend { margin-top:18px; border:1px solid #fcd34d; background:#fffbeb; border-radius:8px; padding:10px 12px; }
  .pend h4 { margin:0 0 6px; font-size:12px; text-transform:uppercase; color:#92400e; }
  .pend table { margin-top:4px; }
  .pend th, .pend td { border-bottom:1px solid #fde68a; }
  .firmas { display:flex; justify-content:space-between; gap:40px; margin-top:60px; }
  .firma { flex:1; text-align:center; }
  .firma .linea { border-top:1px solid #374151; margin-top:40px; padding-top:6px; font-size:12px; }
  .obs { margin-top:12px; color:#6b7280; font-size:12px; }
  .actions { text-align:center; margin-top:24px; }
  @media print { body { padding:0; } .actions { display:none; } }
</style></head><body>
  ${membreteA4()}
  <div class="titulo">NOTA DE REMISIÓN</div>
  <div style="text-align:center"><span class="badge ${r.estado === "anulada" ? "anulada" : ""}">${esc(ESTADO_LABEL[r.estado] ?? r.estado)}</span></div>

  <div class="grid">
    <div><b>N°:</b> ${esc(r.numero)}</div>
    <div><b>Fecha:</b> ${(() => { try { return new Date(String(r.fecha)).toLocaleString("es-PY"); } catch { return esc(r.fecha); } })()}</div>
    <div><b>Venta:</b> ${esc(r.numero_control)}</div>
    <div><b>Cliente:</b> ${esc(r.cliente_nombre ?? "—")}</div>
    ${r.numero_orden_compra ? `<div><b>N.º Orden de Compra:</b> ${esc(r.numero_orden_compra)}</div>` : ""}
    <div><b>Entregado por:</b> ${esc(r.usuario_creador_nombre ?? "—")}</div>
  </div>

  <table>
    <thead><tr><th class="r">Entregado</th><th>Producto</th><th class="r">Vendido</th><th>Observación</th></tr></thead>
    <tbody>${filas || `<tr><td colspan="4">Sin ítems entregados</td></tr>`}</tbody>
  </table>

  ${
    filasPend
      ? `<div class="pend">
          <h4>Pendiente de entrega</h4>
          <table><thead><tr><th class="r">Cantidad</th><th>Producto</th></tr></thead><tbody>${filasPend}</tbody></table>
        </div>`
      : ""
  }

  ${r.observacion ? `<div class="obs"><b>Observaciones:</b> ${esc(r.observacion)}</div>` : ""}
  ${r.estado === "anulada" && r.anulada_motivo ? `<div class="obs"><b>Motivo de anulación:</b> ${esc(r.anulada_motivo)}</div>` : ""}

  <div class="firmas">
    <div class="firma"><div class="linea">Entregado por</div></div>
    <div class="firma"><div class="linea">Recibido por</div></div>
  </div>

  <div class="actions"><button type="button" onclick="window.print()">🖨 Imprimir</button></div>
  <script>if (new URL(location.href).searchParams.get('auto')) setTimeout(function(){window.print();}, 300);</script>
</body></html>`;

    return new NextResponse(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (err) {
    console.error("[/api/ventas/remisiones/[id]/pdf]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo generar el documento."), { status: 500 });
  }
}
