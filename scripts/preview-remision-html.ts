/** Renderiza una nota de remisión de muestra para revisar el diseño. Sin base ni red. */
import fs from "node:fs";
import path from "node:path";
import { renderRemisionVentaHTML } from "@/lib/ventas/remision-venta-html";

const html = renderRemisionVentaHTML({
  remision: {
    numero: "NR-000005",
    estado: "confirmada",
    fecha: "2026-08-19T10:00:00.000Z",
    numero_control: "VTA-000007",
    numero_orden_compra: "OC-25874",
    cliente_nombre: "GABRIELA GAUTO",
    observacion: "Falta stock del segundo ítem; se entrega la semana próxima.",
    usuario_creador_nombre: "Admin",
    anulada_motivo: null,
  },
  lineas: [
    { producto_nombre: "PRENSA HIDRAULICA DIGITAL", sku: "EQ-1001", cantidad_vendida: 5, en_esta_remision: 3, pendiente: 2, observacion: "Entrega parcial" },
    { producto_nombre: "MOLDE CILINDRICO 15x30", sku: "MO-2210", cantidad_vendida: 20, en_esta_remision: 20, pendiente: 0, observacion: null },
    { producto_nombre: "TAMIZ NORMALIZADO Nº 200", sku: null, cantidad_vendida: 8, en_esta_remision: 0, pendiente: 8, observacion: null },
  ],
}, "");

const outDir = path.join(process.cwd(), "scripts", "_out");
fs.mkdirSync(outDir, { recursive: true });
const out = path.join(outDir, "remision-muestra.html");
fs.writeFileSync(out, html, "utf8");
console.log("OK  documento generado: " + out);
console.log("OK  color de marca presente: " + html.includes("#C7202A"));
console.log("OK  logo del cliente: " + html.includes("tecnolabo-logo"));
console.log("OK  bloque de pendientes: " + html.includes("Pendiente de entrega"));
