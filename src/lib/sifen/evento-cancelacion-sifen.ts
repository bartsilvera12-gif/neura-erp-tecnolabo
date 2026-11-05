/**
 * Evento de cancelación SIFEN (siRecepEvento, síncrono).
 *
 * Cancela en el SET un DE ya aprobado: arma el XML del evento (gGroupGesEve →
 * rGesEve → rEve → gGroupTiEvt → rGeVeCan con el CDC y el motivo), lo FIRMA
 * (sobre `rEve`, igual perfil que el DE), lo envía por SOAP con TLS mutuo al
 * endpoint de eventos, y parsea la respuesta.
 *
 * Fuente: Manual Técnico SIFEN v150 §9.5 (siRecepEvento) + schema
 * siRecepEvento_v150.xsd / resRecepEvento_v150.xsd, y librería de referencia
 * facturacionelectronicapy-xmlgen/xmlsign/setapi (TIPS S.A.).
 *
 * dCodRes "0600" / dEstRes "Aprobado" = evento registrado. Cualquier otra cosa =
 * NO cancelado (fail-safe: el caller nunca marca cancelado si no hay aprobación).
 */
import type { AmbienteSifen } from "./types";
import { extractKeyAndCertFromP12, signSifenEventoXml } from "./sign-xml";
import { sifenFechaFirmaEvento } from "./rde-xml";
import { urlRecepEvento } from "./sifen-ws-urls";
import { SIFEN_EKUATIA_TARGET_NS } from "./sifen-xsi-schema-location";
import { postHttpsMtls } from "./enviar-lote-sifen-test";
import { escapeXml } from "./xml";

const SIFEN_NS = SIFEN_EKUATIA_TARGET_NS;
const XMLNS_XSI = "http://www.w3.org/2001/XMLSchema-instance";
const SOAP_ENV = "http://www.w3.org/2003/05/soap-envelope";
/** Archivo del schema (relativo): SET rechaza (0160) si va una URL https al XSD. */
const EVENTO_SCHEMA_FILE = "siRecepEvento_v150.xsd";
const CONTENT_TYPE_EVENTO = "application/xml; charset=utf-8";

export interface EnviarEventoCancelacionParams {
  /** CDC (44 dígitos) del DE aprobado que se cancela. */
  cdc: string;
  /** Motivo de la cancelación (5–500 caracteres). */
  motivo: string;
  ambiente: AmbienteSifen;
  certificadoP12: Buffer;
  certificadoPassword: string;
  /** dId (identificador de control de envío). Si no se indica, se genera. */
  dId?: number;
}

export interface EventoCancelacionRespuesta {
  /** true SOLO si el SET aprobó el evento (dEstRes "Aprobado*" o dCodRes "0600"). */
  aprobado: boolean;
  dEstRes: string | null;
  dCodRes: string | null;
  dMsgRes: string | null;
  dProtAut: string | null;
  dFecProc: string | null;
  httpStatus: number;
  cuerpoSoapCrudo: string;
}

function generarDId(): number {
  const mod = BigInt("999999999999999");
  let n = Number(BigInt(Date.now()) % mod);
  if (!Number.isFinite(n) || n < 1) n = 1;
  return n;
}

/** Extrae el texto de un elemento hoja de la respuesta SOAP (prefijo de NS opcional). */
function extraerTexto(xml: string, local: string): string | null {
  const re = new RegExp(
    `<(?:[^\\s/>:]+:)?${local}\\b[^>]*>([\\s\\S]*?)</(?:[^\\s/>:]+:)?${local}\\b[^>]*>`,
    "i"
  );
  const m = xml.match(re);
  if (!m?.[1]) return null;
  const inner = m[1].replace(/<[^>]+>/g, "").trim();
  return inner.length > 0 ? inner : null;
}

/**
 * XML del evento (SIN firmar) dentro del wrapper `rEnviEventoDe`. Se firma `rEve`
 * dentro de este documento (así `rEve` canoniza con el namespace e-kuatia en scope).
 */
