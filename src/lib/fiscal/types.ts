/**
 * Abstracción de proveedores fiscales por país (Fase 11).
 *
 * Reutiliza la separación existente entre factura comercial y factura
 * electrónica. NO reimplementa SIFEN: el proveedor `sifen_py` delega en el flujo
 * SIFEN ya existente. `sin_bo` (Bolivia SIN) queda detrás de feature flag y sin
 * emisión real hasta pruebas y autorización.
 */
export type ProveedorFiscal = "none" | "sifen_py" | "sin_bo";

export type DocumentoFiscalEstado =
  | "borrador"
  | "generado"
  | "firmado"
  | "enviado"
  | "validado"
  | "rechazado"
  | "anulado"
  | "contingencia"
  | "error";

export interface FiscalContext {
  schema: string;
  empresaId: string;
  facturaId?: string;
  ventaId?: string;
  usuario?: { id?: string | null; nombre?: string | null; email?: string | null };
}

export interface FiscalResult {
  ok: boolean;
  estado: DocumentoFiscalEstado;
  mensaje?: string;
  /** Requisitos externos faltantes (credenciales/autorizaciones) si aplica. */
  faltantes?: string[];
}

export interface FiscalProvider {
  readonly codigo: ProveedorFiscal;
  readonly pais: string;
  /** ¿Emite documento electrónico o es factura comercial interna? */
  readonly electronico: boolean;
  /** Emite/registra el documento fiscal para la factura del contexto. */
  emitir(ctx: FiscalContext): Promise<FiscalResult>;
  /** Estado/diagnóstico del proveedor para una empresa (habilitación, faltantes). */
  estado(ctx: FiscalContext): Promise<FiscalResult>;
}

export class FiscalNoHabilitadoError extends Error {
  faltantes: string[];
  constructor(message: string, faltantes: string[] = []) {
    super(message);
    this.name = "FiscalNoHabilitadoError";
    this.faltantes = faltantes;
  }
}
