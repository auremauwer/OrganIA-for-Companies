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

# El HTML no se cachea para que cada cambio se vea de inmediato; las fotos
# si, porque cambian poco y asi la carga es mas rapida.
echo "Subiendo fotos..."
aws s3 sync photos/ "s3://$BUCKET/photos/" \
  --profile "$PERFIL" --region "$REGION" \
  --cache-control 'public, max-age=604800' \
  --delete

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
