import { toCalendarDateStr } from "@/lib/fechas/calendario";

/**
 * Guard de "retraso de emisión" para documentos electrónicos SIFEN.
 *
 * El SET rechaza un DE cuya fecha/hora de emisión (`dFeEmiDE`) supera la ventana
 * de transmisión normal respecto al momento del envío, con el mensaje
 * "La fecha y hora de emisión del DE informada es inválida por retraso".
 *
 * El `dFeEmiDE` lleva como fecha calendario la `fecha` de la factura (hora civil
 * de Paraguay) y como hora el instante de generación. Si esa fecha quedó varios
 * días atrás (p. ej. facturas de suscripción fechadas al día de facturación, o
 * facturas cargadas con fecha retroactiva), enviarlas a SET las hace caer fuera
 * de la ventana. Este guard detecta la condición ANTES de transmitir para
 * devolver un mensaje claro en vez del rechazo críptico del SET.
 */

/** Ventana de transmisión normal del SET (horas). Fuera de esto: rechazo "por retraso". */
export const SIFEN_RETRASO_MAX_HORAS = 72;

/** Zona usada por el SET para validar fecha/hora de emisión. */
const SIFEN_TZ = "America/Asuncion";

function ymdEnTz(d: Date, tz: string): string {
  // "en-CA" produce formato ISO YYYY-MM-DD (mismo patrón que rde-xml.ts).
  return d.toLocaleDateString("en-CA", { timeZone: tz });
}

/** Hoy (YYYY-MM-DD) en hora civil de Paraguay, la zona que el SET usa para el dFeEmiDE. */
export function hoyYmdSifen(ahora: Date = new Date()): string {
  return ymdEnTz(ahora, SIFEN_TZ);
}

function parseYmd(ymd: string): { y: number; mo: number; d: number } | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymd.trim());
  if (!m) return null;
  return { y: Number(m[1]), mo: Number(m[2]), d: Number(m[3]) };
}

/** Diferencia en días de calendario (hastaYmd - desdeYmd), sin corrimientos por zona/DST. */
function diasEntreYmd(desdeYmd: string, hastaYmd: string): number | null {
  const a = parseYmd(desdeYmd);
  const b = parseYmd(hastaYmd);
  if (!a || !b) return null;
  const am = Date.UTC(a.y, a.mo - 1, a.d);
  const bm = Date.UTC(b.y, b.mo - 1, b.d);
  return Math.round((bm - am) / 86_400_000);
}

export type RetrasoEmisionResult = {
  /** Fecha calendario (YYYY-MM-DD) del `dFeEmiDE` evaluada. */
  fechaEmisionYmd: string;
  /** Hoy en hora civil de Paraguay (YYYY-MM-DD). */
  hoyYmd: string;
  /** Días de atraso del `dFeEmiDE` respecto a hoy (0 = mismo día; negativo = futuro). */
  diasAtraso: number;
  /** Horas aproximadas de atraso: `dFeEmiDE` usa hora ~actual, así que ≈ diasAtraso * 24. */
  horasAtraso: number;
  /** true si supera la ventana del SET → rechazo "por retraso". */
  fueraDeVentana: boolean;
  /** Ventana máxima en horas aplicada. */
  maxHoras: number;
};

/**
 * Evalúa si una factura, por su fecha de emisión, caería fuera de la ventana
 * de retraso del SET si se enviara `ahora`.
 *
 * Devuelve `null` si la fecha es inválida/no parseable (el guard no debe
 * bloquear por un dato malformado; otras validaciones se encargan de eso).
 */
export function evaluarRetrasoEmisionSifen(
  fechaEmisionIso: string,
  ahora: Date = new Date(),
  maxHoras: number = SIFEN_RETRASO_MAX_HORAS
): RetrasoEmisionResult | null {
  const fechaYmd = toCalendarDateStr(fechaEmisionIso);
  if (!fechaYmd) return null;
  const hoyYmd = hoyYmdSifen(ahora);
  const dias = diasEntreYmd(fechaYmd, hoyYmd);
  if (dias == null) return null;
  const horasAtraso = dias * 24;
  return {
    fechaEmisionYmd: fechaYmd,
    hoyYmd,
    diasAtraso: dias,
    horasAtraso,
    // Estricto: `dFeEmiDE` usa `ahora` (menos un pequeño skew) como hora, por lo
    // que a los N días exactos la antigüedad real es N*24 h menos el skew. Con
    // `>` se bloquea recién cuando supera la ventana con holgura (≥ 96 h / 4 días)
    // y no se frenan envíos que el SET aún aceptaría justo en el borde de 72 h.
    fueraDeVentana: horasAtraso > maxHoras,
    maxHoras,
  };
}

/** Mensaje accionable para devolver al usuario cuando el guard bloquea el envío. */
export function mensajeRetrasoEmisionSifen(r: RetrasoEmisionResult): string {
  return (
    `No se envió a SET: la factura tiene fecha de emisión ${r.fechaEmisionYmd}, ` +
    `con ${r.diasAtraso} día(s) de atraso respecto a hoy (${r.hoyYmd}, hora de Paraguay). ` +
    `El SET rechaza documentos cuya emisión supera ${r.maxHoras} h ("La fecha y hora de emisión ` +
    `del DE informada es inválida por retraso"). Corrija la fecha de la factura a una dentro de la ` +
    `ventana y regenere el XML (borrador → XML → firmar) antes de reenviar.`
  );
}