function construirEventoRequestFirmable(dId: number, cdc: string, motivo: string, dFecFirma: string): string {
  return (
    `<rEnviEventoDe xmlns="${SIFEN_NS}" xmlns:xsi="${XMLNS_XSI}">` +
    `<dId>${dId}</dId>` +
    `<dEvReg>` +
    `<gGroupGesEve>` +
    `<rGesEve xsi:schemaLocation="${SIFEN_NS} ${EVENTO_SCHEMA_FILE}" xmlns:xsi="${XMLNS_XSI}">` +
    `<rEve Id="1">` +
    `<dFecFirma>${dFecFirma}</dFecFirma>` +
    `<dVerFor>150</dVerFor>` +
    `<gGroupTiEvt>` +
    `<rGeVeCan>` +
    `<Id>${escapeXml(cdc)}</Id>` +
    `<mOtEve>${escapeXml(motivo)}</mOtEve>` +
    `</rGeVeCan>` +
    `</gGroupTiEvt>` +
    `</rEve>` +
    `</rGesEve>` +
    `</gGroupGesEve>` +
    `</dEvReg>` +
    `</rEnviEventoDe>`
  );
}

function stripXmlDeclaration(xml: string): string {
  return xml.replace(/^﻿?/, "").replace(/^<\?xml[^?]*\?>\s*/i, "").trim();
}

function construirSoapEvento(rEnviEventoDeFirmado: string): string {
  return (
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<env:Envelope xmlns:env="${SOAP_ENV}">` +
    `<env:Header/>` +
    `<env:Body>` +
    `${stripXmlDeclaration(rEnviEventoDeFirmado)}` +
    `</env:Body>` +
    `</env:Envelope>`
  );
}

/**
 * Envía un evento de cancelación a SIFEN (TEST o producción según `ambiente`).
 * mTLS con el mismo .p12 que firma los DE.
 */
export async function enviarEventoCancelacionSifen(
  params: EnviarEventoCancelacionParams
): Promise<EventoCancelacionRespuesta> {
  const { ambiente } = params;
  if (ambiente !== "test" && ambiente !== "produccion") {
    throw new Error('ambiente debe ser "test" o "produccion".');
  }
  const cdc = (params.cdc ?? "").replace(/\s/g, "").trim();
  if (!/^\d{44}$/.test(cdc)) {
    throw new Error("CDC inválido para el evento de cancelación (se esperan 44 dígitos).");
  }
  const motivo = (params.motivo ?? "").trim();
  if (motivo.length < 5 || motivo.length > 500) {
    throw new Error("El motivo de cancelación debe tener entre 5 y 500 caracteres.");
  }

  const dId = params.dId ?? generarDId();
  const dFecFirma = sifenFechaFirmaEvento();

  const material = extractKeyAndCertFromP12(params.certificadoP12, params.certificadoPassword);
  const sinFirmar = construirEventoRequestFirmable(dId, cdc, motivo, dFecFirma);
  const firmado = signSifenEventoXml(sinFirmar, material);
  const soap = construirSoapEvento(firmado);

  const url = urlRecepEvento(ambiente);
  let httpStatus: number;
  let cuerpo: string;
  try {
    const res = await postHttpsMtls(url, soap, material.certificatePem, material.privateKeyPem, CONTENT_TYPE_EVENTO);
    httpStatus = res.status;
    cuerpo = res.body;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const label = ambiente === "produccion" ? "SIFEN producción" : "SIFEN TEST";
    throw new Error(`Fallo HTTPS/mTLS contra ${label} (eventos): ${msg}`);
  }

  const dEstRes = extraerTexto(cuerpo, "dEstRes");
  const dCodRes = extraerTexto(cuerpo, "dCodRes");
  const dMsgRes = extraerTexto(cuerpo, "dMsgRes");
  const dProtAut = extraerTexto(cuerpo, "dProtAut");
  const dFecProc = extraerTexto(cuerpo, "dFecProc");

  const estadoAprobado = (dEstRes ?? "").toLowerCase().startsWith("aprobado");
  const codigoOk = (dCodRes ?? "").trim() === "0600";
  const http2xx = httpStatus >= 200 && httpStatus < 300;
  const aprobado = http2xx && (estadoAprobado || codigoOk);

  return {
    aprobado,
    dEstRes,
    dCodRes,
    dMsgRes,
    dProtAut,
    dFecProc,
    httpStatus,
    cuerpoSoapCrudo: cuerpo,
  };
}
