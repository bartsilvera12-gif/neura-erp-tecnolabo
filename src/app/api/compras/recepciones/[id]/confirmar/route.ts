import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { confirmarRecepcion, RecepcionExcedenteError } from "@/lib/compras/server/recepciones-pg";

/** POST /api/compras/recepciones/[id]/confirmar — confirma una recepción borrador (sube stock). */
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    await confirmarRecepcion(schema, ctx.auth.empresa_id, id, {
      id: ctx.auth.usuarioCatalogId ?? null,
      nombre: ctx.auth.nombre ?? null,
      email: ctx.auth.user?.email ?? null,
    });
    return NextResponse.json(successResponse({ ok: true }));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo confirmar la recepción.";
    const status = err instanceof RecepcionExcedenteError ? 409 : /no encontrada|no está/i.test(msg) ? 400 : 500;
    console.error("[/api/compras/recepciones/[id]/confirmar]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
