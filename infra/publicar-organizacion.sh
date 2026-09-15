#!/usr/bin/env bash
# Publica una nueva organizacion para que la vean todos los usuarios.
#
#   ./infra/publicar-organizacion.sh                 # publica organia-datos.csv
#   ./infra/publicar-organizacion.sh ~/mi-excel.csv  # publica otro archivo
#
# Solo reemplaza el archivo de datos y, si existen, las fotos. No toca el
# HTML ni requiere volver a desplegar la aplicacion.
set -euo pipefail

PERFIL="${PERFIL:-openbank}"
REGION="${REGION:-us-east-1}"
STACK="${STACK:-organia}"

cd "$(dirname "$0")/.."
ORIGEN="${1:-organia-datos.csv}"

if [[ ! -f "$ORIGEN" ]]; then
  echo "No encontre el archivo: $ORIGEN" >&2
  exit 1
fi

if [[ "$ORIGEN" == *.xlsx ]]; then
  echo "Este script publica CSV, no .xlsx." >&2
  echo "Abre el .xlsx en la app (⚙ Subir organización), revisa que se vea bien," >&2
  echo "descarga con ⚙ Descargar organización y publica ese archivo." >&2
  exit 1
fi

leer_salida() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --profile "$PERFIL" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

BUCKET="$(leer_salida NombreBucket)"
DIST="$(leer_salida IdDistribucion)"
URL="$(leer_salida UrlSitio)"

# Revision minima antes de publicar: que traiga encabezado y al menos una fila
FILAS=$(($(wc -l < "$ORIGEN") - 1))
if [[ "$FILAS" -lt 1 ]]; then
  echo "El archivo no tiene filas de datos." >&2
  exit 1
fi
if ! head -1 "$ORIGEN" | grep -qi "role\|puesto"; then
  echo "El archivo no parece tener la columna de puesto en su encabezado." >&2
  echo "Encabezado leido: $(head -1 "$ORIGEN" | cut -c1-120)" >&2
  exit 1
fi

echo "Publicando $ORIGEN ($FILAS filas) en $BUCKET"

aws s3 cp "$ORIGEN" "s3://$BUCKET/organia-datos.csv" \
  --profile "$PERFIL" --region "$REGION" \
  --cache-control 'no-cache, must-revalidate' \
  --content-type 'text/csv; charset=utf-8'

if [[ -d photos ]] && [[ -n "$(ls -A photos 2>/dev/null)" ]]; then
  echo "Sincronizando fotos..."
  aws s3 sync photos/ "s3://$BUCKET/photos/" \
    --profile "$PERFIL" --region "$REGION" \
    --cache-control 'no-cache, must-revalidate' \
    --delete
fi

echo "Invalidando cache..."
ID="$(aws cloudfront create-invalidation \
  --distribution-id "$DIST" --paths '/organia-datos.csv' '/photos/*' \
  --profile "$PERFIL" --region "$REGION" \
  --query 'Invalidation.Id' --output text)"

aws cloudfront wait invalidation-completed \
  --distribution-id "$DIST" --id "$ID" \
  --profile "$PERFIL" --region "$REGION"

echo
echo "Publicado. Todos veran la nueva organizacion al recargar: $URL"
