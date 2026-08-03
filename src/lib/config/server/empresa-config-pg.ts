/**
 * Configuración / feature flags per-empresa (Fase 0).
 *
 * Fuente autoritativa server-side de banderas por empresa, en la tabla
 * `empresa_config` (NO en localStorage/ConfigGlobal). Se auto-provisiona una
 * fila con defaults en la primera lectura, de modo que ausencia = defaults.
 *
 * Bandera clave del alcance Tecnolabo:
 *   - stock_salida_por_remision: la factura NO descuenta stock; el stock sale al
 *     confirmar cada nota de remisión.
 */
import type { PoolClient } from "pg";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface EmpresaConfig {
  empresa_id: string;
  stock_salida_por_remision: boolean;
  permitir_stock_negativo: boolean;
  permitir_excedente_recepcion: boolean;
  compra_ingresa_por_recepcion: boolean;
  extra: Record<string, unknown>;
}

const DEFAULTS: Omit<EmpresaConfig, "empresa_id"> = {
  stock_salida_por_remision: false,
  permitir_stock_negativo: false,
  permitir_excedente_recepcion: false,
  compra_ingresa_por_recepcion: false,
  extra: {},
};

function mapRow(empresaId: string, row: Record<string, unknown> | undefined): EmpresaConfig {
  if (!row) return { empresa_id: empresaId, ...DEFAULTS };
  return {
    empresa_id: empresaId,
    stock_salida_por_remision: row.stock_salida_por_remision === true,
    permitir_stock_negativo: row.permitir_stock_negativo === true,
    permitir_excedente_recepcion: row.permitir_excedente_recepcion === true,
    compra_ingresa_por_recepcion: row.compra_ingresa_por_recepcion === true,
    extra: (row.extra as Record<string, unknown>) ?? {},
  };
}

/** Lee la config (dentro de la tx del caller). Ausencia → defaults en memoria. */
export async function getEmpresaConfigTx(
  client: PoolClient,
  schema: string,
  empresaId: string,
): Promise<EmpresaConfig> {
  assertAllowedChatDataSchema(schema);
  const t = quoteSchemaTable(schema, "empresa_config");
  const res = await client.query(`SELECT * FROM ${t} WHERE empresa_id = $1::uuid`, [empresaId]);
  return mapRow(empresaId, res.rows[0]);
}

/** Lee la config con conexión propia (best-effort → defaults si no hay pool). */
export async function getEmpresaConfig(schema: string, empresaId: string): Promise<EmpresaConfig> {
  const pool = getChatPostgresPool();
  if (!pool) return { empresa_id: empresaId, ...DEFAULTS };
  const client = await pool.connect();
  try {
    return await getEmpresaConfigTx(client, schema, empresaId);
  } finally {
    client.release();
  }
}

export type EmpresaConfigFlags = Partial<Omit<EmpresaConfig, "empresa_id" | "extra">> & {
  extra?: Record<string, unknown>;
};

/** Upsert de banderas (merge). Sólo actualiza las claves provistas. */
export async function setEmpresaConfig(
  schema: string,
  empresaId: string,
  flags: EmpresaConfigFlags,
): Promise<EmpresaConfig> {
  assertAllowedChatDataSchema(schema);
  const pool = getChatPostgresPool();
  if (!pool) throw new Error("Pool no disponible.");
  const t = quoteSchemaTable(schema, "empresa_config");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    // Asegura fila base con defaults.
    await client.query(
      `INSERT INTO ${t} (empresa_id) VALUES ($1::uuid) ON CONFLICT (empresa_id) DO NOTHING`,
      [empresaId],
    );
    const sets: string[] = [];
    const vals: unknown[] = [empresaId];
    const push = (col: string, val: unknown, cast = "") => {
      vals.push(val);
      sets.push(`${col} = $${vals.length}${cast}`);
    };
    if (flags.stock_salida_por_remision !== undefined)
      push("stock_salida_por_remision", flags.stock_salida_por_remision);
    if (flags.permitir_stock_negativo !== undefined)
      push("permitir_stock_negativo", flags.permitir_stock_negativo);
    if (flags.permitir_excedente_recepcion !== undefined)
      push("permitir_excedente_recepcion", flags.permitir_excedente_recepcion);
    if (flags.compra_ingresa_por_recepcion !== undefined)
      push("compra_ingresa_por_recepcion", flags.compra_ingresa_por_recepcion);
    if (flags.extra !== undefined) push("extra", JSON.stringify(flags.extra), "::jsonb");

    if (sets.length > 0) {
      sets.push("updated_at = now()");
      await client.query(
        `UPDATE ${t} SET ${sets.join(", ")} WHERE empresa_id = $1::uuid`,
        vals,
      );
    }
    const out = await getEmpresaConfigTx(client, schema, empresaId);
    await client.query("COMMIT");
    return out;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}
