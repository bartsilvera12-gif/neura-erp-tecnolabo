import * as forge from "node-forge";

export type P12Check = { ok: true } | { ok: false; error: string };

/**
 * Valida —SIN contraseña— que el buffer sea un PKCS#12 (.p12/.pfx) y no un
 * certificado público X.509 (.cer/.crt) u otro archivo distinto.
 *
 * Solo inspecciona la estructura ASN.1 de nivel superior:
 *   - Un PKCS#12 (PFX) es  SEQUENCE { version INTEGER, authSafe, macData }
 *     → su primer hijo es un INTEGER.
 *   - Un certificado X.509 es SEQUENCE { tbsCertificate SEQUENCE, ... }
 *     → su primer hijo es un SEQUENCE.
 *
 * No se descifra ni se verifica la contraseña acá (puede configurarse aparte),
 * así que tampoco se rechazan .p12 con cifrado moderno: solo se distingue el
 * tipo de archivo, que es el error de carga más común.
 */
export function validarEstructuraP12(buf: Buffer): P12Check {
  let asn1: forge.asn1.Asn1;
  try {
    asn1 = forge.asn1.fromDer(forge.util.createBuffer(buf.toString("binary")));
  } catch {
    return {
      ok: false,
      error:
        "El archivo no es un certificado válido (no tiene formato DER/PKCS#12). " +
        "Subí el .p12 / .pfx que te entregó la Autoridad Certificadora.",
    };
  }

  const primerHijo = Array.isArray(asn1.value) ? asn1.value[0] : undefined;
  const tipo =
    primerHijo != null && typeof primerHijo === "object"
      ? (primerHijo as forge.asn1.Asn1).type
      : undefined;

  if (tipo === forge.asn1.Type.INTEGER) {
    return { ok: true };
  }
  if (tipo === forge.asn1.Type.SEQUENCE) {
    return {
      ok: false,
      error:
        "El archivo cargado es un certificado público (.cer/.crt), no un .p12. " +
        "Subí el archivo .p12 / .pfx que incluye la CLAVE PRIVADA (el que pide contraseña).",
    };
  }
  return {
    ok: false,
    error:
      "El archivo no parece un .p12 válido. Subí el .p12 / .pfx que incluye la clave privada.",
  };
}
