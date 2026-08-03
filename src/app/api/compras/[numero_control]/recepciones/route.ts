import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import {
  crearRecepcion,
  getResumenCompra,
  listRecepciones,
  RecepcionExcedenteError,
  type RecepcionItemInput,
} from "@/lib/compras/server/recepciones-pg";

/** GET: resumen comprado/recibido/pendiente + recepciones de la compra. */
export async function GET(request: NextRequest, { params }: { params: Promise<{ numero_control: string }> }) {
  try {
    const { numero_control } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const [resumen, recepciones] = await Promise.all([
      getResumenCompra(schema, ctx.auth.empresa_id, numero_control),
      listRecepciones(schema, ctx.auth.empresa_id, numero_control),
    ]);
    if (!resumen) return NextResponse.json(errorResponse("Compra no encontrada."), { status: 404 });
    return NextResponse.json(successResponse({ resumen, recepciones }));
  } catch (err) {
    console.error("[/api/compras/[nc]/recepciones GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las recepciones."), { status: 500 });
  }
}

/** POST: crea una recepción (borrador o confirmada). */
export async function POST(request: NextRequest, { params }: { params: Promise<{ numero_control: string }> }) {
  try {
    const { numero_control } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;

    const rawItems = Array.isArray(body.items) ? (body.items as Record<string, unknown>[]) : [];
    const items: RecepcionItemInput[] = rawItems
      .map((it) => ({
        compra_id: String(it.compra_id ?? ""),
        producto_id: String(it.producto_id ?? ""),
        producto_nombre: String(it.producto_nombre ?? ""),
        sku: (it.sku as string) ?? null,
        cantidad_recibida: Number(it.cantidad_recibida) || 0,
        cantidad_rechazada: Number(it.cantidad_rechazada) || 0,
        costo_unitario: Number(it.costo_unitario) || 0,
        observacion: (it.observacion as string) ?? null,
      }))
      .filter((it) => it.producto_id && it.cantidad_recibida > 0);

    if (items.length === 0) {
      return NextResponse.json(errorResponse("Indicá al menos un ítem con cantidad recibida."), { status: 400 });
    }

    const out = await crearRecepcion(
      schema,
      ctx.auth.empresa_id,
      {
        compra_numero_control: numero_control,
        deposito_id: (body.deposito_id as string) ?? null,
        sucursal_id: (body.sucursal_id as string) ?? null,
        observacion: (body.observacion as string) ?? null,
        firma_entrega: (body.firma_entrega as string) ?? null,
        firma_recepcion: (body.firma_recepcion as string) ?? null,
        documento_url: (body.documento_url as string) ?? null,
        documento_storage_path: (body.documento_storage_path as string) ?? null,
        documento_nombre: (body.documento_nombre as string) ?? null,
        documento_mime_type: (body.documento_mime_type as string) ?? null,
        items,
        confirmar: body.confirmar === true,
      },
      { id: ctx.auth.usuarioCatalogId ?? null, nombre: ctx.auth.nombre ?? null, email: ctx.auth.user?.email ?? null },
    );

    return NextResponse.json(successResponse(out));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo registrar la recepción.";
    const status = err instanceof RecepcionExcedenteError ? 409 : /no encontrada|no tiene/i.test(msg) ? 400 : 500;
    console.error("[/api/compras/[nc]/recepciones POST]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
