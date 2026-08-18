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
