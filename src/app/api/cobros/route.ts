import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuthWithRol } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { registrarCobroPg, CobroError } from "@/lib/cobros/server/cobros-tx-pg";

/**
 * POST /api/cobros — registra un cobro contra una cuenta por cobrar.
 * Transaccional e idempotente: enviá `idempotency_key` (o header
 * `Idempotency-Key`) para que doble clic / reintentos no dupliquen el cobro.
 */
export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const usuarioNombre = ctx.auth.nombre ?? ctx.auth.user?.email ?? null;
    const usuarioId = ctx.auth.usuarioCatalogId ?? null;
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);

    let body: Record<string, unknown>;
    try {
      body = (await request.json()) as Record<string, unknown>;
    } catch {
      return NextResponse.json(errorResponse("JSON inválido."), { status: 400 });
    }

    const idempotencyKey =
      (typeof body.idempotency_key === "string" && body.idempotency_key) || request.headers.get("Idempotency-Key") || null;

    const result = await registrarCobroPg(schema, ctx.auth.empresa_id, {
      cuenta_por_cobrar_id: String(body.cuenta_por_cobrar_id ?? ""),
      monto: Number(body.monto),
      metodo_pago: (body.metodo_pago as "efectivo" | "transferencia" | "tarjeta" | "otro") ?? "efectivo",
      entidad_bancaria_id: body.entidad_bancaria_id ? String(body.entidad_bancaria_id) : null,
      entidad_nombre_snapshot: body.entidad_nombre_snapshot ? String(body.entidad_nombre_snapshot) : null,
      referencia: body.referencia ? String(body.referencia) : null,
      titular: body.titular ? String(body.titular) : null,
      observaciones: body.observaciones ? String(body.observaciones) : null,
      fecha_pago: typeof body.fecha_pago === "string" ? body.fecha_pago : null,
      usuario_id: usuarioId,
      usuario_nombre: usuarioNombre,
      usuario_email: ctx.auth.user?.email ?? null,
      idempotency_key: idempotencyKey,
    });

    return NextResponse.json(successResponse(result));
  } catch (err) {
    if (err instanceof CobroError) {
      return NextResponse.json(errorResponse(err.message), { status: err.status });
    }
    console.error("[/api/cobros POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo registrar el cobro."), { status: 500 });
  }
}
