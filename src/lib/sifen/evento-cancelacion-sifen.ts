/**
 * Evento de Cancelación SIFEN (siRecepEvento): construye, firma y transmite a la SET el
 * evento que da de baja un DE ya aprobado. Es el envío REAL a SET; la "cancelación lógica"
 * del ERP (estado_sifen='cancelado') debe hacerse SOLO si la SET acepta este evento.
 *
 * Estructura (alineada a facturacionelectronicapy-xmlgen / Manual Técnico v150):
 *   env:Envelope > env:Body >
 *     rEnviEventoDe (xmlns e-kuatia) > dId + dEvReg >
 *       gGroupGesEve > rGesEve >
 *         rEve Id="1" > dFecFirma + dVerFor + gGroupTiEvt > rGeVeCan > Id(CDC) + mOtEve
 *         ds:Signature   (firma del nodo rEve; se inserta al firmar)
 *
 * TLS mutuo + firma: mismo .p12 de la empresa que firma el DE.
 *
 * NOTA: este flujo no pudo ejecutarse contra SET en el entorno de desarrollo. Validar contra
 * SET TEST (ambiente de pruebas) antes de confiar en producción.
 */
import * as https from "node:https";
import { URL } from "node:url";
import type { AmbienteSifen } from "./types";
import { extractKeyAndCertFromP12, signSifenEventoCancelacionXml } from "./sign-xml";
import { sifenFechaFirmaEventoAhora } from "./rde-xml";
import { SIFEN_EKUATIA_TARGET_NS } from "./sifen-xsi-schema-location";
import { urlRecibeEvento } from "./sifen-ws-urls";
import { escapeXml } from "./xml";

const SIFEN_NS = SIFEN_EKUATIA_TARGET_NS;
const SOAP_ENV = "http://www.w3.org/2003/05/soap-envelope";
const XMLNS_XSI = "http://www.w3.org/2001/XMLSchema-instance";
/** Archivo relativo (sin URL https) en xsi:schemaLocation, mismo criterio que el DE (evita 0160). */
const EVENTO_XSI_SCHEMA_LOCATION = `${SIFEN_NS} siRecepEvento_v150.xsd`;
/** SET acepta application/xml (no exige SOAP 1.2 con action), igual que recibe-lote. */
const CONTENT_TYPE_RECEP_EVENTO = "application/xml; charset=utf-8";
/** Código SET de evento registrado con éxito. */
const COD_EVENTO_OK = "0600";

export interface EmpresaConfigEventoCancelacion {
  ambiente?: AmbienteSifen;
  certificadoP12: Buffer;
  certificadoPassword: string;
}

export interface EnviarEventoCancelacionParams {
  /** CDC (44 dígitos) del DE a cancelar. */
  cdc: string;
  /** Motivo de la cancelación (5–500 caracteres, según XSD mOtEve). */
  motivo: string;
  empresaConfig: EmpresaConfigEventoCancelacion;
  /** Identificador de control de envío (dId). Si no se indica, se genera. */
  dId?: number;
  /** Versión de formato (dVerFor). Por defecto 150. */
  version?: number;
  /** Trazabilidad local; no se envía en el SOAP. */
  facturaElectronicaId?: string;
}

export interface EventoCancelacionRespuestaParsed {
  /** true si la SET registró el evento (dCodRes 0600). */
  eventoRegistrado: boolean;
  dCodRes: string | null;
  dMsgRes: string | null;
  dFecProc: string | null;
  httpStatus: number;
  soapFault: boolean;
  faultString: string | null;
  cuerpoSoapCrudo: string;
}

function generarDId(): number {
  const mod = BigInt("999999999999999");
  let n = Number(BigInt(Date.now()) % mod);
  if (!Number.isFinite(n) || n < 1) n = 1;
  return n;
}

