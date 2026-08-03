/**
 * Implementaciones de proveedores fiscales (Fase 11).
 *  - none:     factura comercial interna (no electrónica).
 *  - sifen_py: delega en el flujo SIFEN existente (no se reimplementa aquí).
 *  - sin_bo:   Bolivia SIN — arquitectura + config lista, EMISIÓN REAL detrás de
 *              feature flag y sin habilitar hasta credenciales + autorización.
 */
import type { FiscalContext, FiscalProvider, FiscalResult } from "@/lib/fiscal/types";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";

/** Requisitos externos que el cliente debe proveer para habilitar Bolivia. */
export const SIN_BO_REQUISITOS: string[] = [
  "Modalidad de facturación SIN (electrónica en línea / computarizada en línea)",
  "NIT y razón social registrados en el SIN",
  "Código de sucursal y punto de venta autorizados",
  "CUIS vigente (código único de inicio de sistemas)",
  "CUFD vigente (código único de facturación diaria)",
  "Certificado digital (.p12) y su contraseña",
  "Token/credenciales de API del SIN (SIAT)",
  "Autorización del SIN para el ambiente de producción",
];

const noneProvider: FiscalProvider = {
  codigo: "none",
  pais: "XX",
  electronico: false,
  async emitir(): Promise<FiscalResult> {
    return { ok: true, estado: "validado", mensaje: "Factura comercial interna (sin documento electrónico)." };
  },
  async estado(): Promise<FiscalResult> {
    return { ok: true, estado: "validado", mensaje: "Modo comercial interno." };
  },
};

const sifenPyProvider: FiscalProvider = {
  codigo: "sifen_py",
  pais: "PY",
  electronico: true,
  async emitir(): Promise<FiscalResult> {
    // La emisión SIFEN se realiza por su flujo existente (wizard + rutas /sifen/*).
    return {
      ok: false,
      estado: "borrador",
      mensaje: "Paraguay usa el flujo SIFEN existente (wizard/API /api/facturas/[id]/sifen/*).",
    };
  },
  async estado(): Promise<FiscalResult> {
    return { ok: true, estado: "borrador", mensaje: "Proveedor SIFEN (Paraguay) — gestionado por el módulo existente." };
  },
};

async function sinBoHabilitado(ctx: FiscalContext): Promise<boolean> {
  const pool = getChatPostgresPool();
  if (!pool) return false;
  const tCfg = quoteSchemaTable(ctx.schema, "empresa_config");
  const tSin = quoteSchemaTable(ctx.schema, "empresa_sin_config");
  const client = await pool.connect();
  try {
    const cfg = await client.query(`SELECT proveedor_fiscal, fiscal_habilitado FROM ${tCfg} WHERE empresa_id = $1::uuid`, [ctx.empresaId]);
    const sin = await client.query(`SELECT activo FROM ${tSin} WHERE empresa_id = $1::uuid`, [ctx.empresaId]);
    const row = cfg.rows[0];
    return row?.proveedor_fiscal === "sin_bo" && row?.fiscal_habilitado === true && sin.rows[0]?.activo === true;
  } finally {
    client.release();
  }
}

const sinBoProvider: FiscalProvider = {
  codigo: "sin_bo",
  pais: "BO",
  electronico: true,
  async emitir(ctx: FiscalContext): Promise<FiscalResult> {
    const habilitado = await sinBoHabilitado(ctx);
    if (!habilitado) {
      return {
        ok: false,
        estado: "error",
        mensaje: "La emisión electrónica Bolivia (SIN) no está habilitada. Falta configuración/credenciales y autorización.",
        faltantes: SIN_BO_REQUISITOS,
      };
    }
    // Habilitado por config, pero la integración real con el SIN aún no se
    // completa en esta fase (arquitectura lista, sin llamadas productivas).
    return {
      ok: false,
      estado: "contingencia",
      mensaje: "Adaptador Bolivia (SIN) preparado; la emisión real se activa tras completar pruebas y autorización.",
      faltantes: [],
    };
  },
  async estado(ctx: FiscalContext): Promise<FiscalResult> {
    const habilitado = await sinBoHabilitado(ctx);
    return {
      ok: habilitado,
      estado: habilitado ? "contingencia" : "borrador",
      mensaje: habilitado ? "Bolivia (SIN) configurado; pendiente de pruebas/autorización para emisión real." : "Bolivia (SIN) no habilitado.",
      faltantes: habilitado ? [] : SIN_BO_REQUISITOS,
    };
  },
};

const REGISTRY: Record<string, FiscalProvider> = {
  none: noneProvider,
  sifen_py: sifenPyProvider,
  sin_bo: sinBoProvider,
};

export function resolveFiscalProvider(codigo: string | null | undefined): FiscalProvider {
  return REGISTRY[codigo ?? "none"] ?? noneProvider;
}
