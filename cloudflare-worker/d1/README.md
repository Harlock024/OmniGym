# Catálogo postal SEPOMEX (Cloudflare D1)

Catálogo CP → colonias servido por el worker en `GET /catalogs/postal?cp=XXXXX`.
Vive en **Cloudflare D1** (SQLite) en vez de Firestore, porque son ~145k filas y el
plan Spark de Firebase no soporta ese volumen de escrituras/lecturas.

## Despliegue (una sola vez)

```bash
cd cloudflare-worker

# 1. Crear la base D1 y copiar el database_id que imprime a wrangler.toml
wrangler d1 create omnigym_catalogs

# 2. Crear el esquema (tabla sepomex + catalog_meta)
wrangler d1 execute omnigym_catalogs --file=./d1/schema.sql --remote

# 3. Generar el seed desde el mirror público de GitHub (descarga + arma seed.sql)
node d1/import_sepomex.mjs

# 4. Cargar los datos (~145,908 filas). Wrangler divide el archivo en lotes.
wrangler d1 execute omnigym_catalogs --file=./d1/seed.sql --remote

# 5. Desplegar el worker (ya con el binding CATALOGS_DB)
wrangler deploy
```

## Verificar

```bash
curl -H "Authorization: Bearer <UPLOAD_SECRET>" \
  "https://omni-gym.hadith024.workers.dev/catalogs/postal?cp=20000"
# → { cp, found:true, estado, municipio, ciudad, colonias:[{nombre,tipo}, …] }
```

## Re-sincronización / versionado

El dataset no se sobreescribe a ciegas: `catalog_meta` guarda `{catalog, version,
rows, updated_at}`. Para actualizar a una versión más nueva, repetir pasos 2–4
(el `DROP TABLE` del schema recrea limpio) y el seed registra la nueva versión.

- Fuente: `redrbrt/sepomex-zip-codes` (abril 2016, 145,908 registros).
- `seed.sql` se genera localmente y está en `.gitignore` (no se versiona, 13 MB).
