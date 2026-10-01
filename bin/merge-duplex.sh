#!/usr/bin/env bash
# usage: merge-duplex.sh A.pdf B.pdf out.pdf   (B = Rueckseiten, Ausgabestapel unveraendert eingelegt => umgekehrte Reihenfolge)
# Leerseiten entscheidet blank-pages.sh (zweistufig, im Zweifel behalten); die Ausrichtung entscheidet spaeter ocr-remote.sh.
# Ausgabe: Zeile 1 Zusammenfassung, dann je verworfener Rueckseite eine "leer:"-Zeile mit den Messwerten.
set -euo pipefail
export LC_ALL=C
A=$1; B=$2; OUT=$3; BIN=$(dirname "$0")
nix shell nixpkgs#poppler-utils nixpkgs#qpdf -c bash -c '
A=$1; B=$2; OUT=$3; BIN=$4
nA=$(pdfinfo "$A" 2>/dev/null | awk "/^Pages/{print \$2}"); nB=$(pdfinfo "$B" 2>/dev/null | awk "/^Pages/{print \$2}")
[ "$nA" = "$nB" ] || { echo "SEITENZAHL UNGLEICH: A=$nA B=$nB"; exit 6; }
declare -A V K C
while IFS=$'"'"'\t'"'"' read -r p k c v; do V[$p]=$v; K[$p]=$k; C[$p]=$c; done < <("$BIN/blank-pages.sh" "$B")
args=(); kept=0; dropped=(); : > "${OUT%.pdf}.map.tsv"; mp=0
for i in $(seq 1 "$nA"); do
  j=$((nA+1-i))
  args+=("$A" "$i"); mp=$((mp+1)); printf "%s\t%s\tF\n" $mp $i >> "${OUT%.pdf}.map.tsv"
  if [ "${V[$j]}" = LEER ]; then dropped+=("blatt$i:rueck=B$j tinte=${K[$j]}% komponente=${C[$j]}mm")
  else args+=("$B" "$j"); kept=$((kept+1)); mp=$((mp+1)); printf "%s\t%s\tB\n" $mp $i >> "${OUT%.pdf}.map.tsv"; fi
done
qpdf --empty --pages "${args[@]}" -- "$OUT"
echo "blaetter=$nA rueckseiten_behalten=$kept rueckseiten_leer=${#dropped[@]} out_seiten=$(pdfinfo "$OUT" | awk "/^Pages/{print \$2}")"
for d in "${dropped[@]}"; do echo "  leer: $d"; done' _ "$A" "$B" "$OUT" "$BIN"
