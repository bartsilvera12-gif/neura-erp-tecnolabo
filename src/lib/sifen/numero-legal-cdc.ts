/**
 * Número legal de un documento electrónico (establecimiento-puntoExpedición-
 * númeroDocumento) a partir de su CDC de 44 dígitos: posiciones 12-14, 15-17 y
 * 18-24 (0-indexado 11/14/17). Devuelve null si el CDC no está completo (p. ej.
 * documento aún sin DE aprobado). Misma convención que el listado de ventas.
 */
export function numeroLegalDesdeCdc(cdc: string | null | undefined): string | null {
  const s = String(cdc ?? "").trim();
  if (s.length < 24) return null;
  return s.slice(11, 14) + "-" + s.slice(14, 17) + "-" + s.slice(17, 24);
}
