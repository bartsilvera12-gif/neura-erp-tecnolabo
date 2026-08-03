import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuthWithRol } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { getEmpresaConfig, setEmpresaConfig } from "@/lib/config/server/empresa-config-pg";
import { resolveFiscalProvider } from "@/lib/fiscal/providers";

function esAdmin(rol?: string): boolean {
  const r = (rol ?? "").toLowerCase();
  return r === "super_admin" || r === "admin" || r === "administrador";
}
const VALIDOS = ["none", "sifen_py", "sin_bo"];

export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const cfg = await getEmpresaConfig(schema, ctx.auth.empresa_id);
    const provider = resolveFiscalProvider(cfg.proveedor_fiscal);
    const estado = await provider.estado({ schema, empresaId: ctx.auth.empresa_id });
    return NextResponse.json(successResponse({
      proveedor_fiscal: cfg.proveedor_fiscal,
      pais_fiscal: cfg.pais_fiscal,
      fiscal_habilitado: cfg.fiscal_habilitado,
      proveedor_estado: estado,
    }));
  } catch (err) {
    console.error("[/api/configuracion/proveedor-fiscal GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo cargar la configuración fiscal."), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    if (!esAdmin(ctx.auth.rol)) return NextResponse.json(errorResponse("Solo un administrador puede cambiar la configuración fiscal."), { status: 403 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const proveedor = VALIDOS.includes(String(body.proveedor_fiscal)) ? String(body.proveedor_fiscal) : "none";
    const pais = proveedor === "sifen_py" ? "PY" : proveedor === "sin_bo" ? "BO" : null;
    // Bolivia queda deshabilitada por seguridad salvo que se indique explícitamente.
    const habilitado = proveedor === "sin_bo" ? body.fiscal_habilitado === true : proveedor === "sifen_py";
    const cfg = await setEmpresaConfig(schema, ctx.auth.empresa_id, {
      proveedor_fiscal: proveedor,
      pais_fiscal: pais,
      fiscal_habilitado: habilitado,
    });
    return NextResponse.json(successResponse({ proveedor_fiscal: cfg.proveedor_fiscal, pais_fiscal: cfg.pais_fiscal, fiscal_habilitado: cfg.fiscal_habilitado }));
  } catch (err) {
    console.error("[/api/configuracion/proveedor-fiscal POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo guardar la configuración fiscal."), { status: 500 });
  }
}
