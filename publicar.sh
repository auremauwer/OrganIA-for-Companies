#!/usr/bin/env bash
# Publica la organizacion en GitHub Pages para que la vean todos.
#
#   ./publicar.sh
#   ./publicar.sh ~/Descargas/organia-organizacion.csv
#
# Publicar aqui es hacer commit y push: GitHub Pages reconstruye el sitio solo.
set -euo pipefail

cd "$(dirname "$0")"
ORIGEN="${1:-}"

if [[ -n "$ORIGEN" ]]; then
  if [[ ! -f "$ORIGEN" ]]; then
    echo "No encontre el archivo: $ORIGEN" >&2
    exit 1
  fi
  if [[ "$ORIGEN" == *.xlsx ]]; then
    echo "Este script publica CSV, no .xlsx." >&2
    echo "Sube el .xlsx en la aplicacion, revisa que se vea bien, y descarga" >&2
    echo "con ⚙ Descargar organizacion. Ese archivo es el que se publica." >&2
    exit 1
  fi
  cp "$ORIGEN" organia-datos.csv
  echo "Copiado $ORIGEN -> organia-datos.csv"
fi

# Revision minima: encabezado con la columna de puesto y al menos una fila.
# grep -c '' cuenta lineas aunque el archivo no termine en salto de linea.
FILAS=$(($(grep -c '' organia-datos.csv) - 1))
if [[ "$FILAS" -lt 1 ]]; then
  echo "organia-datos.csv no tiene filas de datos." >&2
  exit 1
fi
if ! head -1 organia-datos.csv | grep -qi "role\|puesto"; then
  echo "El archivo no parece traer la columna de puesto en su encabezado." >&2
  echo "Encabezado leido: $(head -1 organia-datos.csv | cut -c1-120)" >&2
  exit 1
fi

if git diff --quiet -- organia-datos.csv photos/ 2>/dev/null; then
  echo "No hay cambios en la organizacion ni en las fotos. Nada que publicar."
  exit 0
fi

echo "Publicando $FILAS personas..."
git add organia-datos.csv photos/
git commit -q -m "Actualizar la organizacion publicada ($FILAS personas)"
git push -q

URL="https://$(git remote get-url origin \
  | sed -E 's|.*github.com[:/]([^/]+)/(.+)\.git|\1.github.io/\2|')"

echo
echo "Publicado. GitHub Pages tarda un minuto en reconstruir."
echo "   $URL"
