/**
 * Cadena `dCarQR` (URL consulta QR) para rDE firmado, alineada a TIPS facturacionelectronicapy-qrgen
 * (Manual SIFEN / validación SET: error 2500 si el QR no coincide con el XML firmado).
 */
import { createHash } from "node:crypto";
import { DOMParser } from "@xmldom/xmldom";
import type { Element as XmlElement } from "@xmldom/xmldom";
import type { AmbienteSifen } from "./types";
import { SIFEN_TEST_ID_CSC } from "./sifen-ambiente-test";
import { normalizarIdCsc, resolverIdCsc } from "./sifen-id-csc";
import { SIFEN_EKUATIA_TARGET_NS } from "./sifen-xsi-schema-location";

const SIFEN_NS = SIFEN_EKUATIA_TARGET_NS;
const DSIG_NS = "http://www.w3.org/2000/09/xmldsig#";

export interface BuildSifenDcarQrOptions {
  ambiente: AmbienteSifen;
  csc: string;
  /**
   * Id del CSC en el SET: `0001` para el CSC1, `0002` para el CSC2. Debe
   * corresponder al CSC cargado en `csc` (el SET valida `cHashQR` con el CSC
   * asociado a este identificador). Si se omite se usa `SIFEN_ID_CSC` o `0001`.
   */
  idCsc?: string;
}

/** Partes de la URL del QR, útiles para diagnosticar un rechazo de `cHashQR`. */
export interface SifenDcarQrParts {
  /** Cadena exacta (desde `nVersion=` hasta `IdCSC=xxxx`) sobre la que se calcula el hash. */
  params: string;
  /** SHA-256 hex de `params + CSC`. */
  cHashQR: string;
  /** URL completa de consulta (`params&cHashQR=...`). */
  url: string;
  idCsc: string;
}

function textOf(el: XmlElement | null | undefined): string {
  return el?.textContent?.trim() ?? "";
}

/**
 * Construye la URL completa del QR a partir del XML **ya firmado** (debe existir `ds:Signature` / `DigestValue`).
 */
export function buildSifenDcarQrUrl(signedXmlUtf8: string, opts: BuildSifenDcarQrOptions): string {
  return buildSifenDcarQrParts(signedXmlUtf8, opts).url;
}

/**
 * Igual que {@link buildSifenDcarQrUrl}, pero devuelve además la cadena firmada y
 * el hash por separado (para scripts de diagnóstico del error «hash del código QR inválido»).
 */
