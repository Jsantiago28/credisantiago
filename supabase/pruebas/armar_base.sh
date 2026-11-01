#!/usr/bin/env bash
# Arma una base de datos de PRUEBA igual a la de producción: schema.sql y
# después cada migración en el orden en que se corrieron (por fecha y, el
# mismo día, por nombre). Solo se usa en GitHub (pruebas-base-datos.yml);
# nunca toca la base de datos de verdad.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf migrations
mkdir migrations
cp schema.sql migrations/20260901000000_schema.sql

n=0
for f in $(ls migracion_*.sql | sort); do
  n=$((n + 1))
  fecha=$(echo "$f" | sed -E 's/^migracion_([0-9]{4})_([0-9]{2})_([0-9]{2})_.*/\1\2\3/')
  nombre=$(echo "$f" | sed -E 's/^migracion_[0-9_]{11}(.*)\.sql$/\1/')
  cp "$f" "migrations/${fecha}$(printf '%06d' "$n")_${nombre}.sql"
done
ls migrations
