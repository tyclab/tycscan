#!/usr/bin/env bash
# usage: blank-pages.sh <scan.pdf> [k-schwelle=0.2] [min-mm=10]
# Leerseitenerkennung fuer Rueckseiten-Scans, zweistufig, im Zweifel INHALT:
#  1. Ghostscript ink_cov (K, intensitaetsgewichtet, keine Binarisierung): >= k-schwelle -> INHALT
#  2. sonst bei nativen 300 dpi: 3 mm Rand weg, adaptive Schwelle (Mittelwert-50), 3x3 Open gegen Rauschen,
#     1,5 mm Dilatation, Komponentenanalyse: eine zusammenhaengende Komponente >= min-mm -> INHALT (Unterschrift, Stempel,
#     Handschrift); Lochung, Druckmarken, Durchscheinen bleiben darunter -> LEER
# stdout je Seite: <seite>\t<K%>\t<max-komponente-mm>\t<LEER|INHALT>
set -euo pipefail
export LC_ALL=C
PDF=$1; KTHR=${2:-0.2}; MM=${3:-10}
exec nix shell nixpkgs#ghostscript nixpkgs#poppler-utils nixpkgs#imagemagick -c bash -c '
PDF=$1; KTHR=$2; MM=$3; T=$(mktemp -d); trap "rm -rf $T" EXIT
DPI=300; Q=4; QD=$((DPI/Q))   # Binarisierung bei 300 dpi, danach 4x zusammengefasst (jeder Tintenpixel bleibt erhalten) fuer Dilatation und Komponenten
SHAVE=$(awk -v d=$DPI "BEGIN{printf \"%d\", 3/25.4*d}"); DIL=$(awk -v d=$QD "BEGIN{printf \"%d\", 0.75/25.4*d}")
n=$(pdfinfo "$PDF" | awk "/^Pages/{print \$2}")
gs -q -o - -sDEVICE=ink_cov -r150 "$PDF" 2>/dev/null | awk "{print \$4}" > "$T/k"
for i in $(seq 1 "$n"); do
  k=$(sed -n "${i}p" "$T/k"); comp=0
  if awk -v k="$k" -v t="$KTHR" "BEGIN{exit !(k<t)}"; then
    pdftoppm -r $DPI -gray -f "$i" -l "$i" -png "$PDF" "$T/p"; f=$(ls "$T"/p*.png | head -1)
    thr=$(magick "$f" -format "%[fx:(mean*255-50)/2.55]" info:)
    comp=$(magick "$f" -shave ${SHAVE}x${SHAVE} -threshold "${thr}%" -negate -scale "$((100/Q))%" -threshold 12% -morphology Dilate "Disk:$DIL" \
      -define connected-components:area-threshold=4 -define connected-components:verbose=true -connected-components 8 null: 2>/dev/null \
      | awk -v d=$QD "/gray\(255\)|srgb\(255,255,255\)|white/ { split(\$2,g,/[x+]/); w=g[1]; h=g[2]; m=(w>h?w:h); if (m>max) max=m } END{printf \"%.1f\", max/d*25.4}")
    rm -f "$T"/p*.png
  fi
  if awk -v k="$k" -v t="$KTHR" "BEGIN{exit !(k>=t)}" || awk -v c="$comp" -v m="$MM" "BEGIN{exit !(c>=m)}"; then v=INHALT; else v=LEER; fi
  printf "%d\t%.3f\t%s\t%s\n" "$i" "$k" "$comp" "$v"
done' _ "$PDF" "$KTHR" "$MM"
