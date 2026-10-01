#!/usr/bin/env bash
# usage: ocr-batch.sh <staging-dir> <NNN>   -- ocr-remote.sh (Ausrichtung + OCR) fuer batch-NNN-merged.pdf auf OCR_HOST (ssh, default local; "local" = hier),
# danach check-order.py und Kontaktbogen. Ergebnis: batch-NNN.pdf, batch-NNN.check.txt, batch-NNN.sheet.png (Sichtpruefung:
# gedrehte Seiten rot); merged wird geloescht. Exit = check-order (1 = Tausch-/Reihenfolgeverdacht).
set -uo pipefail
D=$1; N=$2; R=${OCR_HOST:-local}; RD=scan-ocr; B=$(dirname "$0")
M="$D/batch-$N-merged.pdf"; OUT="$D/batch-$N.pdf"
MAP="$D/batch-$N-merged.map.tsv"
[ -f "$M" ] && [ -f "$MAP" ] || { echo "fehlt: $M oder $MAP"; exit 2; }
echo "$(date +%T) OCR batch-$N auf $R"
if [ "$R" = local ]; then
  "$B/ocr-remote.sh" "$M" "$MAP" "$OUT.part" | tee "$D/batch-$N.orient.txt"; [ "${PIPESTATUS[0]}" -eq 0 ] || { rm -f "$OUT.part"; echo "OCR fehlgeschlagen"; exit 3; }
else
  if ! { ssh -o BatchMode=yes "$R" "mkdir -p $RD" && scp -q "$M" "$MAP" "$B/ocr-remote.sh" "$R:$RD/"; }; then echo "upload fehlgeschlagen"; exit 3; fi
  ssh -o BatchMode=yes "$R" "cd $RD && bash ocr-remote.sh batch-$N-merged.pdf batch-$N-merged.map.tsv batch-$N.pdf; rc=\$?; rm -f batch-$N-merged.pdf batch-$N-merged.map.tsv; exit \$rc" \
    | tee "$D/batch-$N.orient.txt"; [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "OCR auf $R fehlgeschlagen"; exit 3; }
  if ! scp -q "$R:$RD/batch-$N.pdf" "$OUT.part"; then rm -f "$OUT.part"; echo "download fehlgeschlagen"; exit 3; fi
  ssh -o BatchMode=yes "$R" "rm -f $RD/batch-$N.pdf"
fi
mv "$OUT.part" "$OUT"
nix shell nixpkgs#poppler-utils -c python3 "$B/check-order.py" "$OUT" "$MAP" > "$D/batch-$N.check.txt"; rc=$?
rm -f "$M"
echo "$(date +%T) $(tail -1 "$D/batch-$N.check.txt")"
rot=$(grep -o 'drehe [0-9,]*' "$D/batch-$N.orient.txt" | sed 's/drehe //' | paste -sd, -); rm -f "$D/batch-$N.orient.txt"
"$B/contact-sheet.sh" "$OUT" "$D/batch-$N.sheet.png" "$rot" && echo "  Kontaktbogen: batch-$N.sheet.png"
# Fortsetzung ueber Batchgrenzen (Vorgaenger -> N, N -> Nachfolger, soweit deren OCR schon da ist) -> batch-<spaeterer>.cont.txt
nix shell nixpkgs#poppler-utils -c python3 "$B/check-continuation.py" "$D" "$N" | sed 's/^/  /'
exit $rc
