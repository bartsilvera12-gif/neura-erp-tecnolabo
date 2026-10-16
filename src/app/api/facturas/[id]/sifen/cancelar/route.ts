import { NextRequest, NextResponse } from "next/server";
import { getFacturasSupabaseFromAuth } from "@/lib/facturacion/facturas-service-client";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { toFacturaElectronicaDto } from "@/lib/sifen/to-factura-electronica-dto";
import {
  buildSifenCancelacionPreview,
  normalizePlazoCancelacionHoras,
} from "@/lib/sifen/sifen-cancelacion-rules";
import { decryptSecret } from "@/lib/sifen/security";
import { downloadSifenCertificadoObject } from "@/lib/sifen/sifen-certificados-storage";
import {
  enviarEventoCancelacionSifen,
  type EventoCancelacionRespuestaParsed,
} from "@/lib/sifen/evento-cancelacion-sifen";
import type { AmbienteSifen, FacturaElectronicaDTO } from "@/lib/sifen/types";

function trimMotivo(raw: unknown): string | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  return s.length > 0 ? s : null;
}

function parseAmbiente(raw: string): AmbienteSifen | null {
  if (raw === "test" || raw === "produccion") return raw;
  return null;
}

/** Resumen de la respuesta SET para persistir en el evento (traza). */
function respuestaEventoJson(r: EventoCancelacionRespuestaParsed): Record<string, unknown> {
  return {
    eventoRegistrado: r.eventoRegistrado,
    dCodRes: r.dCodRes,
    dMsgRes: r.dMsgRes,
    dFecProc: r.dFecProc,
    httpStatus: r.httpStatus,
    soapFault: r.soapFault,
    faultString: r.faultString,
  };
}

/** Mensaje de error legible a partir de la respuesta SET rechazada. */
function mensajeEventoRechazado(r: EventoCancelacionRespuestaParsed): string {
  if (r.soapFault) {
    return `SET rechazó el evento de cancelación (SOAP Fault): ${r.faultString ?? "sin detalle"}.`;
  }
  const partes = [r.dMsgRes, r.dCodRes ? `Código ${r.dCodRes}` : null, `HTTP ${r.httpStatus}`]
    .filter(Boolean)
    .join(" — ");
  return `La SET no registró la cancelación del DE. ${partes || "Respuesta inesperada de recibe-evento."}`;
}

