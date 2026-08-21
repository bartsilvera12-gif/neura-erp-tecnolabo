/**
 * Verifica que dInfoEmi (Orden de Compra) se emita dentro de gOpeDE, después de
 * dCodSeg, y que NO aparezca cuando la factura no tiene orden de compra.
 * No toca la base ni SIFEN: solo construye el XML en memoria.
 */
import { buildOfficialRdeFacturaElectronicaXml } from "@/lib/sifen/rde-xml";
import type { SifenFacturaPayloadBase } from "@/lib/sifen/types";

function base(oc: string | null): SifenFacturaPayloadBase {
  return {
    emisor: {
      ruc: "80167938",
      dv: "7",
      razon_social: "TECNOLABO E.A.S. UNIPERSONAL",
      timbrado_numero: "19058619",
      establecimiento: "001",
      punto_expedicion: "002",
      numero_documento: "0000001",
    },
    documento: {
      factura_id: "00000000-0000-0000-0000-000000000001",
      numero_factura: "001-002-0000001",
      fecha: "2026-08-18T10:00:00.000Z",
      tipo: "contado",
      moneda: "GS",
      monto: 110000,
      saldo: 0,
      numero_orden_compra: oc,
    },
    receptor: {
      cliente_id: "00000000-0000-0000-0000-000000000002",
      nombre: "JUAN PEREZ",
      documento: null,
      ruc: "5375000",
      dv: "4",
      direccion: "TENIENTE FULGENCIO YEGROS",
      telefono: "0981625726",
      email: null,
      receptor_extranjero: false,
      codigo_pais_iso3: "PRY",
      tipo_doc_receptor: null,
      descripcion_tipo_doc_receptor: null,
      num_id_receptor: null,
      naturaleza: "contribuyente_paraguayo",
      ti_ope: 1,
      num_casa: 0,
    },
    items: [
      {
        descripcion: "PRODUCTO DE PRUEBA",
        cantidad: 1,
        precio_unitario: 110000,
        total: 110000,
        iva_tipo: "10%",
        monto_iva: 10000,
      },
    ],
    sifen: {
      factura_electronica_id: "00000000-0000-0000-0000-000000000003",
      estado_sifen: "borrador",
    },
  } as unknown as SifenFacturaPayloadBase;
}

const opts = {
  timbradoFechaInicio: "2026-08-01",
  ambiente: "test" as const,
  emisorTelefono: "0973989068",
  emisorEmail: "test@tecnolabo.com.py",
  emisorDireccion: "AVENIDA PRINCIPAL 123",
  emisorNumCasa: 123,
  actividadEconomicaCodigo: "46102",
  actividadEconomicaDescripcion: "VENTA AL POR MAYOR",
  fechaHoraEmision: new Date("2026-08-18T10:00:00.000Z"),
};

let fallos = 0;
function check(cond: boolean, msg: string) {
  console.log((cond ? "  OK    " : "  FALLA ") + msg);
  if (!cond) fallos++;
}

console.log("-- CON orden de compra --");
const conOC = buildOfficialRdeFacturaElectronicaXml(base("OC-25874"), opts);
const gOpe = /<gOpeDE>([\s\S]*?)<\/gOpeDE>/.exec(conOC);
check(!!gOpe, "existe el bloque gOpeDE");
if (gOpe) {
  const inner = gOpe[1]!;
  console.log("    gOpeDE = " + inner);
  check(inner.includes("<dInfoEmi>"), "gOpeDE contiene dInfoEmi");
  check(
    inner.indexOf("<dCodSeg>") < inner.indexOf("<dInfoEmi>"),
    "dInfoEmi va DESPUES de dCodSeg (orden del XSD)",
  );
  check(inner.includes("Orden de Compra: OC-25874"), "dInfoEmi lleva el numero de orden de compra");
}
check(!/<dInfoEmi>[^<]*<\/dInfoEmi>[\s\S]*<dInfoEmi>/.test(conOC), "dInfoEmi aparece una sola vez");

console.log("");
console.log("-- SIN orden de compra --");
const sinOC = buildOfficialRdeFacturaElectronicaXml(base(null), opts);
check(!sinOC.includes("<dInfoEmi>"), "no se emite el nodo vacio cuando no hay OC");
check(sinOC.includes("<gOpeDE>") && sinOC.includes("<dCodSeg>"), "gOpeDE sigue intacto sin OC");

console.log("");
if (fallos > 0) {
  console.log("RESULTADO: " + fallos + " comprobacion(es) fallaron");
  process.exit(1);
}
console.log("RESULTADO: todo OK");

// ─────────────────────────────────────────────────────────────────────────────
// El tramo que fallaba en produccion: la fila de `facturas` -> payload -> XML.
// La prueba de arriba armaba el payload a mano y por eso no detecto que el
// mapeo intermedio descartaba `numero_orden_compra`.
// ─────────────────────────────────────────────────────────────────────────────
import { validateAndBuildSifenPayload, type BuildSifenPayloadInput } from "@/lib/sifen/build-payload";

console.log("");
console.log("-- fila de facturas -> payload (mapeo intermedio) --");

const filaFactura = {
  id: "00000000-0000-0000-0000-000000000001",
  cliente_id: "00000000-0000-0000-0000-000000000002",
  numero_factura: "FAC-000015",
  fecha: "2026-08-20T10:56:11.000Z",
  tipo: "contado",
  moneda: "GS",
  monto: 3150000,
  saldo: 0,
  numero_orden_compra: "OC- 348",
};

const construido = validateAndBuildSifenPayload({
  factura: filaFactura,
  items: [{ descripcion: "MOLDE CONICO", cantidad: 7, precio_unitario: 450000, iva: 286364, total: 3150000 }],
  cliente: {
    id: filaFactura.cliente_id, empresa: "PARGOS TECH S.A.", nombre_contacto: null, nombre: null,
    ruc: "80088565-1", documento: null, direccion: "Avda. Medicos del Chaco", telefono: "0952133841",
    email: null, pais: "PRY",
  },
  config: {
    activo: true, ruc: "80167938-9", razon_social: "TECNOLABO EAS UNIPERSONAL",
    timbrado_numero: "19058619", timbrado_fecha_inicio_vigencia: "2026-08-17",
    establecimiento: "001", punto_expedicion: "002", ambiente: "test",
    direccion_fiscal: "Jacinto Herrera C/ Amambay",
    actividad_economica_codigo: "46102", actividad_economica_descripcion: "VENTA AL POR MAYOR",
  },
  facturaElectronica: { id: "00000000-0000-0000-0000-000000000003", estado_sifen: "borrador" },
} as unknown as BuildSifenPayloadInput);

if (!construido.ok) {
  console.log("  FALLA  no se pudo construir el payload: " + construido.error);
  fallos++;
} else {
  const oc = construido.payload.documento.numero_orden_compra;
  check(oc === "OC- 348", "el payload conserva la OC de la fila (" + JSON.stringify(oc) + ")");

  const xmlReal = buildOfficialRdeFacturaElectronicaXml(construido.payload, opts);
  check(xmlReal.includes("<dInfoEmi>"), "el XML armado desde la fila lleva dInfoEmi");
  check(xmlReal.includes("Orden de Compra: OC- 348"), "dInfoEmi lleva el numero correcto");
}

console.log("");
if (fallos > 0) {
  console.log("RESULTADO FINAL: " + fallos + " comprobacion(es) fallaron");
  process.exit(1);
}
console.log("RESULTADO FINAL: todo OK");
