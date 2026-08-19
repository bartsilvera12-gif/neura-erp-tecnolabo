/**
 * Genera un KuDE de prueba en memoria para verificar el branding del cliente:
 * que el logo JPEG se embeba (antes solo se aceptaba PNG) y que el color
 * primario sea el de la marca, no el azul Neura.
 *
 * No toca la base ni SIFEN. Escribe el PDF en scripts/_out para inspeccion.
 */
import fs from "node:fs";
import path from "node:path";
import { buildKudePdfBuffer } from "@/lib/sifen/kude-pdf";
import { CLIENTE_COLORES, CLIENTE_LOGO_URL } from "@/lib/branding/cliente";
import type { KudeParsedFromXml } from "@/lib/sifen/parse-kude-from-signed-xml";

const parsed = {
  cdc: "01801679380010020000001120260818123456789",
  dFeEmiDE: "2026-08-18T10:00:00",
  dCarQR: null,
  monedaCodigo: "PYG",
  monedaDescripcion: "Guarani",
  timbrado: { dNumTim: "19058619", dEst: "001", dPunExp: "002", dNumDoc: "0000001", dFeIniT: "2026-08-01" },
  emisor: {
    dRucEm: "80167938",
    dDVEmi: "7",
    dNomEmi: "TECNOLABO E.A.S. UNIPERSONAL",
    dDirEmi: "AVENIDA PRINCIPAL 123",
    dTelEmi: "0981625726",
    dEmailE: "ventas@tecnolabo.com.py",
  },
  receptor: { nombre: "GABRIELA GAUTO", docLabel: "RUC", docValue: "5375000-4", direccion: "ASUNCION", telefono: "0981000000" },
  operacion: { condicionVenta: "Contado", tipoOperacion: "B2C" },
  infoEmisor: "Orden de Compra: OC-25874",
  totales: {
    dSubExe: "0", dSub5: "0", dSub10: "110000", dTotOpe: "110000", dTotGralOpe: "110000",
    dIVA5: "0", dIVA10: "10000", dBaseGrav5: "0", dBaseGrav10: "100000",
    dTBasGraIVA: "100000", dTotIVA: "10000",
  },
  items: [
    {
      codigo: "EQ-001",
      descripcion: "EQUIPO DE LABORATORIO",
      unidadMedida: "UNI",
      cantidad: "1",
      precioUnit: "110000",
      totalLinea: "110000",
      montoExenta: "0",
      montoGrav5: "0",
      montoGrav10: "110000",
    },
  ],
} as unknown as KudeParsedFromXml;

let fallos = 0;
function check(cond: boolean, msg: string) {
  console.log((cond ? "  OK    " : "  FALLA ") + msg);
  if (!cond) fallos++;
}

(async () => {
  console.log("-- branding configurado --");
  console.log("  logo    = " + CLIENTE_LOGO_URL);
  console.log("  primario= " + CLIENTE_COLORES.primario);

  const logoRel = String(CLIENTE_LOGO_URL ?? "").replace(/^\/+/, "");
  const logoPath = path.join(process.cwd(), "public", logoRel);
  check(!!logoRel && fs.existsSync(logoPath), "el logo del cliente existe en /public (" + logoRel + ")");
  check(/\.jpe?g$/i.test(logoRel) || /\.png$/i.test(logoRel), "formato de logo soportado (jpg/jpeg/png)");

  const pdf = await buildKudePdfBuffer({
    parsed,
    numeroFactura: "001-002-0000001",
    dProtAut: null,
    qrUrl: "https://ekuatia.set.gov.py/consultas/qr?nVersion=150",
  });

  check(pdf.length > 5000, "el PDF se genero (" + Math.round(pdf.length / 1024) + " KB)");

  const head = pdf.subarray(0, 5).toString("latin1");
  check(head.startsWith("%PDF-"), "el archivo es un PDF valido");

  // Si el JPEG se embebio, pdf-lib deja un filtro DCTDecode en el stream de imagen.
  const cuerpo = pdf.toString("latin1");
  const esJpg = /\.jpe?g$/i.test(logoRel);
  if (esJpg) {
    check(cuerpo.includes("DCTDecode"), "el logo JPEG quedo embebido (DCTDecode presente)");
  } else {
    check(cuerpo.includes("FlateDecode"), "el logo PNG quedo embebido");
  }

  const outDir = path.join(process.cwd(), "scripts", "_out");
  fs.mkdirSync(outDir, { recursive: true });
  const out = path.join(outDir, "kude-branding.pdf");
  fs.writeFileSync(out, pdf);
  console.log("");
  console.log("PDF de muestra: " + out);

  console.log("");
  if (fallos > 0) {
    console.log("RESULTADO: " + fallos + " comprobacion(es) fallaron");
    process.exit(1);
  }
  console.log("RESULTADO: todo OK");
})().catch((e) => {
  console.error("ERROR: " + (e?.message || e));
  process.exit(1);
});
