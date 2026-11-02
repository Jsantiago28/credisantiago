#!/usr/bin/env bash
# Prueba aplicar_migraciones.sh con una API falsa (supabase/pruebas/api_falsa):
# de 2 migraciones "sin correr", debe correr esas 2, en orden, cada una entre
# begin/commit y anotada en control.migraciones; y ninguna otra.
set -euo pipefail
cd "$(dirname "$0")/.."
export FALSO_DIR=$PWD FALSO_LOG=$(mktemp)
ultimas=$(ls migracion_*.sql | sort | tail -2)
export FALSO_NUEVAS=$(mktemp)
echo "$ultimas" > "$FALSO_NUEVAS"
# Una dirección que no existe: aunque se usara el curl de verdad, no llega a nada.
PATH="$PWD/pruebas/api_falsa:$PATH" SUPABASE_API_URL=http://127.0.0.1:9 \
  SUPABASE_ACCESS_TOKEN=x SUPABASE_PROJECT_REF=x \
  bash pruebas/aplicar_migraciones.sh

corridas=$(grep -o "insert into control.migraciones (nombre) values ('[^']*')" "$FALSO_LOG" | sed "s/.*('//;s/')//")
[ "$corridas" = "$ultimas" ] || { echo "Se corrieron: $corridas — se esperaban: $ultimas"; exit 1; }
[ "$(grep -c '"query":"begin;' "$FALSO_LOG")" = 2 ] || { echo 'Falta el begin'; exit 1; }
[ "$(grep -c 'commit;' "$FALSO_LOG")" = 2 ] || { echo 'Falta el commit'; exit 1; }
echo "El aplicador corre solo las nuevas, en orden y enteras."
