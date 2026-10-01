#!/usr/bin/env bash
# usage: ocr-remote.sh <merged.pdf> <merged.map.tsv> <out.pdf>   -- laeuft auf dem OCR-Host (OCR_HOST per ssh oder lokal)
# 1. Ausrichtung pro Seite per OCR-Konfidenz: jede Seite in 0 und 180 Grad erkennen, die Richtung mit deutlich hoeherer
#    Wortkonfidenz gewinnt. Unentschiedene Seiten (Leerseiten, Raster, Codes) folgen der Mehrheit ihres Durchgangs
#    (F = Vorderseiten, B = Rueckseiten), ohne Mehrheit dem Standardweg (F aufrecht, B auf dem Kopf). Tesseracts OSD ist
#    auf diesen Scans unbrauchbar, ocrmypdf --rotate-pages verliert bei vorhandenem /Rotate den Textlayer.
# 2. qpdf setzt /Rotate fuer die betroffenen Seiten, dann ocrmypdf ohne --rotate-pages.
set -uo pipefail
IN=$1; MAP=$2; OUT=$3; LANGS=${OCR_LANG:-deu+eng}
exec nix shell nixpkgs#ocrmypdf nixpkgs#tesseract nixpkgs#ghostscript nixpkgs#poppler-utils nixpkgs#qpdf nixpkgs#imagemagick -c bash -c '
IN=$1; MAP=$2; OUT=$3; LANGS=$4; T=$(mktemp -d); trap "rm -rf $T" EXIT; export LC_ALL=C
# Tesseract oeffnet pro Prozess alle Kerne (OpenMP); bei einem Prozess je Kern wuerde die Kiste nur noch thrashen.
export OMP_THREAD_LIMIT=1
# Summe der Wortkonfidenzen: eine aufrechte Textseite liefert viele sichere Woerter, auf dem Kopf nur wenige unsichere.
conf() { tesseract "$1" - -l "${LANGS%%+*}" --psm 3 tsv 2>/dev/null | awk -F"\t" "NR>1 && \$1==5 && \$11>=0 {s+=\$11} END{printf \"%.0f\", s}"; }
one() { local p=$1; pdftoppm -r 150 -gray -f "$p" -l "$p" -png "$IN" "$T/s$p"; local f; f=$(ls "$T"/s$p-*.png | head -1)
  local x0 x180; x0=$(conf "$f"); magick "$f" -rotate 180 "$T/r$p.png"; x180=$(conf "$T/r$p.png"); rm -f "$f" "$T/r$p.png"
  echo "$p $x0 $x180"; }
export -f conf one; export IN T LANGS
N=$(pdfinfo "$IN" | awk "/^Pages/{print \$2}")
seq 1 "$N" | xargs -P "$(nproc)" -I{} bash -c "one {}" | sort -n > "$T/conf.txt"
# eindeutig = eine Richtung mindestens doppelt so sicher (+200): Raster, Barcodes und Leerseiten sind in beiden Richtungen gleich.
rot=()
for side in F B; do
  mapfile -t P < <(awk -v s=$side "\$3==s{print \$1}" "$MAP"); n=${#P[@]}; [ $n -eq 0 ] && continue
  up=(); down=(); und=(); c0=0; c180=0
  for p in "${P[@]}"; do read -r _ x0 x180 < <(grep "^$p " "$T/conf.txt")
    if [ "$x0" -ge $((2*x180+200)) ]; then up+=("$p"); c0=$((c0+x0)); elif [ "$x180" -ge $((2*x0+200)) ]; then down+=("$p"); c180=$((c180+x180)); else und+=("$p"); fi
  done
  if [ ${#up[@]} -eq 0 ] && [ ${#down[@]} -eq 0 ]; then dflt=$([ $side = B ] && echo 1 || echo 0); why="keine Textseite, Standardannahme fuer ${#und[@]} Seiten"
  else dflt=$([ ${#down[@]} -gt ${#up[@]} ] && echo 1 || echo 0); why="${#up[@]} aufrecht, ${#down[@]} auf dem Kopf, ${#und[@]} unentschieden folgen $([ $dflt = 1 ] && echo 180 || echo 0)"; fi
  rot+=("${down[@]}"); [ $dflt = 1 ] && rot+=("${und[@]}")
  echo "  ausrichtung $side: $n Seiten, $why$([ ${#down[@]} -gt 0 ] && echo "; drehe $(IFS=,; echo "${down[*]}")")"
done
SRC=$IN
if [ ${#rot[@]} -gt 0 ]; then qpdf "$IN" --rotate=+180:$(IFS=,; echo "${rot[*]}") "$T/rot.pdf"; rc=$?; { [ $rc -eq 0 ] || [ $rc -eq 3 ]; } && SRC="$T/rot.pdf"; fi
ocrmypdf -q -l "$LANGS" --deskew --optimize 1 --output-type pdf "$SRC" "$OUT"' _ "$IN" "$MAP" "$OUT" "$LANGS"
