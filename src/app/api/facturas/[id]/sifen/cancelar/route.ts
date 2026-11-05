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
import { enviarEventoCancelacionSifen } from "@/lib/sifen/evento-cancelacion-sifen";
import type { AmbienteSifen, FacturaElectronicaDTO } from "@/lib/sifen/types";

function trimMotivo(raw: unknown): string | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  return s.length > 0 ? s : null;
}

function parseAmbiente(raw: unknown): AmbienteSifen | null {
  const s = String(raw ?? "");
  return s === "test" || s === "produccion" ? s : null;
}

/**
 * POST /api/facturas/[id]/sifen/cancelar
 *
 * Cancela el DE en SIFEN enviando el **evento de cancelación** al SET (siRecepEvento)
 * y espera su aceptación. SOLO si el SET aprueba el evento (dEstRes "Aprobado" /
 * dCodRes "0600") se marca el documento como cancelado y la factura como anulada.
 * Si el SET rechaza, no se anula nada y se devuelve el motivo del rechazo.
 *
 * (Antes este endpoint hacía solo una "cancelación lógica" local sin avisar al SET,
 * por lo que el ERP decía "anulada" pero en SIFEN seguía vigente.)
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
    // mOtEve del SET admite hasta 500 caracteres.
    if (motivo.length > 500) {
      return NextResponse.json(errorResponse("motivo no puede superar 500 caracteres."), { status: 400 });
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

    const [{ data: cfg, error: errCfg }, { data: feRow }, pagosRes] = await Promise.all([
      supabase
        .from("empresa_sifen_config")
        .select("ambiente, activo, certificado_path, certificado_password_encrypted, sifen_plazo_cancelacion_horas")
        .eq("empresa_id", auth.empresa_id)
        .maybeSingle(),
      supabase.from("factura_electronica").select("*").eq("factura_id", fid).eq("empresa_id", auth.empresa_id).maybeSingle(),
      supabase
        .from("pagos")
        .select("id", { count: "exact", head: true })
        .eq("factura_id", fid)
        .eq("empresa_id", auth.empresa_id),
    ]);

    if (errCfg) {
      return NextResponse.json(errorResponse(errCfg.message), { status: 400 });
    }
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
    if (!cfg) {
      return NextResponse.json(errorResponse("No hay configuración SIFEN para esta empresa."), { status: 400 });
    }

    const feDto = toFacturaElectronicaDto(feRow as Record<string, unknown>);

    // Solo se puede cancelar en SIFEN un documento efectivamente APROBADO.
    if (feDto.estado_sifen !== "aprobado") {
      return NextResponse.json(
        errorResponse(
          `Solo se puede cancelar en SIFEN un documento aprobado. Estado actual: "${feDto.estado_sifen}".`
        ),
        { status: 409 }
      );
    }

    const cdc = (feRow as { cdc?: unknown }).cdc == null ? "" : String((feRow as { cdc?: unknown }).cdc).trim();
    if (!/^\d{44}$/.test(cdc)) {
      return NextResponse.json(
        errorResponse("El documento no tiene un CDC válido (44 dígitos); no se puede cancelar en SIFEN."),
        { status: 409 }
      );
    }

    const plazo = normalizePlazoCancelacionHoras(
      (cfg as { sifen_plazo_cancelacion_horas?: unknown }).sifen_plazo_cancelacion_horas
    );

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

    // ── Preparar firma/envío a SET ──────────────────────────────────────────
    const ambiente = parseAmbiente((cfg as { ambiente?: unknown }).ambiente);
    if (!ambiente) {
      return NextResponse.json(
        errorResponse('Ambiente SIFEN inválido en configuración (use "test" o "produccion").'),
        { status: 400 }
      );
    }
    if (!(cfg as { activo?: unknown }).activo) {
      return NextResponse.json(
        errorResponse("La configuración SIFEN está inactiva. Actívela antes de cancelar."),
        { status: 400 }
      );
    }
    const certPath = (cfg as { certificado_path?: unknown }).certificado_path;
    const certPathStr = certPath == null ? "" : String(certPath).trim();
    if (!certPathStr) {
      return NextResponse.json(
        errorResponse("No hay certificado en storage. Suba el .p12 en configuración SIFEN."),
        { status: 400 }
      );
    }
    const encPwd = (cfg as { certificado_password_encrypted?: unknown }).certificado_password_encrypted;
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

    const p12Dl = await downloadSifenCertificadoObject(supabase, certPathStr);
    if (!p12Dl.ok) {
      return NextResponse.json(
        errorResponse(`No se pudo descargar el certificado .p12: ${p12Dl.message}`),
        { status: 500 }
      );
    }

    // ── Enviar el evento de cancelación al SET y esperar su respuesta ────────
    let resp;
    try {
      resp = await enviarEventoCancelacionSifen({
        cdc,
        motivo,
        ambiente,
        certificadoP12: p12Dl.data,
        certificadoPassword: p12Password,
      });
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e);
      const label = ambiente === "produccion" ? "SIFEN producción" : "SIFEN TEST";
      return NextResponse.json(
        errorResponse(
          `No se pudo contactar a ${label} para cancelar. La factura NO fue anulada. Detalle: ${m}`
        ),
        { status: 502 }
      );
    }

    const respuestaSet = {
      aprobado: resp.aprobado,
      dEstRes: resp.dEstRes,
      dCodRes: resp.dCodRes,
      dMsgRes: resp.dMsgRes,
      dProtAut: resp.dProtAut,
      dFecProc: resp.dFecProc,
      httpStatus: resp.httpStatus,
    };

    // ── Rechazo del SET: NO se anula nada ───────────────────────────────────
    if (!resp.aprobado) {
      // Traza del intento rechazado (no cambia estado del documento).
      // `tipo` admite solo generacion|envio|respuesta|error|firma|cancelacion (CHECK en BD).
      await supabase.from("factura_electronica_evento").insert({
        empresa_id: auth.empresa_id,
        factura_electronica_id: feDto.id,
        tipo: "error",
        detalle: {
          origen: "api_cancelar",
          evento: "cancelacion_rechazada",
          factura_id: fid,
          motivo,
          respuesta_set: respuestaSet,
        },
      });

      const detalleRechazo =
        [resp.dMsgRes, resp.dCodRes ? `Código ${resp.dCodRes}` : null, resp.dEstRes]
          .filter(Boolean)
          .join(" — ") || "El SET rechazó la cancelación.";
      return NextResponse.json(
        errorResponse(
          `El SET rechazó la cancelación; la factura sigue VIGENTE en SIFEN y NO fue anulada. ${detalleRechazo}`
        ),
        { status: 409 }
      );
    }

    // ── Aprobado por el SET: ahora sí se marca cancelado/anulado ─────────────
    const canceladoEn = resp.dFecProc || new Date().toISOString();

    const { data: updatedFe, error: errUp } = await supabase
      .from("factura_electronica")
      .update({
        estado_sifen: "cancelado",
        sifen_cancelado_at: canceladoEn,
        sifen_cancelacion_motivo: motivo,
        error: null,
      })
      .eq("id", feDto.id)
      .eq("empresa_id", auth.empresa_id)
      .select()
      .single();

    if (errUp || !updatedFe) {
      return NextResponse.json(
        errorResponse(
          `El SET canceló el documento, pero no se pudo actualizar el ERP: ${errUp?.message ?? "error"}. ` +
            "El documento quedó CANCELADO en SIFEN; reintente para sincronizar el estado local."
        ),
        { status: 500 }
      );
    }

    await supabase.from("factura_electronica_evento").insert({
      empresa_id: auth.empresa_id,
      factura_electronica_id: feDto.id,
      tipo: "cancelacion",
      detalle: {
        origen: "api_cancelar",
        factura_id: fid,
        motivo,
        cancelado_en: canceladoEn,
        respuesta_set: respuestaSet,
      },
    });

    const { error: errFactura } = await supabase
      .from("facturas")
      .update({ estado: "Anulado", saldo: 0 })
      .eq("id", fid)
      .eq("empresa_id", auth.empresa_id);

    if (errFactura) {
      // El DE ya está cancelado en SET y en factura_electronica; solo falló la cabecera comercial.
      return NextResponse.json(
        errorResponse(
          `El documento fue cancelado en SIFEN, pero no se pudo anular la factura comercial: ${errFactura.message}. ` +
            "Anúlela manualmente para dejarla consistente."
        ),
        { status: 500 }
      );
    }

    const dto = toFacturaElectronicaDto(updatedFe as Record<string, unknown>);
    const data: { factura_electronica: FacturaElectronicaDTO; respuesta_set: typeof respuestaSet } = {
      factura_electronica: dto,
      respuesta_set: respuestaSet,
    };

    return NextResponse.json(successResponse(data));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