/** Normaliza CDC: solo dígitos; debe quedar en 44. */
export function normalizarCdcParaEvento(cdcRaw: string): string {
  const cdc = String(cdcRaw ?? "").replace(/\D/g, "");
  if (cdc.length !== 44) {
    throw new Error(`CDC inválido para evento de cancelación: se esperaban 44 dígitos y vinieron ${cdc.length}.`);
  }
  return cdc;
}

/** Valida y recorta el motivo al rango exigido por el XSD (mOtEve: 5–500). */
export function normalizarMotivoEvento(motivoRaw: string): string {
  const m = String(motivoRaw ?? "").trim();
  if (m.length < 5) {
    throw new Error("El motivo de cancelación debe tener al menos 5 caracteres (requerido por SET).");
  }
  if (m.length > 500) {
    throw new Error("El motivo de cancelación no puede superar 500 caracteres (requerido por SET).");
  }
  return m;
}

/**
 * Construye el `rEnviEventoDe` SIN firmar (sin saltos de línea entre nodos, igual criterio que el rDE).
 * Se firma el documento completo para que el contexto de namespaces coincida con el de la SET.
 */
export function buildEventoCancelacionREnviXml(opts: {
  cdc: string;
  motivo: string;
  dId: number;
  dFecFirma: string;
  version?: number;
}): string {
  const cdc = normalizarCdcParaEvento(opts.cdc);
  const motivo = normalizarMotivoEvento(opts.motivo);
  const version = opts.version ?? 150;

  const rEve =
    `<rEve Id="1">` +
    `<dFecFirma>${escapeXml(opts.dFecFirma)}</dFecFirma>` +
    `<dVerFor>${escapeXml(String(version))}</dVerFor>` +
    `<gGroupTiEvt>` +
    `<rGeVeCan>` +
    `<Id>${escapeXml(cdc)}</Id>` +
    `<mOtEve>${escapeXml(motivo)}</mOtEve>` +
    `</rGeVeCan>` +
    `</gGroupTiEvt>` +
    `</rEve>`;

  return (
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<rEnviEventoDe xmlns="${SIFEN_NS}">` +
    `<dId>${opts.dId}</dId>` +
    `<dEvReg>` +
    `<gGroupGesEve xmlns:xsi="${XMLNS_XSI}" xsi:schemaLocation="${escapeXml(EVENTO_XSI_SCHEMA_LOCATION)}">` +
    `<rGesEve>` +
    rEve +
    `</rGesEve>` +
    `</gGroupGesEve>` +
    `</dEvReg>` +
    `</rEnviEventoDe>`
  );
}

function stripXmlDeclaration(xml: string): string {
  return xml.replace(/^﻿?/, "").replace(/^<\?xml[^?]*\?>\s*/i, "").trim();
}

/** Envuelve el `rEnviEventoDe` firmado en el envelope SOAP 1.2 (prefijo env:). */
function construirSoapRecepEvento(rEnviEventoFirmado: string): string {
  const inner = stripXmlDeclaration(rEnviEventoFirmado);
  return (
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<env:Envelope xmlns:env="${SOAP_ENV}">` +
    `<env:Header/>` +
    `<env:Body>` +
    inner +
    `</env:Body>` +
    `</env:Envelope>`
  );
}

/** Extrae texto de un elemento hoja en respuesta SOAP (prefijo opcional). */
function extraerTextoElemento(xml: string, local: string): string | null {
  const re = new RegExp(
    `<(?:[^\\s/>:]+:)?${local}\\b[^>]*>([\\s\\S]*?)</(?:[^\\s/>:]+:)?${local}\\b[^>]*>`,
    "i"
  );
  const m = xml.match(re);
  if (!m?.[1]) return null;
  const inner = m[1].replace(/<[^>]+>/g, "").trim();
  return inner.length > 0 ? inner : null;
}

