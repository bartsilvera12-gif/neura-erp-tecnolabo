/**
 * IdCSC (identificador del CSC en el SET) usado en la URL del QR (`IdCSC=`).
 *
 * El SET entrega dos CSC por timbrado: CSC1 → IdCSC `0001` y CSC2 → IdCSC `0002`.
 * El `cHashQR` se valida del lado del SET tomando la cadena de la URL hasta
 * `IdCSC=xxxx` y concatenándole **el CSC que corresponde a ese IdCSC**. Enviar un
 * IdCSC que no corresponde al CSC cargado produce el rechazo
 * «El hash del código QR incluido el de la cadena de caracteres es inválido».
 */

/** Valor por defecto cuando la empresa no configuró el IdCSC (CSC1). */
export const SIFEN_ID_CSC_DEFAULT = "0001";

/** `true` si el valor tiene la forma exigida por el SET: exactamente 4 dígitos. */
export function esIdCscValido(value: string): boolean {
  return /^[0-9]{4}$/.test(value);
}

/**
 * Normaliza un IdCSC a 4 dígitos (`"1"` → `"0001"`). Devuelve `null` si no es
 * representable como IdCSC válido.
 */
export function normalizarIdCsc(value: unknown): string | null {
  if (value == null) return null;
  const raw = String(value).trim();
  if (raw === "") return null;
  if (!/^[0-9]{1,4}$/.test(raw)) return null;
  const padded = raw.padStart(4, "0");
  return esIdCscValido(padded) ? padded : null;
}

/**
 * IdCSC efectivo para firmar: valor de la empresa → env `SIFEN_ID_CSC` → `0001`.
 */
export function resolverIdCsc(idCscEmpresa: unknown): string {
  return (
    normalizarIdCsc(idCscEmpresa) ??
    normalizarIdCsc(process.env.SIFEN_ID_CSC) ??
    SIFEN_ID_CSC_DEFAULT
  );
}
