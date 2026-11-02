#!/usr/bin/env bash
# Corre en la base de datos de VERDAD las migraciones nuevas (las que no
# están en control.migraciones), una por una y en orden, cada una entera
# o nada (si falla, se deshace y se para). Lo usa aplicar-migraciones.yml.
#
# Necesita SUPABASE_ACCESS_TOKEN y SUPABASE_PROJECT_REF.
set -euo pipefail
cd "$(dirname "$0")/.."

API="${SUPABASE_API_URL:-https://api.supabase.com}/v1/projects/${SUPABASE_PROJECT_REF}/database/query"

consulta() {
  local respuesta codigo
  respuesta=$(mktemp)
  codigo=$(jq -Rsc '{query: .}' | curl -sS -o "$respuesta" -w '%{http_code}' -X POST "$API" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' --data-binary @-)
  if [[ "$codigo" != 2* ]]; then
    echo "::error::La base de datos respondió $codigo:" >&2
    cat "$respuesta" >&2
    echo >&2
    return 1
  fi
  cat "$respuesta"
}

hechas=$(echo "select nombre from control.migraciones" | consulta | jq -r '.[].nombre')

pendientes=0
for f in $(ls migracion_*.sql | sort); do
  if grep -qxF "$f" <<<"$hechas"; then continue; fi
  pendientes=$((pendientes + 1))
  echo "Aplicando $f ..."
  { echo 'begin;'; cat "$f"; echo; echo "insert into control.migraciones (nombre) values ('$f');"; echo 'commit;'; } \
    | consulta >/dev/null
  echo "  listo: $f"
done

if [[ $pendientes -eq 0 ]]; then
  echo "No hay migraciones nuevas: la base de datos ya está al día."
else
  echo "Aplicadas: $pendientes."
fi
