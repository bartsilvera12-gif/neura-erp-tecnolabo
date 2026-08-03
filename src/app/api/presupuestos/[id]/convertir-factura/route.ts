import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import {
  convertirPresupuestoAFactura,
  PresupuestoNoConvertibleError,
} from "@/lib/presupuestos/server/presupuestos-conversion-pg";

/**
 * POST /api/presupuestos/[id]/convertir-factura
 * Convierte un presupuesto APROBADO en una factura (receivables). Idempotente:
 * reintento / doble clic devuelven la MISMA factura (guard UNIQUE en BD).
 * Body opcional: { tipo_pago?: 'contado'|'credito', dias_vencimiento?: number }.
 */
export async function POST(request: NextRequest, ctxParams: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctxParams.params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });

    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);

    const res = await convertirPresupuestoAFactura(schema, ctx.auth.empresa_id, {
      presupuestoId: id,
      usuarioId: ctx.auth.usuarioCatalogId ?? null,
      usuarioNombre: ctx.auth.nombre ?? null,
      usuarioEmail: ctx.auth.user?.email ?? null,
      tipoPago: typeof body.tipo_pago === "string" ? body.tipo_pago : undefined,
      diasVencimiento: typeof body.dias_vencimiento === "number" ? body.dias_vencimiento : undefined,
    });

    return NextResponse.json(
      successResponse({
        factura_id: res.facturaId,
        numero_factura: res.numeroFactura,
        ya_existia: res.yaExistia,
      }),
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo convertir el presupuesto.";
    const status =
      err instanceof PresupuestoNoConvertibleError
        ? /en curso/i.test(msg)
          ? 409
          : 400
        : 500;
    console.error("[/api/presupuestos/[id]/convertir-factura]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
