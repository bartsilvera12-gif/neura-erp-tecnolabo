import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import {
  crearNotaSalida,
  listNotasSalida,
  StockInsuficienteMovimientoError,
  type NotaSalidaItemInput,
} from "@/lib/inventario/server/notas-salida-pg";

export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const notas = await listNotasSalida(schema, ctx.auth.empresa_id);
    return NextResponse.json(successResponse({ notas }));
  } catch (err) {
    console.error("[/api/notas-salida GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las notas de salida."), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const rawItems = Array.isArray(body.items) ? (body.items as Record<string, unknown>[]) : [];
    const items: NotaSalidaItemInput[] = rawItems
      .map((it) => ({
        producto_id: String(it.producto_id ?? ""),
        producto_nombre: String(it.producto_nombre ?? ""),
        sku: (it.sku as string) ?? null,
        cantidad: Number(it.cantidad) || 0,
        costo_unitario: Number(it.costo_unitario) || 0,
        observacion: (it.observacion as string) ?? null,
      }))
      .filter((it) => it.producto_id && it.cantidad > 0);
    if (items.length === 0) return NextResponse.json(errorResponse("Agregá al menos un producto con cantidad."), { status: 400 });

    const out = await crearNotaSalida(
      schema,
      ctx.auth.empresa_id,
      {
        motivo: String(body.motivo ?? "otro"),
        deposito_id: (body.deposito_id as string) ?? null,
        sucursal_id: (body.sucursal_id as string) ?? null,
        observacion: (body.observacion as string) ?? null,
        items,
        confirmar: body.confirmar === true,
      },
      { id: ctx.auth.usuarioCatalogId ?? null, nombre: ctx.auth.nombre ?? null, email: ctx.auth.user?.email ?? null },
    );
    return NextResponse.json(successResponse(out));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo crear la nota de salida.";
    const status = err instanceof StockInsuficienteMovimientoError ? 409 : /no tiene|no encontrad/i.test(msg) ? 400 : 500;
    console.error("[/api/notas-salida POST]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
