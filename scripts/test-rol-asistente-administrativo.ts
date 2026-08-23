/**
 * Valida la matriz de acceso del rol Asistente Administrativo contra la base y
 * contra el mapa de rutas real del ERP.
 *
 * Comprueba las dos capas juntas:
 *   1. que el usuario tenga (o no) el modulo en `usuario_modulos`;
 *   2. que la ruta de esa pantalla exija ese modulo (`pathRequiresModuleSlug`),
 *      que es lo que impide entrar por URL directa.
 *
 * Tambien verifica que el administrador conserve todos sus accesos.
 */
import fs from "node:fs";
import { Client } from "pg";
import { pathRequiresModuleSlug, isModuleSlugGranted } from "@/lib/modulos/route-slug-map";

const AUTH_ASISTENTE = "fa5dcbba-5675-4a4a-b574-648dc754e9bd";
const SCHEMA = "tecnolabo";

const env: Record<string, string> = {};
for (const l of fs.readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const m = l.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) env[m[1]!] = m[2]!.replace(/^["']|["']$/g, "");
}

/** Pantalla -> ruta real. El slug se deriva del mapa, no se hardcodea. */
const MATRIZ: { area: string; ruta: string; debe: boolean }[] = [
  { area: "Comercial · Clientes", ruta: "/clientes", debe: true },
  { area: "Comercial · Caja", ruta: "/ventas", debe: true },
  { area: "Comercial · Presupuestos", ruta: "/presupuestos", debe: true },
  { area: "Comercial · Notas de remisión", ruta: "/notas-remision", debe: true },
  { area: "Comercial · CRM", ruta: "/crm", debe: true },
  { area: "Comercial · COMISIONES", ruta: "/comisiones", debe: false },
  { area: "Finanzas · Pagos", ruta: "/pagos", debe: true },
  { area: "Finanzas · Gastos", ruta: "/gastos", debe: true },
  { area: "Finanzas · Cuentas bancarias", ruta: "/configuracion/entidades-bancarias", debe: true },
  { area: "Finanzas · Cobranzas (fuera de la matriz)", ruta: "/cobranzas", debe: false },
  { area: "Finanzas · Recibos (fuera de la matriz)", ruta: "/recibos", debe: false },
  { area: "Finanzas · Otros ingresos (fuera de la matriz)", ruta: "/otros-ingresos", debe: false },
  { area: "Inventario · Productos", ruta: "/inventario", debe: true },
  { area: "Inventario · Movimientos", ruta: "/inventario/movimientos", debe: true },
  { area: "Inventario · Categorías", ruta: "/inventario/categorias", debe: true },
  { area: "Inventario · Notas de salida", ruta: "/notas-salida", debe: true },
  { area: "Inventario · Alertas de stock", ruta: "/inventario/alertas", debe: true },
  { area: "Compras · Órdenes", ruta: "/compras", debe: true },
  { area: "Compras · Proveedores", ruta: "/proveedores", debe: true },
  { area: "Compras · Cuentas por pagar", ruta: "/compras/cuentas-por-pagar", debe: true },
  { area: "Configuración (no autorizado)", ruta: "/configuracion", debe: false },
  { area: "Usuarios (no autorizado)", ruta: "/usuarios", debe: false },
  { area: "Reportes (no autorizado)", ruta: "/reportes", debe: false },
  { area: "Notas de crédito (no autorizado)", ruta: "/notas-credito", debe: false },
];

let fallos = 0;
function check(ok: boolean, msg: string) {
  console.log((ok ? "  OK    " : "  FALLA ") + msg);
  if (!ok) fallos++;
}

(async () => {
  const c = new Client({ connectionString: env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } });
  await c.connect();
  try {
    const u = await c.query(
      `SELECT id, nombre, email, rol, activo FROM ${SCHEMA}.usuarios WHERE auth_user_id = $1::uuid`,
      [AUTH_ASISTENTE],
    );
    if (u.rowCount === 0) {
      console.log("FALLA: el asistente no tiene ficha en el ERP");
      process.exit(1);
    }
    const asistente = u.rows[0];
    console.log("Asistente: " + asistente.nombre + " <" + asistente.email + "> rol=" + asistente.rol);
    check(asistente.rol !== "admin" && asistente.rol !== "administrador", "no quedo como administrador");
    check(asistente.activo === true, "esta activo");

    const mods = await c.query(
      `SELECT m.slug FROM ${SCHEMA}.usuario_modulos um
         JOIN ${SCHEMA}.modulos m ON m.id = um.modulo_id
        WHERE um.usuario_id = $1::uuid`,
      [asistente.id],
    );
    const otorgados = new Set<string>(mods.rows.map((r) => String(r.slug)));
    console.log("Módulos otorgados (" + otorgados.size + "): " + [...otorgados].sort().join(", "));
    console.log("");

    console.log("-- matriz de acceso --");
    for (const m of MATRIZ) {
      const slug = pathRequiresModuleSlug(m.ruta);
      if (!slug) {
        check(false, m.area + " → la ruta " + m.ruta + " NO exige modulo (entra cualquiera por URL)");
        continue;
      }
      // strict: la instancia corre en single_client, sin alias heredados.
      const puede = isModuleSlugGranted(slug, otorgados, undefined, { strict: true });
      check(puede === m.debe, m.area + " → " + (m.debe ? "SI" : "NO") + " (slug " + slug + ", da " + (puede ? "SI" : "NO") + ")");
    }

    // El administrador no debe perder nada.
    console.log("");
    console.log("-- administrador --");
    const admin = await c.query(
      `SELECT id, rol FROM ${SCHEMA}.usuarios WHERE lower(rol) IN ('admin','administrador','super_admin') LIMIT 1`,
    );
    check((admin.rowCount ?? 0) > 0, "sigue existiendo un usuario administrador");
    if ((admin.rowCount ?? 0) > 0) {
      const acotado = await c.query(
        `SELECT count(*)::int n FROM ${SCHEMA}.usuario_modulos WHERE usuario_id = $1::uuid`,
        [admin.rows[0].id],
      );
      check(acotado.rows[0].n === 0, "el administrador NO quedo acotado por usuario_modulos");
    }
    const act = await c.query(
      `SELECT count(*)::int n FROM ${SCHEMA}.empresa_modulos WHERE activo = false`,
    );
    check(act.rows[0].n === 0, "ningun modulo de la empresa quedo desactivado");
  } finally {
    await c.end();
  }

  console.log("");
  if (fallos > 0) {
    console.log("RESULTADO: " + fallos + " comprobacion(es) fallaron");
    process.exit(1);
  }
  console.log("RESULTADO: matriz de acceso correcta");
})();
