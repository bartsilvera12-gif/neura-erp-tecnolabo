import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";

/**
 * Vistas configurables por usuario (columnas/filtros/orden) por pantalla (clave).
 * Genérico: sirve para inventario, movimientos y reportes tabulares.
 * GET ?clave=...   → vistas del usuario para esa pantalla
 * POST {clave, nombre, config, es_predeterminada, id?} → crea/actualiza
 * DELETE ?id=...   → elimina una vista propia
 */
export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const clave = (new URL(request.url).searchParams.get("clave") ?? "").trim();
    const email = ctx.auth.user?.email ?? "";
    let q = ctx.supabase
      .from("usuario_vistas")
      .select("id, clave, nombre, config, es_predeterminada, updated_at")
      .eq("empresa_id", ctx.auth.empresa_id)
      .eq("usuario_email", email);
    if (clave) q = q.eq("clave", clave);
    const { data, error } = await q.order("updated_at", { ascending: false });
    if (error) throw new Error(error.message);
    return NextResponse.json(successResponse({ vistas: data ?? [] }));
  } catch (err) {
    console.error("[/api/usuario-vistas GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las vistas."), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const email = ctx.auth.user?.email ?? "";
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const clave = String(body.clave ?? "").trim();
    if (!clave) return NextResponse.json(errorResponse("Falta la clave de pantalla."), { status: 400 });
    const nombre = String(body.nombre ?? "Mi vista").trim() || "Mi vista";
    const config = (body.config && typeof body.config === "object" ? body.config : {}) as Record<string, unknown>;
    const esPred = body.es_predeterminada === true;

    // Si es predeterminada, desmarcar las demás de esta clave/usuario.
    if (esPred) {
      await ctx.supabase
        .from("usuario_vistas")
        .update({ es_predeterminada: false })
        .eq("empresa_id", ctx.auth.empresa_id)
        .eq("usuario_email", email)
        .eq("clave", clave);
    }

    const payload = {
      empresa_id: ctx.auth.empresa_id,
      usuario_id: ctx.auth.usuarioCatalogId ?? null,
      usuario_email: email,
      clave,
      nombre,
      config,
      es_predeterminada: esPred,
      updated_at: new Date().toISOString(),
    };

    if (body.id) {
      const { data, error } = await ctx.supabase
        .from("usuario_vistas")
        .update(payload)
        .eq("id", String(body.id))
        .eq("empresa_id", ctx.auth.empresa_id)
        .eq("usuario_email", email)
        .select("id")
        .maybeSingle();
      if (error) throw new Error(error.message);
      return NextResponse.json(successResponse({ id: (data as { id?: string } | null)?.id ?? body.id }));
    }

    const { data, error } = await ctx.supabase.from("usuario_vistas").insert(payload).select("id").single();
    if (error) throw new Error(error.message);
    return NextResponse.json(successResponse({ id: (data as { id: string }).id }));
  } catch (err) {
    console.error("[/api/usuario-vistas POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo guardar la vista."), { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const email = ctx.auth.user?.email ?? "";
    const id = (new URL(request.url).searchParams.get("id") ?? "").trim();
    if (!id) return NextResponse.json(errorResponse("Falta el id."), { status: 400 });
    const { error } = await ctx.supabase
      .from("usuario_vistas")
      .delete()
      .eq("id", id)
      .eq("empresa_id", ctx.auth.empresa_id)
      .eq("usuario_email", email);
    if (error) throw new Error(error.message);
    return NextResponse.json(successResponse({ ok: true }));
  } catch (err) {
    console.error("[/api/usuario-vistas DELETE]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo eliminar la vista."), { status: 500 });
  }
}
