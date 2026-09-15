#!/usr/bin/env bash
# Despliega OrganIA a AWS: sube el sitio al bucket e invalida la cache.
#
#   ./infra/deploy.sh
#
# Requiere que el stack ya exista (ver infra/README.md).
set -euo pipefail

PERFIL="${PERFIL:-openbank}"
REGION="${REGION:-us-east-1}"
STACK="${STACK:-organia}"

cd "$(dirname "$0")/.."

leer_salida() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK" --profile "$PERFIL" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

BUCKET="$(leer_salida NombreBucket)"
DIST="$(leer_salida IdDistribucion)"
URL="$(leer_salida UrlSitio)"

if [[ -z "$BUCKET" || "$BUCKET" == "None" ]]; then
  echo "No se encontro el stack '$STACK'. Creelo primero." >&2
  exit 1
fi

echo "Bucket:       $BUCKET"
echo "Distribucion: $DIST"
echo

# Nada se cachea: la organizacion y las fotos se actualizan reemplazando
# archivos, y si el navegador guardara copias, la gente seguiria viendo la
# version anterior. Antes las fotos se cacheaban una semana, asi que sustituir
# la foto de alguien tardaba hasta 7 dias en verse.
echo "Subiendo fotos..."
aws s3 sync photos/ "s3://$BUCKET/photos/" \
  --profile "$PERFIL" --region "$REGION" \
  --cache-control 'no-cache, must-revalidate' \
  --delete

# 'sync' solo sube lo que cambio, asi que una foto que ya estaba en el bucket
# conserva los encabezados con los que se subio la primera vez. Sin esta
# pasada, corregir la cache no surtiria efecto sobre las fotos existentes.
aws s3 cp "s3://$BUCKET/photos/" "s3://$BUCKET/photos/" \
  --recursive --metadata-directive REPLACE \
  --profile "$PERFIL" --region "$REGION" \
  --cache-control 'no-cache, must-revalidate' >/dev/null

echo "Subiendo la organizacion..."
aws s3 cp organia-datos.csv "s3://$BUCKET/organia-datos.csv" \
  --profile "$PERFIL" --region "$REGION" \
  --cache-control 'no-cache, must-revalidate' \
  --content-type 'text/csv; charset=utf-8'

echo "Subiendo index.html..."
aws s3 cp index.html "s3://$BUCKET/index.html" \
  --profile "$PERFIL" --region "$REGION" \
  --cache-control 'no-cache, must-revalidate' \
  --content-type 'text/html; charset=utf-8'

echo "Invalidando cache..."
ID_INVALIDACION="$(aws cloudfront create-invalidation \
  --distribution-id "$DIST" --paths '/*' \
  --profile "$PERFIL" --region "$REGION" \
  --query 'Invalidation.Id' --output text)"

echo "Esperando a que se propague ($ID_INVALIDACION)..."
aws cloudfront wait invalidation-completed \
  --distribution-id "$DIST" --id "$ID_INVALIDACION" \
  --profile "$PERFIL" --region "$REGION"

echo
echo "Listo: $URL"
