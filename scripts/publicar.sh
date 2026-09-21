#!/bin/bash
# Mejora automáticamente (color/nitidez/compresión) las fotos y videos nuevos
# en assets/gallery/{fotos,videos-clases,ejercicios}, regenera el manifest.json
# de la Galería, y publica los cambios (nuevos y eliminados) en la rama main.
set -euo pipefail

# Homebrew no siempre está en el PATH de un doble clic (.command); lo agregamos
# si existe, para poder usar ffmpeg/magick sin que la persona tenga que hacer nada.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

GALLERY_DIR="assets/gallery"
CACHE_FILE="$GALLERY_DIR/.enhance-cache.tsv"
touch "$CACHE_FILE"

IMAGE_EXT="jpg jpeg png webp gif"
VIDEO_EXT="mp4 mov webm m4v"

ext_of() { local n="$1"; echo "${n##*.}" | tr '[:upper:]' '[:lower:]'; }
has_word() { local w="$1"; shift; for x in "$@"; do [ "$x" = "$w" ] && return 0; done; return 1; }

cache_key() {
  # ruta + tamaño + fecha de modificación: si el archivo cambia, se vuelve a procesar
  local f="$1"
  printf '%s\t%s\t%s' "$f" "$(stat -f '%z' "$f")" "$(stat -f '%m' "$f")"
}

is_cached() { grep -qxF "$1" "$CACHE_FILE" 2>/dev/null; }
remember() { printf '%s\n' "$1" >> "$CACHE_FILE"; }

enhance_image() {
  local f="$1" tmp
  tmp=$(mktemp "${f%.*}.XXXXXX.${f##*.}") || return 1
  if magick "$f" -auto-level -modulate 100,108,100 -unsharp 0x0.75+0.6+0.02 -strip -quality 87 "$tmp" 2>/tmp/movenow-enhance.log; then
    mv "$tmp" "$f"
    remember "$(cache_key "$f")"
  else
    rm -f "$tmp"
    echo "  Aviso: no pude mejorar \"$(basename "$f")\", la dejo igual."
  fi
}

enhance_video() {
  local f="$1"
  local base="${f%.*}"
  local target="${base}.mp4"
  local tmp
  tmp=$(mktemp "${base}.XXXXXX.mp4") || return 1
  if ffmpeg -y -i "$f" \
      -vf "eq=contrast=1.05:brightness=0.02:saturation=1.12,unsharp=5:5:0.6:5:5:0.0,scale='min(1920,iw)':-2" \
      -c:v libx264 -preset medium -crf 20 -c:a aac -b:a 128k -movflags +faststart \
      "$tmp" </dev/null >/tmp/movenow-enhance.log 2>&1; then
    mv "$tmp" "$target"
    if [ "$f" != "$target" ]; then rm -f "$f"; fi
    remember "$(cache_key "$target")"
  else
    rm -f "$tmp"
    echo "  Aviso: no pude mejorar \"$(basename "$f")\", la dejo igual."
  fi
}

echo "Mejorando calidad de fotos y videos nuevos..."
have_ffmpeg=1; command -v ffmpeg >/dev/null 2>&1 || have_ffmpeg=0
have_magick=1; command -v magick >/dev/null 2>&1 || have_magick=0

for sub in fotos videos-clases ejercicios; do
  dir="$GALLERY_DIR/$sub"
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 1 -type f ! -name '.*' -print0 |
    while IFS= read -r -d '' f; do
      ext=$(ext_of "$f")
      key="$(cache_key "$f")"
      if has_word "$ext" $IMAGE_EXT; then
        if [ "$have_magick" = 1 ] && ! is_cached "$key"; then
          enhance_image "$f"
        fi
      elif has_word "$ext" $VIDEO_EXT; then
        if [ "$have_ffmpeg" = 1 ] && ! is_cached "$key"; then
          enhance_video "$f"
        fi
      fi
    done
done

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
