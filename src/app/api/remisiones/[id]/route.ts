import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import {
  getRemisionParaEdicion,
  editarRemision,
  RemisionExcedenteError,
  StockInsuficienteMovimientoError,
  type RemisionItemInput,
} from "@/lib/ventas/server/remisiones-pg";
import { assertPermiso, PermisoError } from "@/lib/auth/permisos";

/** GET /api/remisiones/[id] — detalle de la remisión para VER o EDITAR. */
export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const data = await getRemisionParaEdicion(schema, ctx.auth.empresa_id, id);
    if (!data) return NextResponse.json(errorResponse("Remisión no encontrada."), { status: 404 });
    return NextResponse.json(successResponse(data));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo cargar la remisión.";
    console.error("[/api/remisiones/[id] GET]", msg);
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}

/**
 * PATCH /api/remisiones/[id] — edita ítems/cantidades de la remisión.
 * NO modifica la factura. Editar una remisión CONFIRMADA mueve stock (ajuste por
 * diferencia) → requiere el permiso `confirmar_remision`. Editar un borrador no.
 */
export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);

    const detalle = await getRemisionParaEdicion(schema, ctx.auth.empresa_id, id);
    if (!detalle) return NextResponse.json(errorResponse("Remisión no encontrada."), { status: 404 });
    if (detalle.remision.estado === "confirmada") {
      await assertPermiso(schema, ctx.auth.empresa_id, ctx.auth.user?.email, "confirmar_remision");
    }

    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const rawItems = Array.isArray(body.items) ? (body.items as Record<string, unknown>[]) : [];
    const items: RemisionItemInput[] = rawItems
      .map((r) => ({
        factura_item_id: String(r.factura_item_id ?? ""),
        producto_id: String(r.producto_id ?? ""),
        producto_nombre: String(r.producto_nombre ?? ""),
        sku: (r.sku as string | null) ?? null,
        cantidad: Number(r.cantidad) || 0,
        costo_unitario: Number(r.costo_unitario) || 0,
      }))
      .filter((it) => it.factura_item_id && it.producto_id);

    await editarRemision(
      schema,
      ctx.auth.empresa_id,
      id,
      {
        items,
        observacion: typeof body.observacion === "string" ? body.observacion : detalle.remision.observacion,
        cliente_nombre: typeof body.cliente_nombre === "string" ? body.cliente_nombre.slice(0, 200) : undefined,
      },
      { id: ctx.auth.usuarioCatalogId ?? null, nombre: ctx.auth.nombre ?? null, email: ctx.auth.user?.email ?? null },
    );
    return NextResponse.json(successResponse({ ok: true }));
  } catch (err) {
    if (err instanceof PermisoError) return NextResponse.json(errorResponse(err.message), { status: 403 });
    const msg = err instanceof Error ? err.message : "No se pudo editar la remisión.";
    const status =
      err instanceof RemisionExcedenteError || err instanceof StockInsuficienteMovimientoError
        ? 409
        : /no encontrad|anulada|al menos un ítem/i.test(msg)
          ? 400
          : 500;
    console.error("[/api/remisiones/[id] PATCH]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