export function buildSifenDcarQrParts(
  signedXmlUtf8: string,
  opts: BuildSifenDcarQrOptions
): SifenDcarQrParts {
  const csc = typeof opts.csc === "string" ? opts.csc.trim() : "";
  if (csc === "") {
    throw new Error(
      "Falta el CSC: sin él el cHashQR del QR no puede calcularse y el SET rechaza el DE."
    );
  }

  const doc = new DOMParser().parseFromString(signedXmlUtf8, "application/xml");
  const parseErr = doc.getElementsByTagName("parsererror")[0];
  if (parseErr) {
    throw new Error("XML inválido al generar dCarQR (parsererror)");
  }

  const rde =
    (doc.getElementsByTagNameNS(SIFEN_NS, "rDE")[0] as XmlElement | undefined) ??
    (doc.documentElement?.localName === "rDE" ? (doc.documentElement as XmlElement) : null);
  if (!rde) throw new Error("rDE no encontrado");

  const nVersion = textOf(rde.getElementsByTagNameNS(SIFEN_NS, "dVerFor")[0] as XmlElement);
  if (!nVersion) throw new Error("dVerFor vacío");

  const de = rde.getElementsByTagNameNS(SIFEN_NS, "DE")[0] as XmlElement | undefined;
  if (!de) throw new Error("DE no encontrado");
  const idDe = de.getAttribute("Id")?.trim();
  if (!idDe) throw new Error("DE sin atributo Id (CDC)");

  const gDatGralOpe = de.getElementsByTagNameNS(SIFEN_NS, "gDatGralOpe")[0] as XmlElement | undefined;
  if (!gDatGralOpe) throw new Error("gDatGralOpe no encontrado");
  const dFeEmiDE = textOf(gDatGralOpe.getElementsByTagNameNS(SIFEN_NS, "dFeEmiDE")[0] as XmlElement);
  if (!dFeEmiDE) throw new Error("dFeEmiDE vacío");

  const gDatRec = gDatGralOpe.getElementsByTagNameNS(SIFEN_NS, "gDatRec")[0] as XmlElement | undefined;
  if (!gDatRec) throw new Error("gDatRec no encontrado");
  const iNatRec = textOf(gDatRec.getElementsByTagNameNS(SIFEN_NS, "iNatRec")[0] as XmlElement);

  const gTotSub = de.getElementsByTagNameNS(SIFEN_NS, "gTotSub")[0] as XmlElement | undefined;
  let dTotGralOpe = gTotSub
    ? textOf(gTotSub.getElementsByTagNameNS(SIFEN_NS, "dTotGralOpe")[0] as XmlElement)
    : "";
  let dTotIVA = gTotSub ? textOf(gTotSub.getElementsByTagNameNS(SIFEN_NS, "dTotIVA")[0] as XmlElement) : "";
  if (dTotGralOpe === "") dTotGralOpe = "0";
  if (dTotIVA === "") dTotIVA = "0";

  const gDtipDE = de.getElementsByTagNameNS(SIFEN_NS, "gDtipDE")[0] as XmlElement | undefined;
  const cItems = gDtipDE ? gDtipDE.getElementsByTagNameNS(SIFEN_NS, "gCamItem").length : 0;

  const sig = doc.getElementsByTagNameNS(DSIG_NS, "Signature")[0] as XmlElement | undefined;
  if (!sig) throw new Error("Falta ds:Signature: el QR se calcula sobre el XML ya firmado");
  const references = sig.getElementsByTagNameNS(DSIG_NS, "Reference");
  let digestEl: XmlElement | undefined;
  for (let i = 0; i < references.length; i++) {
    const ref = references[i] as XmlElement;
    const uri = ref.getAttribute("URI")?.trim() ?? "";
    if (uri === `#${idDe}`) {
      digestEl = ref.getElementsByTagNameNS(DSIG_NS, "DigestValue")[0] as XmlElement | undefined;
      break;
    }
  }
  if (!digestEl && references.length === 1) {
    const sole = references[0] as XmlElement;
    digestEl = sole.getElementsByTagNameNS(DSIG_NS, "DigestValue")[0] as XmlElement | undefined;
  }
  if (!digestEl) {
    throw new Error("DigestValue no encontrado en la Reference del DE (ds:Signature)");
  }
  const digestB64 = textOf(digestEl);
  /** Igual que TIPS qrgen: hex de los bytes UTF-8 del texto base64 del DigestValue. */
  const digestHexUtf8 = Buffer.from(digestB64, "utf8").toString("hex");

  const dFeEmiHex = Buffer.from(dFeEmiDE, "utf8").toString("hex");

  let qr = "";
  qr += `nVersion=${nVersion}&`;
  qr += `Id=${idDe}&`;
  qr += `dFeEmiDE=${dFeEmiHex}&`;
  if (iNatRec === "1") {
    const dRucRec = textOf(gDatRec.getElementsByTagNameNS(SIFEN_NS, "dRucRec")[0] as XmlElement);
    qr += `dRucRec=${dRucRec}&`;
  } else {
    const dNumIDRec = textOf(gDatRec.getElementsByTagNameNS(SIFEN_NS, "dNumIDRec")[0] as XmlElement);
    qr += `dNumIDRec=${dNumIDRec}&`;
  }
  qr += `dTotGralOpe=${dTotGralOpe}&`;
  qr += `dTotIVA=${dTotIVA}&`;
  qr += `cItems=${cItems}&`;
  qr += `DigestValue=${digestHexUtf8}&`;

  // IdCSC: el SET entrega CSC1 (0001) y CSC2 (0002) por timbrado. Debe ser el que
  // corresponde al CSC cargado: si no coincide, el SET rechaza el DE con
  // «El hash del código QR ... es inválido».
  const idCsc =
    normalizarIdCsc(opts.idCsc) ??
    (opts.ambiente === "test" ? SIFEN_TEST_ID_CSC : resolverIdCsc(undefined));
  qr += `IdCSC=${idCsc}`;

  const cHashQR = createHash("sha256").update(qr + csc, "utf8").digest("hex");
  const params = qr;
  qr += `&cHashQR=${cHashQR}`;

  let base = "https://ekuatia.set.gov.py/consultas";
  if (opts.ambiente === "test") base += "-test";
  base += "/qr?";
  return { params, cHashQR, url: base + qr, idCsc };
}
