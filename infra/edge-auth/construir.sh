#!/usr/bin/env bash
# Genera el paquete de la funcion de borde con la configuracion incrustada.
#
# Lambda@Edge no admite variables de entorno, asi que la configuracion tiene
# que quedar dentro del codigo. Este script lee los datos reales de los dos
# stacks y los sustituye en index.js.
#
#   ./infra/edge-auth/construir.sh
#
# Deja el resultado en infra/edge-auth-build/, que es lo que consume
# 'aws cloudformation package'.
set -euo pipefail

PERFIL="${PERFIL:-openbank}"
REGION="${REGION:-us-east-1}"
STACK="${STACK:-organia}"
STACK_COGNITO="${STACK_COGNITO:-organia-cognito}"

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
ORIGEN="$RAIZ/infra/edge-auth/index.js"
DESTINO_DIR="$RAIZ/infra/edge-auth-build"
ARCHIVO_SECRETO="$RAIZ/infra/.secreto-sesion"

salida() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --profile "$PERFIL" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

echo "Leyendo la configuracion de los stacks..."
DOMINIO_SITIO="$(salida "$STACK" UrlSitio | sed 's|^https://||')"
ID_POOL="$(salida "$STACK_COGNITO" IdPool)"
ID_CLIENTE="$(salida "$STACK_COGNITO" IdCliente)"
URL_LOGIN="$(salida "$STACK_COGNITO" UrlLogin)"
DOMINIO_COGNITO="${URL_LOGIN#https://}"

CLIENTE_SECRETO="$(aws cognito-idp describe-user-pool-client \
  --user-pool-id "$ID_POOL" --client-id "$ID_CLIENTE" \
  --profile "$PERFIL" --region "$REGION" \
  --query 'UserPoolClient.ClientSecret' --output text)"

for v in DOMINIO_SITIO ID_CLIENTE DOMINIO_COGNITO CLIENTE_SECRETO; do
  if [[ -z "${!v}" || "${!v}" == "None" ]]; then
    echo "Falta $v. Revisa que ambos stacks existan." >&2
    exit 1
  fi
done

# El secreto de sesion se guarda para que un redespliegue no cierre la sesion
# de todo el mundo. El archivo esta fuera de git (ver .gitignore).
if [[ -f "$ARCHIVO_SECRETO" ]]; then
  SECRETO_SESION="$(cat "$ARCHIVO_SECRETO")"
  echo "Reutilizando el secreto de sesion existente."
else
  SECRETO_SESION="$(openssl rand -hex 32)"
  printf '%s' "$SECRETO_SESION" > "$ARCHIVO_SECRETO"
  chmod 600 "$ARCHIVO_SECRETO"
  echo "Secreto de sesion nuevo generado."
fi

# Sustitucion en Python: sed se rompe si algun valor trae / o &.
mkdir -p "$DESTINO_DIR"
DOMINIO_COGNITO="$DOMINIO_COGNITO" ID_CLIENTE="$ID_CLIENTE" \
CLIENTE_SECRETO="$CLIENTE_SECRETO" DOMINIO_SITIO="$DOMINIO_SITIO" \
SECRETO_SESION="$SECRETO_SESION" ORIGEN="$ORIGEN" \
DESTINO="$DESTINO_DIR/index.js" python3 - <<'PY'
import os
codigo = open(os.environ['ORIGEN'], encoding='utf-8').read()
reemplazos = {
    '__DOMINIO_COGNITO__': os.environ['DOMINIO_COGNITO'],
    '__CLIENTE_ID__':      os.environ['ID_CLIENTE'],
    '__CLIENTE_SECRETO__': os.environ['CLIENTE_SECRETO'],
    '__DOMINIO_SITIO__':   os.environ['DOMINIO_SITIO'],
    '__SECRETO_SESION__':  os.environ['SECRETO_SESION'],
}
for marca, valor in reemplazos.items():
    if marca not in codigo:
        raise SystemExit(f'No se encontro la marca {marca} en index.js')
    codigo = codigo.replace(marca, valor)
if '__' in codigo.split('const CFG')[1].split('};')[0]:
    raise SystemExit('Quedaron marcas sin sustituir en CFG')
open(os.environ['DESTINO'], 'w', encoding='utf-8').write(codigo)
PY

node --check "$DESTINO_DIR/index.js"

echo "Paquete listo en infra/edge-auth-build/"
echo "  sitio:   $DOMINIO_SITIO"
echo "  cognito: $DOMINIO_COGNITO"
echo "  cliente: $ID_CLIENTE"
