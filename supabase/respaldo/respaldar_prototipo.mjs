// Respaldo de las tablas del prototipo ANTES de aplicar la migración
// 20261112000000_gygtrack_modelo.sql, que las borra.
//
// No necesita Docker ni pg_dump: se conecta directo a PostgreSQL.
//
// Uso (desde supabase/respaldo):
//   npm install
//   $env:DATABASE_URL = "postgresql://postgres.<ref>:<clave>@<host>:5432/postgres"   # PowerShell
//   npm run respaldar
//
// La cadena de conexión está en Supabase → Connect → Session pooler.
// Genera respaldos/prototipo_<fecha>.json y .sql (INSERTs para restaurar).
// La carpeta respaldos/ NO se versiona: contiene datos.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Tablas que la migración elimina o transforma. */
export const TABLAS = ["profiles", "cotizaciones", "rutas", "puntos_ruta"];

function literal(valor) {
  if (valor === null || valor === undefined) return "NULL";
  if (typeof valor === "number" || typeof valor === "bigint") return String(valor);
  if (typeof valor === "boolean") return valor ? "true" : "false";
  if (valor instanceof Date) return `'${valor.toISOString()}'`;
  const texto = typeof valor === "object" ? JSON.stringify(valor) : String(valor);
  return `'${texto.replace(/'/g, "''")}'`;
}

/**
 * Lee las tablas del prototipo con un cliente que tenga `query(sql)` →
 * `{ rows }` (pg.Client o PGlite). Omite las que no existan.
 */
export async function respaldar(cliente, tablas = TABLAS) {
  const datos = {};
  let sql = `-- Respaldo del prototipo GyGTrack (${new Date().toISOString()})\n` +
    `-- Restaurar sobre el esquema del prototipo (migraciones 20260825 y 20260826).\n\n`;

  for (const tabla of tablas) {
    const existe = await cliente.query(`select to_regclass('public.${tabla}') is not null as existe`);
    if (!existe.rows[0].existe) continue;

    const { rows } = await cliente.query(`select * from public.${tabla}`);
    datos[tabla] = rows;
    sql += `-- ${tabla}: ${rows.length} fila(s)\n`;
    for (const fila of rows) {
      const columnas = Object.keys(fila);
      sql += `insert into public.${tabla} (${columnas.join(", ")}) values (` +
        `${columnas.map((c) => literal(fila[c])).join(", ")});\n`;
    }
    sql += "\n";
  }
  return { datos, sql };
}

async function main() {
  const url = process.env.DATABASE_URL ?? process.argv[2];
  if (!url) {
    console.error("Falta DATABASE_URL (Supabase → Connect → Session pooler).");
    process.exit(1);
  }
  const { default: pg } = await import("pg");
  const cliente = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await cliente.connect();
  try {
    const { datos, sql } = await respaldar(cliente);
    const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "respaldos");
    fs.mkdirSync(dir, { recursive: true });
    const sello = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
    const base = path.join(dir, `prototipo_${sello}`);
    fs.writeFileSync(`${base}.json`, JSON.stringify(datos, null, 2));
    fs.writeFileSync(`${base}.sql`, sql);
    for (const [tabla, filas] of Object.entries(datos)) console.log(`  ${tabla}: ${filas.length} fila(s)`);
    console.log(`\nRespaldo guardado en:\n  ${base}.json\n  ${base}.sql`);
    console.log("Verifícalo antes de ejecutar `supabase db push`.");
  } finally {
    await cliente.end();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