/**
 * POST /api/facturas/[id]/sifen/cancelar
 *
 * Envía el Evento de Cancelación a SIFEN/SET (siRecepEvento). Solo si la SET lo registra
 * (dCodRes 0600) se aplica la cancelación lógica en el ERP (estado 'cancelado' + factura
 * 'Anulado'). Si la SET rechaza o hay fallo de transmisión, NO se cambia el estado: el DE
 * seguiría activo en la SET y marcarlo cancelado solo en el ERP reproduciría el desfase
 * que este flujo corrige.
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const ctx = await getFacturasSupabaseFromAuth(request);
    if (!ctx) {
      return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    }
    const { auth, supabase } = ctx;

    const { id } = await params;
    const fid = id?.trim();
    if (!fid) {
      return NextResponse.json(errorResponse("id de factura es obligatorio"), { status: 400 });
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(errorResponse("Cuerpo JSON inválido"), { status: 400 });
    }
    const b = body != null && typeof body === "object" ? (body as Record<string, unknown>) : {};
    const motivo = trimMotivo(b.motivo);
    if (motivo == null || motivo.length < 5) {
      return NextResponse.json(
        errorResponse("motivo es obligatorio (mínimo 5 caracteres) para registrar la cancelación."),
        { status: 400 }
      );
    }
    // mOtEve (XSD de eventos) admite hasta 500 caracteres; el evento a SET no acepta más.
    if (motivo.length > 500) {
      return NextResponse.json(
        errorResponse("motivo no puede superar 500 caracteres (requerido por SET)."),
        { status: 400 }
      );
    }

    const { data: factura, error: errF } = await supabase
      .from("facturas")
      .select("id, empresa_id")
      .eq("id", fid)
      .eq("empresa_id", auth.empresa_id)
      .maybeSingle();

    if (errF) {
      return NextResponse.json(errorResponse(errF.message), { status: 400 });
    }
    if (!factura) {
      return NextResponse.json(errorResponse("Factura no encontrada"), { status: 404 });
    }

    const [{ data: cfg }, { data: feRow }, pagosRes] = await Promise.all([
      supabase
        .from("empresa_sifen_config")
        .select(
          "sifen_plazo_cancelacion_horas, ambiente, activo, certificado_path, certificado_password_encrypted"
        )
        .eq("empresa_id", auth.empresa_id)
        .maybeSingle(),
      supabase
        .from("factura_electronica")
        .select("*")
        .eq("factura_id", fid)
        .eq("empresa_id", auth.empresa_id)
        .maybeSingle(),
      supabase
        .from("pagos")
        .select("id", { count: "exact", head: true })
        .eq("factura_id", fid)
        .eq("empresa_id", auth.empresa_id),
    ]);

    if (pagosRes.error) {
      return NextResponse.json(errorResponse(pagosRes.error.message), { status: 400 });
    }
    const pagosCount = pagosRes.count ?? 0;

    if (!feRow) {
      return NextResponse.json(
        errorResponse("No hay documento electrónico asociado a esta factura."),
        { status: 409 }
      );
    }

    const plazo = normalizePlazoCancelacionHoras(
      cfg != null ? (cfg as { sifen_plazo_cancelacion_horas?: unknown }).sifen_plazo_cancelacion_horas : 48
    );

    const feDto = toFacturaElectronicaDto(feRow as Record<string, unknown>);
    const preview = buildSifenCancelacionPreview({
      estadoSifen: feDto.estado_sifen,
      sifenAprobadoAtIso: feDto.sifen_aprobado_at,
      sifenCanceladoAtIso: feDto.sifen_cancelado_at,
      plazoHoras: plazo,
      pagosCount,
      nowMs: Date.now(),
    });

    if (!preview.puede_cancelar) {
      return NextResponse.json(
        errorResponse(preview.motivo_bloqueo ?? "No se puede cancelar el documento electrónico."),
        { status: 409 }
      );
    }

    // ── A partir de acá, el DE está aprobado y dentro de la ventana: corresponde el
    //    Evento de Cancelación REAL a la SET (no la cancelación lógica suelta). ──

    const cdc = feDto.cdc == null ? "" : String(feDto.cdc).trim();
    if (!cdc) {
      return NextResponse.json(
        errorResponse("El documento electrónico no tiene CDC; no se puede enviar el evento de cancelación a la SET."),
        { status: 409 }
      );
    }

    if (!cfg) {
      return NextResponse.json(errorResponse("No hay configuración SIFEN para esta empresa."), { status: 400 });
    }
    const cfgRow = cfg as {
      ambiente?: unknown;
      activo?: unknown;
      certificado_path?: unknown;
      certificado_password_encrypted?: unknown;
    };
    if (!cfgRow.activo) {
      return NextResponse.json(
        errorResponse("La configuración SIFEN está inactiva. Actívela antes de cancelar en la SET."),
        { status: 400 }
      );
    }
    const ambiente = parseAmbiente(String(cfgRow.ambiente ?? ""));
    if (!ambiente) {
      return NextResponse.json(
        errorResponse('Ambiente SIFEN inválido en configuración (use "test" o "produccion").'),
        { status: 400 }
      );
    }
    const certPath = cfgRow.certificado_path == null ? "" : String(cfgRow.certificado_path).trim();
    if (!certPath) {
      return NextResponse.json(
        errorResponse("No hay certificado en storage. Suba el .p12 en configuración SIFEN."),
        { status: 400 }
      );
    }
    const encPwd = cfgRow.certificado_password_encrypted;
    if (encPwd == null || String(encPwd).trim() === "") {
      return NextResponse.json(
        errorResponse("Falta la contraseña del certificado cifrada en configuración SIFEN."),
        { status: 400 }
      );
    }

    let p12Password: string;
    try {
      p12Password = decryptSecret(String(encPwd));
    } catch (e) {
      const m = e instanceof Error ? e.message : "Error al descifrar la contraseña del certificado";
      return NextResponse.json(errorResponse(m), { status: 500 });
    }

    const p12Dl = await downloadSifenCertificadoObject(supabase, certPath);
    if (!p12Dl.ok) {
      return NextResponse.json(
        errorResponse(`No se pudo descargar el certificado .p12: ${p12Dl.message}`),
        { status: 500 }
      );
    }

    // ── Transmisión del evento a la SET ──
    let evento: EventoCancelacionRespuestaParsed;
    try {
      evento = await enviarEventoCancelacionSifen({
        cdc,
        motivo,
        empresaConfig: {
          ambiente,
          certificadoP12: p12Dl.data,
          certificadoPassword: p12Password,
        },
        facturaElectronicaId: feDto.id,
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      // Fallo de transmisión: dejamos traza (best-effort) y NO cambiamos el estado.
      await supabase.from("factura_electronica_evento").insert({
        empresa_id: auth.empresa_id,
        factura_electronica_id: feDto.id,
        tipo: "cancelacion",
        detalle: {
          origen: "api_cancelar_set",
          factura_id: fid,
          cdc,
          motivo,
          ok: false,
          error: msg,
          intentado_en: new Date().toISOString(),
        },
      });
      return NextResponse.json(errorResponse(`No se pudo transmitir el evento a la SET: ${msg}`), {
        status: 502,
      });
    }

    if (!evento.eventoRegistrado) {
      // SET rechazó: traza del rechazo, sin tocar el estado (el DE sigue activo en la SET).
      await supabase.from("factura_electronica_evento").insert({
        empresa_id: auth.empresa_id,
        factura_electronica_id: feDto.id,
        tipo: "cancelacion",
        detalle: {
          origen: "api_cancelar_set",
          factura_id: fid,
          cdc,
          motivo,
          ok: false,
          set: respuestaEventoJson(evento),
          intentado_en: new Date().toISOString(),
        },
      });
      return NextResponse.json(errorResponse(mensajeEventoRechazado(evento)), { status: 409 });
    }

    // ── SET registró el evento (0600): recién ahora se aplica la cancelación en el ERP. ──
    const canceladoEn = new Date().toISOString();

    const { data: updatedFe, error: errUp } = await supabase
      .from("factura_electronica")
      .update({
        estado_sifen: "cancelado",
        sifen_cancelado_at: canceladoEn,
        sifen_cancelacion_motivo: motivo,
      })
      .eq("id", feDto.id)
      .eq("empresa_id", auth.empresa_id)
      .select()
      .single();

    if (errUp || !updatedFe) {
      return NextResponse.json(
        errorResponse(errUp?.message ?? "No se pudo actualizar factura_electronica."),
        { status: 500 }
      );
    }

    const { data: evInsert, error: errEv } = await supabase
      .from("factura_electronica_evento")
      .insert({
        empresa_id: auth.empresa_id,
        factura_electronica_id: feDto.id,
        tipo: "cancelacion",
        detalle: {
          origen: "api_cancelar_set",
          factura_id: fid,
          cdc,
          motivo,
          ok: true,
          set: respuestaEventoJson(evento),
          cancelado_en: canceladoEn,
        },
      })
      .select("id")
      .single();

    if (errEv || !evInsert) {
      await supabase
        .from("factura_electronica")
        .update({
          estado_sifen: feDto.estado_sifen,
          sifen_cancelado_at: feDto.sifen_cancelado_at,
          sifen_cancelacion_motivo: feDto.sifen_cancelacion_motivo,
        })
        .eq("id", feDto.id)
        .eq("empresa_id", auth.empresa_id);
      return NextResponse.json(
        errorResponse(
          `La SET registró la cancelación pero no se pudo guardar la traza del evento; se revirtió el estado local: ${errEv?.message ?? "error"}. Reintente para sincronizar el ERP.`
        ),
        { status: 500 }
      );
    }

    const { error: errFactura } = await supabase
      .from("facturas")
      .update({ estado: "Anulado", saldo: 0 })
      .eq("id", fid)
      .eq("empresa_id", auth.empresa_id);

    if (errFactura) {
      await supabase
        .from("factura_electronica")
        .update({
          estado_sifen: feDto.estado_sifen,
          sifen_cancelado_at: feDto.sifen_cancelado_at,
          sifen_cancelacion_motivo: feDto.sifen_cancelacion_motivo,
        })
        .eq("id", feDto.id)
        .eq("empresa_id", auth.empresa_id);
      await supabase.from("factura_electronica_evento").delete().eq("id", (evInsert as { id: string }).id);
      return NextResponse.json(
        errorResponse(
          `La SET registró la cancelación pero no se pudo anular la factura comercial (${errFactura.message}); se revirtió el estado local. Reintente para sincronizar el ERP.`
        ),
        { status: 500 }
      );
    }

    const dto = toFacturaElectronicaDto(updatedFe as Record<string, unknown>);
    const data: {
      factura_electronica: FacturaElectronicaDTO;
      evento_set: ReturnType<typeof respuestaEventoJson>;
    } = {
      factura_electronica: dto,
      evento_set: respuestaEventoJson(evento),
    };

    return NextResponse.json(successResponse(data));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
