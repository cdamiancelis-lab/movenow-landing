#!/bin/bash
# Regenera la galería (assets/gallery/manifest.json) a partir de lo que haya
# en assets/gallery/fotos, /videos-clases y /ejercicios, y publica los
# cambios (nuevos y eliminados) en la rama main del sitio.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

GALLERY_DIR="assets/gallery"

json_array_for_dir() {
  local dir="$1"
  local tmp
  tmp=$(mktemp)
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f ! -name '.*' -print0 |
      while IFS= read -r -d '' f; do
        mtime=$(stat -f '%m' "$f")
        printf '%s\t%s\n' "$mtime" "$f" >> "$tmp"
      done
  fi
  local first=1
  printf '['
  if [ -s "$tmp" ]; then
    while IFS=$'\t' read -r _ path; do
      name=$(basename "$path")
      esc=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
      if [ $first -eq 1 ]; then first=0; else printf ','; fi
      printf '"%s"' "$esc"
    done < <(sort -t $'\t' -k1,1rn "$tmp")
  fi
  printf ']'
  rm -f "$tmp"
}

echo "Buscando fotos y videos nuevos..."
{
  printf '{\n'
  printf '  "fotos": %s,\n' "$(json_array_for_dir "$GALLERY_DIR/fotos")"
  printf '  "clases": %s,\n' "$(json_array_for_dir "$GALLERY_DIR/videos-clases")"
  printf '  "ejercicios": %s\n' "$(json_array_for_dir "$GALLERY_DIR/ejercicios")"
  printf '}\n'
} > "$GALLERY_DIR/manifest.json"

echo "Actualizando con la última versión del sitio..."
git pull --ff-only origin main

git add -A "$GALLERY_DIR"

if git diff --cached --quiet; then
  echo ""
  echo "No hay fotos ni videos nuevos para publicar."
else
  git commit -m "Actualizar galería con nuevas fotos/videos" --quiet
  echo "Publicando en el sitio..."
  git push origin main --quiet
  echo ""
  echo "¡Listo! En uno o dos minutos se verá en la web."
fi
