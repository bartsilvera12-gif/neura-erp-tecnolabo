import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { membreteA4 } from "@/lib/documentos/membrete";
import { signProductoImagen } from "@/lib/inventario/imagen-storage";

/**
 * GET /api/presupuestos/[id]/pdf?auto=1
 *
 * Documento comercial A4 imprimible (HTML). El navegador imprime / guarda como PDF.
 * NO fiscal, NO toca SIFEN, NO descuenta stock.
 *
 * Impresión: por defecto DOS copias idénticas del mismo presupuesto en una hoja A4
 * (superior + inferior) con una línea "✂ CORTAR AQUÍ ✂" en el centro. Si el contenido
 * no entra en media hoja (muchos productos), cae automáticamente a UNA copia en A4
 * completo con el detalle (imágenes + especificaciones). No se crean ni duplican
 * registros: la duplicación existe SOLO en la vista de impresión.
 */

import { CLIENTE_NOMBRE } from "@/lib/branding/cliente";

const NEGOCIO_FALLBACK = CLIENTE_NOMBRE;

function resolveNegocio(nombreEmpresa?: string | null): string {
  const env = (process.env.NEURA_CLIENT_NAME ?? "").trim();
  if (env) return env;
  const e = (nombreEmpresa ?? "").trim();
  if (e) return e;
  return NEGOCIO_FALLBACK;
}

