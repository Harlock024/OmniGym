// Descarga el dataset SEPOMEX de un mirror público de GitHub y genera seed.sql
// para cargarlo en Cloudflare D1.
//
// Uso:
//   node d1/import_sepomex.mjs
//   wrangler d1 execute omnigym_catalogs --file=./d1/schema.sql --remote
//   wrangler d1 import  omnigym_catalogs --file=./d1/seed.sql   --remote
//
// Fuente: redrbrt/sepomex-zip-codes (145,908 registros, abril 2016).
// Campos por registro: { idEstado, estado, idMunicipio, municipio, ciudad,
//                        zona, cp (número), asentamiento, tipo }

import { writeFileSync } from 'node:fs';

const SOURCE_URL =
  'https://raw.githubusercontent.com/redrbrt/sepomex-zip-codes/master/sepomex_abril-2016.json';
const VERSION = 'sepomex_abril-2016';
const OUT = new URL('./seed.sql', import.meta.url);
const BATCH = 500;

const sqlStr = (v) =>
  v == null ? 'NULL' : `'${String(v).replace(/'/g, "''")}'`;

async function main() {
  console.log(`Descargando ${SOURCE_URL} …`);
  const res = await fetch(SOURCE_URL);
  if (!res.ok) throw new Error(`Descarga falló: HTTP ${res.status}`);
  // El mirror usa NULL (estilo SQL) en vez de null → JSON inválido. Se sanea.
  const raw = (await res.text()).replace(/:\s*NULL\b/g, ': null');
  const data = JSON.parse(raw);
  console.log(`Registros: ${data.length}`);

  // Nota: D1 maneja las transacciones internamente; NO se emite BEGIN/COMMIT.
  const lines = [];
  for (let i = 0; i < data.length; i += BATCH) {
    const chunk = data.slice(i, i + BATCH);
    const values = chunk
      .map((r) => {
        const cp = String(r.cp).padStart(5, '0');
        return `(${sqlStr(cp)},${sqlStr(r.asentamiento)},${sqlStr(r.tipo)},${sqlStr(r.municipio)},${sqlStr(r.estado)},${sqlStr(r.ciudad)},${sqlStr(r.zona)})`;
      })
      .join(',');
    lines.push(
      `INSERT INTO sepomex (cp,asentamiento,tipo,municipio,estado,ciudad,zona) VALUES ${values};`,
    );
  }

  // Versionado del catálogo.
  lines.push(
    `INSERT OR REPLACE INTO catalog_meta (catalog,version,rows,updated_at) VALUES ('sepomex',${sqlStr(VERSION)},${data.length},${sqlStr(new Date().toISOString())});`,
  );

  writeFileSync(OUT, lines.join('\n'));
  console.log(`seed.sql generado: ${OUT.pathname} (${lines.length} sentencias)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