function parsearRespuestaEvento(xml: string, httpStatus: number): EventoCancelacionRespuestaParsed {
  const soapFault = /<(?:[^\s/>:]+:)?Fault\b/i.test(xml) || /<faultstring>/i.test(xml);
  if (soapFault) {
    return {
      eventoRegistrado: false,
      dCodRes: null,
      dMsgRes: null,
      dFecProc: extraerTextoElemento(xml, "dFecProc"),
      httpStatus,
      soapFault: true,
      faultString: extraerTextoElemento(xml, "faultstring") ?? "Respuesta SOAP con Fault",
      cuerpoSoapCrudo: xml,
    };
  }

  const dCodRes = extraerTextoElemento(xml, "dCodRes");
  const code = (dCodRes ?? "").trim();
  return {
    eventoRegistrado: code === COD_EVENTO_OK,
    dCodRes,
    dMsgRes: extraerTextoElemento(xml, "dMsgRes"),
    dFecProc: extraerTextoElemento(xml, "dFecProc"),
    httpStatus,
    soapFault: false,
    faultString: null,
    cuerpoSoapCrudo: xml,
  };
}

function postHttpsMtls(
  urlStr: string,
  body: string,
  certPem: string,
  keyPem: string,
  contentType: string
): Promise<{ status: number; body: string }> {
  const url = new URL(urlStr);
  const port = url.port ? Number(url.port) : 443;

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: url.hostname,
        port,
        path: `${url.pathname}${url.search}`,
        method: "POST",
        cert: certPem,
        key: keyPem,
        rejectUnauthorized: true,
        headers: {
          "Content-Type": contentType,
          "Content-Length": Buffer.byteLength(body, "utf8"),
        },
      },
      (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (ch) => chunks.push(ch as Buffer));
        res.on("end", () => {
          resolve({
            status: res.statusCode ?? 0,
            body: Buffer.concat(chunks).toString("utf8"),
          });
        });
      }
    );
    req.on("error", reject);
    req.write(body, "utf8");
    req.end();
  });
}

/**
 * Construye, firma y transmite el Evento de Cancelación a SIFEN (test | producción).
 * mTLS + firma con el mismo .p12 que firma el DE.
 */
export async function enviarEventoCancelacionSifen(
  params: EnviarEventoCancelacionParams
): Promise<EventoCancelacionRespuestaParsed> {
  const ambiente: AmbienteSifen = params.empresaConfig.ambiente ?? "test";
  if (ambiente !== "test" && ambiente !== "produccion") {
    throw new Error('ambiente debe ser "test" o "produccion".');
  }

  const cdc = normalizarCdcParaEvento(params.cdc);
  const motivo = normalizarMotivoEvento(params.motivo);
  const dId = params.dId ?? generarDId();
  const dFecFirma = sifenFechaFirmaEventoAhora();

  const rEnviXml = buildEventoCancelacionREnviXml({
    cdc,
    motivo,
    dId,
    dFecFirma,
    version: params.version,
  });

  const { privateKeyPem, certificatePem } = extractKeyAndCertFromP12(
    params.empresaConfig.certificadoP12,
    params.empresaConfig.certificadoPassword
  );

  const firmado = signSifenEventoCancelacionXml(rEnviXml, {
    privateKeyPem,
    certificatePem,
  });

  const soap = construirSoapRecepEvento(firmado);
  const serviceUrl = urlRecibeEvento(ambiente);

  let httpStatus: number;
  let cuerpo: string;
  try {
    const res = await postHttpsMtls(
      serviceUrl,
      soap,
      certificatePem,
      privateKeyPem,
      CONTENT_TYPE_RECEP_EVENTO
    );
    httpStatus = res.status;
    cuerpo = res.body;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const label = ambiente === "produccion" ? "SIFEN producción" : "SIFEN TEST";
    throw new Error(`Fallo HTTPS/mTLS contra ${label} (recibe-evento): ${msg}`);
  }

  return parsearRespuestaEvento(cuerpo, httpStatus);
}