function esc(v: unknown): string {
  return String(v ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function fmtMoneda(n: unknown, moneda: string): string {
  const v = Number(n) || 0;
  const simbolo = moneda === "USD" ? "USD " : "Gs. ";
  return simbolo + v.toLocaleString("es-PY", { maximumFractionDigits: moneda === "USD" ? 2 : 0 });
}

function fmtFecha(iso: unknown): string {
  if (!iso) return "—";
  try {
    return new Date(String(iso)).toLocaleDateString("es-PY", { day: "2-digit", month: "2-digit", year: "numeric" });
  } catch {
    return String(iso);
  }
}

const IVA_LABEL: Record<string, string> = { EXENTA: "Exenta", "5%": "5%", "10%": "10%" };

export async function GET(request: NextRequest, ctxParams: { params: Promise<{ id: string }> }) {
  const { id } = await ctxParams.params;
  const auto = new URL(request.url).searchParams.get("auto") === "1";

  const ctx = await getTenantSupabaseFromAuth(request);
  if (!ctx) {
    return new NextResponse("No autorizado", { status: 401 });
  }

  const pq = await ctx.supabase
    .from("presupuestos")
    .select("*")
    .eq("empresa_id", ctx.auth.empresa_id)
    .eq("id", id)
    .maybeSingle();
  if (pq.error || !pq.data) {
    return new NextResponse("Presupuesto no encontrado", { status: 404 });
  }
  const p = pq.data as Record<string, unknown>;

  const itq = await ctx.supabase
    .from("presupuesto_items")
    .select(
      "producto_id, producto_nombre, sku, cantidad, unidad_medida, precio_unitario, iva_tipo, descuento, total, imagen_url, imagen_path, descripcion_comercial, especificaciones_tecnicas, caracteristicas",
    )
    .eq("empresa_id", ctx.auth.empresa_id)
    .eq("presupuesto_id", id)
    .order("created_at", { ascending: true });
  const items = (itq.data ?? []) as Record<string, unknown>[];

  // Imágenes: el bucket es privado, así que se firma `imagen_path` -> URL efímera
  // solo para este render. Cada ítem trae su imagen_path (heredada del producto al
  // crearse); para presupuestos anteriores a esa herencia, se resuelve desde el
  // producto por producto_id. Si el ítem ya trae una URL directa (externa), se respeta.
  try {
    const sinResolver = items.filter((it) => !it.imagen_url && !it.imagen_path && it.producto_id);
    const pathPorProducto = new Map<string, string>();
    const prodIds = Array.from(new Set(sinResolver.map((it) => String(it.producto_id))));
    if (prodIds.length > 0) {
      const pr = await ctx.supabase
        .from("productos")
        .select("id, imagen_path")
        .eq("empresa_id", ctx.auth.empresa_id)
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
          it.imagen_url = (await signProductoImagen(ctx.supabase, String(path), 3600)) ?? null;
        }
      }),
    );
  } catch {
    // Sin imágenes firmadas el PDF sale igual, solo sin fotos.
  }

  // Nombre del negocio.
  let nombreEmpresa: string | null = null;
  try {
    const eq = await ctx.supabase
      .from("empresas")
      .select("nombre_empresa")
      .eq("id", ctx.auth.empresa_id)
      .maybeSingle();
    nombreEmpresa = (eq.data as { nombre_empresa?: string } | null)?.nombre_empresa ?? null;
  } catch {
    /* fallback al nombre por defecto */
  }
  const negocio = resolveNegocio(nombreEmpresa);
  const moneda = String(p.moneda ?? "PYG");

  // Fila de ítem. `full=true` incluye imagen + especificaciones + características
  // (versión detallada, hoja A4 completa). `full=false` es compacta (dos copias por hoja):
  // solo nombre + descripción comercial, sin imagen ni specs, para que entre en media A4.
  const rowHtml = (it: Record<string, unknown>, full: boolean): string => {
    const cant = Number(it.cantidad) || 0;
    const unidad = it.unidad_medida ? ` ${esc(it.unidad_medida)}` : "";
    const nombreHtml = `${esc(it.producto_nombre)}${it.sku ? `<span class="sku"> · ${esc(it.sku)}</span>` : ""}`;
    const descCom = it.descripcion_comercial ? `<div class="desc">${esc(it.descripcion_comercial)}</div>` : "";
    const imgUrl = it.imagen_url ? esc(String(it.imagen_url)) : "";
    let celda: string;
    if (full) {
      // Hoja completa: imagen grande + especificaciones + características.
      const img = imgUrl ? `<img class="itemimg" src="${imgUrl}" alt="" />` : "";
      const espec = it.especificaciones_tecnicas
        ? `<div class="espec"><b>Especificaciones:</b> ${esc(it.especificaciones_tecnicas)}</div>`
        : "";
      const caracArr = Array.isArray(it.caracteristicas)
        ? (it.caracteristicas as Array<{ label?: string; valor?: string }>)
        : [];
      const carac = caracArr.length
        ? `<ul class="carac">${caracArr
            .map((c) => `<li>${esc(c.label ?? "")}${c.label && c.valor ? ": " : ""}${esc(c.valor ?? "")}</li>`)
            .join("")}</ul>`
        : "";
      const detalle =
        descCom || espec || carac || img
          ? `<div class="itemdetalle">${img}<div class="itemtxt">${descCom}${espec}${carac}</div></div>`
          : "";
      celda = `${nombreHtml}${detalle}`;
    } else {
      // Copia compacta (2 por hoja): miniatura de la imagen al lado del nombre.
      const thumb = imgUrl ? `<img class="thumb" src="${imgUrl}" alt="" />` : "";
      celda = thumb
        ? `<div class="itemc">${thumb}<div>${nombreHtml}${descCom}</div></div>`
        : `${nombreHtml}${descCom}`;
    }
    return `
      <tr>
        <td class="c">${cant.toLocaleString("es-PY", { maximumFractionDigits: 3 })}${unidad}</td>
        <td>${celda}</td>
        <td class="r">${fmtMoneda(it.precio_unitario, moneda)}</td>
        <td class="c">${esc(IVA_LABEL[String(it.iva_tipo)] ?? it.iva_tipo)}</td>
        <td class="r">${Number(it.descuento) > 0 ? fmtMoneda(it.descuento, moneda) : "—"}</td>
        <td class="r">${fmtMoneda(it.total, moneda)}</td>
      </tr>`;
  };
  const filasCompact = items.map((it) => rowHtml(it, false)).join("");
  const filasFull = items.map((it) => rowHtml(it, true)).join("");

  const condiciones: string[] = [];
  if (p.validez_dias) condiciones.push(`Validez: ${esc(p.validez_dias)} día(s)${p.fecha_vencimiento ? ` (vence ${fmtFecha(p.fecha_vencimiento)})` : ""}`);
  if (p.forma_pago) condiciones.push(`Forma de pago: ${esc(p.forma_pago)}`);
  if (p.plazo_entrega) condiciones.push(`Plazo de entrega: ${esc(p.plazo_entrega)}`);
  if (Number(p.tipo_cambio) > 1) condiciones.push(`Tipo de cambio: ${esc(p.tipo_cambio)}`);
  if (p.condiciones_comerciales) condiciones.push(esc(p.condiciones_comerciales));

  // Componente reutilizable: UNA copia del presupuesto. Se usa dos veces (compacto)
  // o una vez (full). Sin repetir consultas: los datos ya se leyeron una sola vez.
  const renderCopia = (filas: string, full: boolean): string => `
    <section class="copia${full ? " full" : ""}">
      ${membreteA4()}
      <div class="head">
        <div>
          <div class="negocio">PRESUPUESTO</div>
          <div class="doc-tag">${esc(negocio)}</div>
        </div>
        <div class="meta">
          <div class="num">${esc(p.numero_control)}</div>
          <div>Fecha: ${fmtFecha(p.fecha)}</div>
          ${p.fecha_vencimiento ? `<div>Válido hasta: ${fmtFecha(p.fecha_vencimiento)}</div>` : ""}
        </div>
      </div>

      <div class="grid2">
        <div class="box">
          <h3>Cliente</h3>
          <p><strong>${esc(p.cliente_nombre)}</strong></p>
          ${p.cliente_ruc ? `<p>RUC/CI: ${esc(p.cliente_ruc)}</p>` : ""}
          ${p.cliente_telefono ? `<p>Tel: ${esc(p.cliente_telefono)}</p>` : ""}
          ${p.cliente_direccion ? `<p>${esc(p.cliente_direccion)}</p>` : ""}
        </div>
        <div class="box">
          <h3>Datos del presupuesto</h3>
          <p>Moneda: ${moneda === "USD" ? "Dólares (USD)" : "Guaraníes (PYG)"}</p>
          ${p.forma_pago ? `<p>Forma de pago: ${esc(p.forma_pago)}</p>` : ""}
          ${p.plazo_entrega ? `<p>Plazo de entrega: ${esc(p.plazo_entrega)}</p>` : ""}
          ${p.validez_dias ? `<p>Validez: ${esc(p.validez_dias)} día(s)</p>` : ""}
        </div>
      </div>

      <table>
        <thead>
          <tr>
            <th class="c">Cant.</th>
            <th>Descripción</th>
            <th class="r">Precio unit.</th>
            <th class="c">IVA</th>
            <th class="r">Desc.</th>
            <th class="r">Total</th>
          </tr>
        </thead>
        <tbody>${filas || `<tr><td colspan="6" class="c">Sin ítems</td></tr>`}</tbody>
      </table>

      <table class="totales">
        <tr><td>Subtotal (sin IVA)</td><td>${fmtMoneda(p.subtotal, moneda)}</td></tr>
        <tr><td>IVA</td><td>${fmtMoneda(p.monto_iva, moneda)}</td></tr>
        ${Number(p.descuento_total) > 0 ? `<tr><td>Descuentos</td><td>- ${fmtMoneda(p.descuento_total, moneda)}</td></tr>` : ""}
        <tr class="total-row"><td>TOTAL</td><td>${fmtMoneda(p.total, moneda)}</td></tr>
      </table>

      ${condiciones.length ? `<div class="cond"><h3>Condiciones comerciales</h3><ul>${condiciones.map((c) => `<li>${c}</li>`).join("")}</ul></div>` : ""}
      ${full && p.observaciones ? `<div class="obs"><strong>Observaciones:</strong>\n${esc(p.observaciones)}</div>` : ""}
      ${full ? `<div class="firmas"><div class="firma"><div class="linea">Firma y aclaración — ${esc(negocio)}</div></div><div class="firma"><div class="linea">Aceptación del cliente${p.cliente_nombre ? ` — ${esc(p.cliente_nombre)}` : ""}</div></div></div>` : ""}

      <div class="legal">Documento no fiscal — no válido como factura. Sujeto a disponibilidad de stock y validez indicada.</div>
    </section>`;

  const html = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(p.numero_control)}</title>
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body { font-family: -apple-system, "Segoe UI", Roboto, Arial, sans-serif; color: #1f2937; background: #e5e7eb; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .toolbar { position: sticky; top: 0; z-index: 10; background: #111827; color: #fff; padding: 10px 16px; display: flex; gap: 12px; align-items: center; justify-content: center; }
  .toolbar button { background: #4FAEB2; color: #fff; border: 0; padding: 8px 16px; border-radius: 6px; font-size: 14px; cursor: pointer; }
  .toolbar .hint { font-size: 12px; color: #cbd5e1; }

  .sheet { width: 210mm; margin: 12px auto; background: #fff; box-shadow: 0 2px 12px rgba(0,0,0,.15); }
  .dual { display: grid; grid-template-rows: 1fr auto 1fr; height: 297mm; }
  .single { display: none; }
  .dual .copia { overflow: hidden; padding: 6mm 10mm; }
  .single .copia { padding: 14mm 14mm; }
  /* Copia compacta (2 por hoja): logo, tipografía y espaciados reducidos para
     que entren ~7-8 ítems en media A4 antes de caer a la hoja completa. */
  .dual .copia img { max-height: 40px !important; max-width: 128px !important; }
  .dual .copia > div:first-child { padding-bottom: 5px !important; margin-bottom: 7px !important; }
  .dual .copia .head { padding-bottom: 4px; }
  .dual .copia .negocio { font-size: 14px; }
  .dual .copia .meta .num { font-size: 13px; }
  .dual .copia .grid2 { margin-top: 5px; gap: 8px; }
  .dual .copia .box { padding: 4px 7px; }
  .dual .copia .box h3 { font-size: 9px; }
  .dual .copia .box p { font-size: 10px; }
  .dual .copia table { margin-top: 5px; font-size: 10px; }
  .dual .copia thead th { padding: 3px 6px; font-size: 9px; }
  .dual .copia tbody td { padding: 2.5px 6px; }
  .dual .copia .desc { font-size: 9px; }
  .dual .copia .totales { margin-top: 4px; font-size: 10px; }
  .dual .copia .totales tr td { padding: 2px 6px; }
  .dual .copia .totales .total-row td { font-size: 12px; }
  .dual .copia .cond { margin-top: 5px; }
  .dual .copia .cond ul { font-size: 9.5px; }
  .dual .copia .legal { margin-top: 5px; }

  .corte { display: flex; align-items: center; gap: 8px; padding: 1mm 8mm; color: #6b7280; font-size: 10px; border-top: 1px dashed #9ca3af; border-bottom: 1px dashed #9ca3af; }
  .corte span { flex: 1; text-align: center; letter-spacing: 2px; text-transform: uppercase; }

  .head { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #4FAEB2; padding-bottom: 6px; }
  .negocio { font-size: 16px; font-weight: 800; color: #1f2937; }
  .copia.full .negocio { font-size: 22px; }
  .doc-tag { color: #6b7280; font-size: 10px; margin-top: 2px; letter-spacing: .08em; text-transform: uppercase; }
  .meta { text-align: right; font-size: 11px; }
  .meta .num { font-size: 15px; font-weight: 700; color: #4FAEB2; }
  .copia.full .meta .num { font-size: 18px; }
  .grid2 { display: flex; gap: 12px; margin-top: 8px; }
  .box { flex: 1; border: 1px solid #d1d5db; border-radius: 6px; padding: 6px 9px; }
  .box h3 { margin: 0 0 3px; font-size: 9.5px; text-transform: uppercase; letter-spacing: .06em; color: #6b7280; }
  .box p { margin: 1px 0; font-size: 11px; }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 11px; }
  thead th { background: #4FAEB2; color: #fff; text-align: left; padding: 4px 7px; font-size: 9.5px; text-transform: uppercase; letter-spacing: .04em; }
  thead th.c, thead th.r { text-align: center; }
  thead th.r { text-align: right; }
  tbody td { padding: 4px 7px; border-bottom: 1px solid #eef2f4; vertical-align: top; }
  tbody td.c { text-align: center; }
  tbody td.r { text-align: right; white-space: nowrap; }
  thead th.r { white-space: nowrap; }
  .sku { color: #9ca3af; font-size: 9.5px; }
  .desc { color: #374151; font-size: 10px; margin-top: 1px; }
  .itemc { display: flex; gap: 6px; align-items: flex-start; }
  .itemc .thumb { width: 34px; height: 34px; object-fit: cover; border-radius: 4px; border: 1px solid #e5e7eb; flex: 0 0 auto; }
  .dual .copia .itemc .thumb { width: 30px; height: 30px; }
  .itemdetalle { display: flex; gap: 8px; margin-top: 6px; align-items: flex-start; }
  .itemimg { width: 52px; height: 52px; object-fit: cover; border-radius: 6px; border: 1px solid #e5e7eb; }
  .itemtxt { flex: 1; }
  .espec { color: #4b5563; font-size: 10px; }
  .carac { margin: 2px 0 0 14px; padding: 0; color: #4b5563; font-size: 10px; }
  .carac li { margin: 0; }
  .totales { width: 52%; margin-left: auto; margin-top: 6px; font-size: 11px; }
  .totales tr td { padding: 3px 7px; border: none; }
  .totales tr td:last-child { text-align: right; font-variant-numeric: tabular-nums; }
  .totales .total-row td { border-top: 2px solid #4FAEB2; font-weight: 800; font-size: 13px; color: #1f2937; }
  .copia.full table { font-size: 13px; }
  .copia.full thead th { padding: 8px 10px; font-size: 11px; }
  .copia.full tbody td { padding: 8px 10px; }
  .copia.full .totales { font-size: 14px; }
  .copia.full .totales .total-row td { font-size: 16px; }
  .cond { margin-top: 8px; }
  .cond h3 { font-size: 9.5px; text-transform: uppercase; letter-spacing: .06em; color: #6b7280; margin: 0 0 3px; }
  .cond ul { margin: 0; padding-left: 16px; font-size: 10.5px; }
  .obs { margin-top: 8px; font-size: 11px; white-space: pre-wrap; }
  .firmas { display: flex; justify-content: space-between; gap: 40px; margin-top: 40px; }
  .firma { flex: 1; text-align: center; }
  .firma .linea { border-top: 1px solid #374151; margin-top: 36px; padding-top: 6px; font-size: 11px; color: #4b5563; }
  .legal { margin-top: 8px; padding-top: 5px; border-top: 1px dashed #d1d5db; font-size: 9.5px; color: #6b7280; text-align: center; }

  @media print {
    @page { size: A4 portrait; margin: 0; }
    html, body { background: #fff; }
    .toolbar { display: none; }
    .sheet { width: 210mm; margin: 0; box-shadow: none; }
    .dual { height: 297mm; }
  }
</style>
</head>
<body>
  <div class="toolbar">
    <button onclick="window.print()">Imprimir / Guardar PDF</button>
    <span class="hint">Se imprimen 2 copias en una hoja A4 (o 1 hoja completa si hay muchos productos).</span>
  </div>
  <div class="sheet" id="sheet">
    <div class="dual" id="dual">
      ${renderCopia(filasCompact, false)}
      <div class="corte"><span>✂ Cortar aquí ✂</span></div>
      ${renderCopia(filasCompact, false)}
    </div>
    <div class="single" id="single">
      ${renderCopia(filasFull, true)}
    </div>
  </div>
  <script>
    window.addEventListener('load', function () {
      try {
        var dual = document.getElementById('dual');
        var single = document.getElementById('single');
        var copia = dual.querySelector('.copia');
        // Si una copia compacta no entra en su media hoja, usar 1 hoja A4 completa
        // (con detalle) en vez de recortar o dejar una mitad vacía.
        if (copia && copia.scrollHeight > copia.clientHeight + 8) {
          dual.style.display = 'none';
          single.style.display = 'block';
        }
      } catch (e) {}
      if (${auto ? "true" : "false"}) { setTimeout(function () { try { window.print(); } catch (e) {} }, 250); }
    });
  </script>
</body>
</html>`;

  return new NextResponse(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}
