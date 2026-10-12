import { NextRequest, NextResponse } from "next/server";
import { getFacturasSupabaseFromAuth } from "@/lib/facturacion/facturas-service-client";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { downloadSifenObject } from "@/lib/sifen/sifen-storage";
import { buildKudePdfBuffer } from "@/lib/sifen/kude-pdf";
import {
  kudeFallbackQrUrl,
  parseKudeFromSignedRdeXml,
} from "@/lib/sifen/parse-kude-from-signed-xml";
import {
  dProtAutDesdeConsulta,
  loadKudeBranding,
  nombreArchivoKude,
} from "@/lib/sifen/kude-route-helpers";
import type { SifenConsultaLoteUltimaPersistida } from "@/lib/sifen/types";

/**
 * GET /api/notas-credito/[id]/sifen/kude
 * PDF KuDE (representación gráfica) de la nota de crédito electrónica, armado
 * desde el XML firmado. Solo disponible con `estado_sifen` = aprobado.
 * Mismo renderer que la factura; solo cambia el rótulo "Tipo de documento".
 * Query: `download=1` → Content-Disposition attachment.
 */
export async function GET(
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
    const nid = id?.trim();
    if (!nid) {
      return NextResponse.json(errorResponse("id de nota de crédito es obligatorio"), { status: 400 });
    }

    const download = request.nextUrl.searchParams.get("download") === "1";

    const { data: nc, error: errNc } = await supabase
      .from("nota_credito")
      .select("id")
      .eq("id", nid)
      .eq("empresa_id", auth.empresa_id)
      .maybeSingle();

    if (errNc) {
      return NextResponse.json(errorResponse(errNc.message), { status: 400 });
    }
    if (!nc) {
      return NextResponse.json(errorResponse("Nota de crédito no encontrada."), { status: 404 });
    }

    const { data: neRow, error: errNe } = await supabase
      .from("nota_credito_electronica")
      .select("estado_sifen, xml_firmado_path, cdc, sifen_ultima_respuesta_consulta_lote")
      .eq("nota_credito_id", nid)
      .eq("empresa_id", auth.empresa_id)
      .maybeSingle();

    if (errNe) {
      return NextResponse.json(errorResponse(errNe.message), { status: 400 });
    }
    if (!neRow) {
      return NextResponse.json(
        errorResponse("No hay documento electrónico para esta nota de crédito."),
        { status: 404 }
      );
    }

    if (String(neRow.estado_sifen) !== "aprobado") {
      return NextResponse.json(
        errorResponse("El KuDE solo está disponible con SIFEN en estado «aprobado»."),
        { status: 403 }
      );
    }

    const xmlPath =
      neRow.xml_firmado_path == null ? "" : String(neRow.xml_firmado_path).trim();
    if (!xmlPath) {
      return NextResponse.json(errorResponse("No hay XML firmado en storage."), { status: 400 });
    }

    const dl = await downloadSifenObject(supabase, xmlPath);
    if (!dl.ok) {
      return NextResponse.json(
        errorResponse(`No se pudo descargar el XML firmado: ${dl.message}`),
        { status: 500 }
      );
    }

    let parsed;
    try {
      parsed = parseKudeFromSignedRdeXml(dl.data.toString("utf8"));
    } catch (e) {
      const m = e instanceof Error ? e.message : "Error al leer el XML";
      return NextResponse.json(errorResponse(`XML firmado inválido: ${m}`), { status: 500 });
    }

    const cdcBd = neRow.cdc == null ? "" : String(neRow.cdc).trim();
    if (cdcBd && cdcBd !== parsed.cdc) {
      return NextResponse.json(
        errorResponse("Inconsistencia CDC: re-genere y firme el XML o contacte soporte."),
        { status: 409 }
      );
    }

    const consultaRaw = neRow.sifen_ultima_respuesta_consulta_lote as
      | SifenConsultaLoteUltimaPersistida
      | Record<string, unknown>
      | null
      | undefined;
    const dProtAut = dProtAutDesdeConsulta(parsed.cdc, consultaRaw ?? null);

    const qrUrl = parsed.dCarQR ?? kudeFallbackQrUrl(parsed.cdc);

    const branding = await loadKudeBranding(supabase, auth.empresa_id).catch((e) => {
      console.warn("[kude-nc] branding load failed, using default", {
        empresa_id: auth.empresa_id,
        error: e instanceof Error ? e.message : String(e),
      });
      return null;
    });

    // Número legal de la propia NC (establecimiento-punto-documento), leído del rDE firmado.
    const numeroLegal = `${parsed.timbrado.dEst}-${parsed.timbrado.dPunExp}-${parsed.timbrado.dNumDoc}`;

    let pdf: Buffer;
    try {
      pdf = await buildKudePdfBuffer({
        parsed,
        numeroFactura: numeroLegal,
        dProtAut,
        qrUrl,
        branding,
        tipoDocumentoLabel: "Nota de crédito electrónica",
      });
    } catch (e) {
      const m = e instanceof Error ? e.message : "Error al generar PDF";
      return NextResponse.json(errorResponse(m), { status: 500 });
    }

    const fname = nombreArchivoKude(numeroLegal, parsed.cdc, "nota-credito");
    const disp = download ? `attachment; filename="${fname}"` : `inline; filename="${fname}"`;

    return new NextResponse(new Uint8Array(pdf), {
      status: 200,
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": disp,
        "Cache-Control": "private, no-store",
      },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
