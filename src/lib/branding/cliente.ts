/**
 * Identidad del cliente de esta instancia (monocliente).
 *
 * Fuente central de branding: el resto del código NO debe hardcodear el nombre
 * comercial, el logo ni los datos fiscales. Así una futura instancia sólo cambia
 * este archivo y sus variables de entorno.
 *
 * NEXT_PUBLIC_NEURA_CLIENT_NAME se lee de forma literal para que Next.js pueda
 * incrustarlo en el bundle del navegador; NEURA_CLIENT_NAME sólo resuelve en servidor.
 */
const NOMBRE_PUBLICO = process.env.NEXT_PUBLIC_NEURA_CLIENT_NAME?.trim();
const NOMBRE_SERVIDOR =
  typeof process !== "undefined" ? process.env.NEURA_CLIENT_NAME?.trim() : undefined;

/** Nombre comercial visible (metadata, login, sidebar, PDFs, logs). */
export const CLIENTE_NOMBRE: string = NOMBRE_PUBLICO || NOMBRE_SERVIDOR || "Tecnolabo";

/** Slug técnico: repo, schema y subdominio. */
export const CLIENTE_SLUG = "tecnolabo";

/**
 * IVA por defecto de las líneas (ventas, presupuestos, facturas).
 *
 * Tecnolabo opera en Bolivia y NO cobra el IVA paraguayo: los precios son el
 * costo del producto sin impuesto. Por eso el default es "EXENTA".
 * (El cajero igual puede elegir 5%/10% en una línea puntual si hiciera falta.)
 */
export const IVA_POR_DEFECTO: "EXENTA" | "5%" | "10%" = "EXENTA";

/** Nombre del producto tal como se muestra en títulos y documentos. */
export const CLIENTE_ERP_NOMBRE = `${CLIENTE_NOMBRE} ERP`;

/**
 * Logo del cliente servido desde /public.
 *
 * Logo oficial de TECNO/LABO (de Pastor Ramírez). Se muestra en el Header y en
 * el membrete de los documentos (presupuestos, remisiones, recepciones, etc.).
 */
export const CLIENTE_LOGO_URL: string | null = "/tecnolabo-logo.jpeg";

/**
 * Datos comerciales y fiscales del cliente.
 *
 * PENDIENTE: razón social, RUC, teléfono, dirección y actividad económica deben
 * cargarse con la información real de Tecnolabo. Se dejan vacíos a propósito:
 * no se heredan los del ERP fuente ni se inventan.
 */
export const CLIENTE_DATOS_FISCALES = {
  razonSocial: "",
  ruc: "",
  telefono: "",
  direccion: [] as string[],
  actividad: [] as string[],
  /** Ciudad que encabeza comprobantes impresos. Vacía = solo se imprime la fecha. */
  ciudad: "",
};
