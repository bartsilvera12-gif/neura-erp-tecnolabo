import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuthWithRol } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { assertModulo, ModuloError } from "@/lib/auth/modulo-guard";
import { assertPermiso, PermisoError } from "@/lib/auth/permisos";
import { anularReciboPg, ReciboAnularError } from "@/lib/recibos/server/recibos-anular-pg";

/**
 * POST /api/recibos-dinero/[id]/anular
 *
 * Anula un recibo de dinero. NO lo borra: conserva número, cliente, fecha,
 * monto, forma de pago y aplicaciones. Para recibos de cobro a crédito revierte
 * el cobro subyacente (restaura saldo de la cuenta por cobrar y de la factura)
 * en una sola transacción atómica. Registra usuario/fecha/motivo en auditoría.
 *
 * Body: { motivo?: string }
 * Guards: módulo 'recibos' + permiso 'anular'. Idempotente (409 si ya anulado).
 */
export async function POST(
  request: NextRequest,
  ctxParams: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await ctxParams.params;
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });

    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    // Doble gate en el server: módulo del menú + permiso de acción.
    await assertModulo(schema, ctx.auth.empresa_id, ctx.auth.user?.id, "recibos", ctx.auth.rol);
    await assertPermiso(schema, ctx.auth.empresa_id, ctx.auth.user?.email, "anular", ctx.auth.rol);

    let body: Record<string, unknown>;
    try {
      body = (await request.json()) as Record<string, unknown>;
    } catch {
      body = {};
    }
    const motivo = typeof body.motivo === "string" ? body.motivo : null;

    const result = await anularReciboPg(schema, ctx.auth.empresa_id, {
      reciboId: id,
      motivo,
      usuario: {
        id: ctx.auth.usuarioCatalogId ?? null,
        email: ctx.auth.user?.email ?? null,
        nombre: ctx.auth.nombre ?? ctx.auth.user?.email ?? null,
      },
    });

    return NextResponse.json(successResponse(result));
  } catch (err) {
    if (err instanceof ModuloError) return NextResponse.json(errorResponse(err.message), { status: 403 });
    if (err instanceof PermisoError) return NextResponse.json(errorResponse(err.message), { status: 403 });
    if (err instanceof ReciboAnularError) {
      return NextResponse.json(errorResponse(err.message), { status: err.status });
    }
    console.error("[/api/recibos-dinero/[id]/anular POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo anular el recibo."), { status: 500 });
  }
}
