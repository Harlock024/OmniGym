-- Esquema D1 para el catálogo postal SEPOMEX (CP → colonias).
-- Aplicar con: wrangler d1 execute omnigym_catalogs --file=./d1/schema.sql --remote

DROP TABLE IF EXISTS sepomex;
CREATE TABLE sepomex (
  cp           TEXT NOT NULL,   -- código postal, 5 chars con ceros a la izquierda
  asentamiento TEXT NOT NULL,   -- colonia / asentamiento
  tipo         TEXT,            -- tipo de asentamiento (Colonia, Fraccionamiento, …)
  municipio    TEXT,
  estado       TEXT,
  ciudad       TEXT,
  zona         TEXT
);
CREATE INDEX idx_sepomex_cp ON sepomex(cp);

-- Versionado de catálogos: no se sobreescribe, se registra la versión cargada.
CREATE TABLE IF NOT EXISTS catalog_meta (
  catalog    TEXT PRIMARY KEY,
  version    TEXT,
  rows       INTEGER,
  updated_at TEXT
);
