#!/usr/bin/env bash
# usage: contact-sheet.sh <batch.pdf> <out.png> [gedrehte-seiten,kommagetrennt]
# Kontaktbogen fuer die Sichtpruefung: alle Seiten als Miniaturen in Lesereihenfolge, Seitennummer
# darunter, per Ausrichtungs-Vote gedrehte Seiten rot umrandet. Ausrichtung und Reihenfolge sind mit einem Blick pruefbar.
set -euo pipefail
PDF=$1; OUT=$2; ROT=",${3:-},"
exec nix shell nixpkgs#poppler-utils nixpkgs#imagemagick nixpkgs#dejavu_fonts -c bash -c '
PDF=$1; OUT=$2; ROT=$3; T=$(mktemp -d); trap "rm -rf $T" EXIT
# ImageMagick findet ohne Fontconfig keine Schrift; der Pfad kommt aus dem dejavu_fonts-Paket im PATH.
FONT=$(dirname "$(command -v fc-query 2>/dev/null || echo "$(echo "$PATH" | tr : "\n" | grep dejavu-fonts- | head -1)/x")")/../share/fonts/truetype/DejaVuSans.ttf
[ -f "$FONT" ] || FONT=$(find /nix/store -maxdepth 6 -name DejaVuSans.ttf 2>/dev/null | head -1)
pdftoppm -r 14 -gray -png "$PDF" "$T/p"
for f in "$T"/p-*.png; do n=${f##*/p-}; n=${n%.png}; n=$((10#$n))
  col=gray60; lbl=$n; [[ "$ROT" == *",$n,"* ]] && { col=red; lbl="$n (180)"; }
  magick "$f" -bordercolor "$col" -border 4 -background white -gravity south -splice 0x18 \
    -font "$FONT" -pointsize 13 -fill "$col" -annotate +0+2 "$lbl" "$T/t-$(printf %04d $n).png"
done
magick montage -font "$FONT" "$T"/t-*.png -tile 8x -geometry +6+6 -background white "$OUT"' _ "$PDF" "$OUT" "$ROT"
