import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { registrarPagoProveedor, listPagosDeCuenta, PagoProveedorError } from "@/lib/compras/server/pagos-proveedor-pg";

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const pagos = await listPagosDeCuenta(schema, ctx.auth.empresa_id, id);
    return NextResponse.json(successResponse({ pagos }));
  } catch (err) {
    console.error("[/api/cuentas-por-pagar/[id]/pagos GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar los pagos."), { status: 500 });
  }
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const idempotencyKey = (typeof body.idempotency_key === "string" && body.idempotency_key) || request.headers.get("Idempotency-Key") || null;
    const out = await registrarPagoProveedor(schema, ctx.auth.empresa_id, {
      cuenta_por_pagar_id: id,
      monto: Number(body.monto),
      metodo_pago: body.metodo_pago ? String(body.metodo_pago) : "efectivo",
      referencia: body.referencia ? String(body.referencia) : null,
      fecha_pago: typeof body.fecha_pago === "string" ? body.fecha_pago : null,
      observacion: body.observacion ? String(body.observacion) : null,
      usuario_id: ctx.auth.usuarioCatalogId ?? null,
      usuario_nombre: ctx.auth.nombre ?? null,
      usuario_email: ctx.auth.user?.email ?? null,
      idempotency_key: idempotencyKey,
    });
    return NextResponse.json(successResponse(out));
  } catch (err) {
    if (err instanceof PagoProveedorError) return NextResponse.json(errorResponse(err.message), { status: err.status });
    console.error("[/api/cuentas-por-pagar/[id]/pagos POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo registrar el pago."), { status: 500 });
  }
}
