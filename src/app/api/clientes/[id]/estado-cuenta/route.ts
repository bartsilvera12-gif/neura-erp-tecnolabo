import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { facturaPorVenta, facturaSinEfectoCobro } from "@/lib/cobros/numero-factura-por-venta";

/**
 * GET /api/clientes/[id]/estado-cuenta — resumen + cuentas por cobrar + cobros del cliente.
 * Solo lectura. No toca ventas/stock.
 */
export async function GET(request: NextRequest, ctxParams: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctxParams.params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const empresaId = ctx.auth.empresa_id;
    const hoy = new Date().toISOString().slice(0, 10);

    const cq = await ctx.supabase
      .from("clientes")
      .select("id, empresa, nombre_contacto, nombre, ruc, documento, telefono, direccion")
      .eq("empresa_id", empresaId)
      .eq("id", id)
      .maybeSingle();
    if (cq.error) throw new Error(cq.error.message);
    if (!cq.data) return NextResponse.json(errorResponse(API_ERRORS.NOT_FOUND), { status: 404 });
    const c = cq.data as Record<string, unknown>;
    const s = (v: unknown) => (typeof v === "string" ? v.trim() : "");
    const cliente = {
      id: String(c.id),
      nombre: s(c.empresa) || s(c.nombre_contacto) || s(c.nombre) || "Cliente",
      ruc: s(c.ruc) || s(c.documento) || null,
      telefono: s(c.telefono) || null,
      direccion: s(c.direccion) || null,
    };

    // Ventas del cliente → total vendido (excluye anuladas).
    const vq = await ctx.supabase
      .from("ventas")
      .select("total")
      .eq("empresa_id", empresaId)
      .eq("cliente_id", id)
      .neq("estado", "anulada");
    if (vq.error) throw new Error(vq.error.message);
    const totalVendido = ((vq.data ?? []) as Record<string, unknown>[]).reduce((acc, r) => acc + (Number(r.total) || 0), 0);

    // Cuentas por cobrar (movimientos de crédito).
    const cxcQ = await ctx.supabase
      .from("cuentas_por_cobrar")
      .select("id, venta_id, numero_venta, fecha_emision, fecha_vencimiento, moneda, total, saldo, estado")
      .eq("empresa_id", empresaId)
      .eq("cliente_id", id)
      .order("fecha_emision", { ascending: false });
    if (cxcQ.error) throw new Error(cxcQ.error.message);
    const cxcRows = (cxcQ.data ?? []) as Record<string, unknown>[];

    // Factura (número + estado) por venta: para mostrar FAC- en lugar de VTA- y
    // detectar las corregidas por NC / anuladas (no suman ni se cobran).
    const facMap = await facturaPorVenta(
      ctx.supabase,
      empresaId,
      cxcRows.map((r) => (r.venta_id ? String(r.venta_id) : null))
    );

    let saldoPendiente = 0;
    let vencido = 0;
    // Total de las cuentas corregidas por NC (factura en 0): se descuenta del
    // total vendido para que "Cobrado" (= vendido − saldo) no se infle.
    let corregidaTotal = 0;
    const movimientos = cxcRows.map((r) => {
      const total = Number(r.total) || 0;
      const saldo = Number(r.saldo) || 0;
      const venc = r.fecha_vencimiento ? String(r.fecha_vencimiento).slice(0, 10) : null;
      const vigentePendiente = r.estado === "pendiente" || r.estado === "parcial";
      const ventaId = r.venta_id ? String(r.venta_id) : null;
      const fac = ventaId ? facMap.get(ventaId) ?? null : null;
      // Corregida por NC o factura anulada: la cuenta ya no se debe aunque el
      // CxC siga "pendiente" (la NC no baja el saldo del CxC, solo el de la factura).
      const corregida = facturaSinEfectoCobro(fac?.estado);
      const anuladoCxc = r.estado === "anulado";

      if (!anuladoCxc && !corregida) saldoPendiente += saldo;
      if (corregida && !anuladoCxc) corregidaTotal += total;
      const vencida = vigentePendiente && !corregida && venc != null && venc < hoy;
      if (vencida) vencido += saldo;

      return {
        id: String(r.id),
        venta_id: ventaId,
        numero_venta: r.numero_venta ?? null,
        numero_factura: fac?.numero_factura ?? null,
        corregida,
        fecha_emision: r.fecha_emision ?? null,
        fecha_vencimiento: venc,
        total,
        cobrado: Math.round((total - saldo) * 100) / 100,
        saldo,
        estado: r.estado,
        vencida,
      };
    });

    // Historial de cobros del cliente.
    const cobQ = await ctx.supabase
      .from("cobros_clientes")
      .select("id, cuenta_por_cobrar_id, venta_id, fecha_pago, monto, metodo_pago, referencia")
      .eq("empresa_id", empresaId)
      .eq("cliente_id", id)
      .is("anulado_at", null)
      .order("fecha_pago", { ascending: false })
      .limit(500);
    if (cobQ.error) throw new Error(cobQ.error.message);
    const cobros = (cobQ.data ?? []) as Record<string, unknown>[];

    // El total vendido no computa lo revertido por NC (facturas corregidas).
    const totalVendidoNeto = totalVendido - corregidaTotal;
    const resumen = {
      total_vendido: Math.round(totalVendidoNeto),
      saldo_pendiente: Math.round(saldoPendiente),
      total_cobrado: Math.round(totalVendidoNeto - saldoPendiente),
      vencido: Math.round(vencido),
    };

    return NextResponse.json(successResponse({ cliente, resumen, movimientos, cobros }));
  } catch (err) {
    console.error("[/api/clientes/[id]/estado-cuenta GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo cargar el estado de cuenta."), { status: 500 });
  }
}
