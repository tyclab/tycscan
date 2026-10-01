#!/usr/bin/env bash
# Stapel-Schleife am Drucker: A scannen, wenden, B scannen, mergen, pruefen, OCR. Ohne Claude.
# usage: scan-batch.sh [staging-dir]   (Ende: q oder Strg-C; ein Neustart setzt bei liegengebliebenem A/B fort)
# Ausrichtung, OCR + Reihenfolgepruefung laufen per ocr-batch.sh im Hintergrund auf OCR_HOST (default local), Ergebnis in batch-NNN.check.txt.
set -uo pipefail
D=${1:-$HOME/scan-staging}; B=$(dirname "$0"); [ -x "$B/escl-scan.sh" ] || B=$(dirname "$(command -v escl-scan.sh)"); mkdir -p "$D"; export LC_ALL=C
pages() { nix shell nixpkgs#poppler-utils -c pdfinfo "$1" 2>/dev/null | awk '/^Pages/{print $2}'; }
PA='Stapel einlegen (max 35 Blatt pro Portion, nichts Klebriges) und Enter (q=Ende): '
PB='  Ausgabestapel UNVERAENDERT (nicht drehen, nicht sortieren) in den Einzug, bei >35 Blatt die OBERE Portion zuerst, und Enter (q=Ende): '
n=; trap 'echo; echo "  abgebrochen. Neustart setzt bei batch-$n fort."; exit 130' INT
# scan <A|B> <prompt>: ein Durchgang aus beliebig vielen ADF-Portionen (>35 Blatt), zusammengefuegt zu batch-NNN-<A|B>.pdf.
# Ein Stau wiederholt nur die aktuelle Portion; q bricht ab (fertige Dateien bleiben fuer Resume).
# Waehrend des Scans getippte Zeichen (z.B. ein frueh gedruecktes f) landen sonst im naechsten Prompt.
ask() { while read -r -t 0; do read -r _; done; read -rp "$1" x; }
scan() { local f="$D/batch-$n-$1.pdf" p=$2 x i=0 tot=0 ref='' parts=()
  [ "$1" = B ] && ref=" (A hat $(pages "$D/batch-$n-A.pdf"), f erst danach)"
  rm -f "$f" "$D/batch-$n-$1-p"*.pdf
  while :; do
    ask "$p"; [ "$x" = q ] && return 1
    [ "$x" = f ] && [ ${#parts[@]} -gt 0 ] && break
    if [ "$x" = x ] && [ ${#parts[@]} -gt 0 ]; then   # letzte Portion verwerfen (z.B. gestautes Blatt doch durchgelaufen)
      tot=$((tot-$(pages "${parts[-1]}"))); rm -f "${parts[-1]}"; unset 'parts[-1]'; i=$((i-1))
      p="  letzte Portion verworfen, bisher $tot Seiten$ref. Ab dem verworfenen Blatt neu einlegen und Enter, f=Durchgang $1 fertig, q=Ende: "; continue; fi
    "$B/escl-scan.sh" "$D/batch-$n-$1-p$((i+1)).pdf" 300; rc=$?
    if [ $rc -eq 0 ] || [ $rc -eq 7 ]; then i=$((i+1)); parts+=("$D/batch-$n-$1-p$i.pdf"); pn=$(pages "$D/batch-$n-$1-p$i.pdf"); tot=$((tot+pn))
      if [ $rc -eq 7 ]; then   # Stau: Portion bis zum Stau ist gesichert, der Rest kommt als naechste Portion
        p="  Stau: $pn Seiten dieser Portion gesichert, bisher $tot Seiten$ref. Liegen genau $pn Blaetter davon im Ausgabefach: gestautes Blatt und Rest einlegen, Enter. Sonst x = letzte Portion verwerfen. f=fertig, q=Ende: "
      else p="  ${#parts[@]}. Portion ok, bisher $tot Seiten$ref. Naechste Portion einlegen und Enter, f=Durchgang $1 fertig, q=Ende: "; fi
    else echo "  $1 fehlgeschlagen -> diese Portion nochmal"; fi
  done
  [ ${#parts[@]} -eq 1 ] && { mv "${parts[0]}" "$f"; return 0; }
  nix shell nixpkgs#qpdf -c qpdf --empty --pages "${parts[@]}" -- "$f" 2>/dev/null; rc=$?   # 3 = nur Warnungen (Canon-JPEGs), Datei ist ok
  if { [ $rc -eq 0 ] || [ $rc -eq 3 ]; } && [ "$(pages "$f")" = "$tot" ]; then rm -f "${parts[@]}"; echo "  $1: ${#parts[@]} Portionen, $tot Seiten"
  else echo "  !! Portionen von $1 nicht zusammenfuegbar (qpdf rc=$rc, Seiten=$(pages "$f") statt $tot); Durchgang $1 neu"; rm -f "$f"; return 1; fi; }
ocr_running() { pgrep -f "ocr-batch.sh $D $1" > /dev/null; }
while :; do
  for m in "$D"/batch-*-merged.pdf; do [ -f "$m" ] || continue; k=${m##*batch-}; k=${k%%-*}
    if ocr_running "$k"; then echo "  OCR laeuft: batch-$k"; elif [ ! -f "$D/batch-$k.pdf" ]; then echo "  !! OCR batch-$k haengt/abgebrochen, siehe batch-$k.ocr.log (Neustart des Skripts bietet Wiederholung an)"; fi; done
  for c in "$D"/batch-*.check.txt; do [ -f "$c" ] && [ "$c" -nt "$D/.scan-batch-seen" ] && echo "  $(basename "$c" .check.txt): $(tail -1 "$c")"; done
  for c in "$D"/batch-*.cont.txt; do [ -f "$c" ] && [ "$c" -nt "$D/.scan-batch-seen" ] && ! grep -q ": NEIN" "$c" && echo "  !! $(cat "$c")"; done; touch "$D/.scan-batch-seen"
  # Portionen eines nicht mit f beendeten Durchgangs (q, Strg-C) werden zum Durchgang zusammengefuegt statt
  # verworfen; der Resume-Prompt bietet dann Mergen oder Neuscannen an. Reste eines vorhandenen Durchgangs weg.
  for pf in "$D"/batch-*-[AB]-p1.pdf; do [ -f "$pf" ] || continue; whole=${pf%-p1.pdf}.pdf
    if [ ! -f "$whole" ]; then ps=("${pf%-p1.pdf}"-p[0-9]*.pdf)
      nix shell nixpkgs#qpdf -c qpdf --empty --pages "${ps[@]}" -- "$whole" 2>/dev/null; rc=$?
      if { [ $rc -eq 0 ] || [ $rc -eq 3 ]; } && [ -n "$(pages "$whole")" ]; then echo "  $(basename "$whole" .pdf): ${#ps[@]} Portion(en) mit $(pages "$whole") Seiten uebernommen"; else rm -f "$whole"; fi
    fi; done
  rm -f "$D"/batch-*-[AB]-p[0-9]*.pdf "$D"/batch-*-[AB]-p[0-9]*.pdf.fix
  last=$(printf "%s\n" "$D"/batch-*.pdf | grep -oE 'batch-[0-9]{3}' | sort -u | tail -1 | cut -d- -f2)
  n=$(printf '%03d' $((10#${last:-0}+1))); step=A
  if [ -n "$last" ] && [ -f "$D/batch-$last-merged.pdf" ] && [ ! -f "$D/batch-$last.pdf" ] && ! ocr_running "$last"; then
    ask $'\n'"[batch-$last] gemergt, OCR fehlt oder abgebrochen. Enter = OCR neu starten, s = ueberspringen, q = Ende: "
    case $x in q) exit 0;; s) ;; *) n=$last; step=O;; esac
  elif [ -n "$last" ] && [ ! -f "$D/batch-$last.pdf" ] && [ ! -f "$D/batch-$last-merged.pdf" ] && [ -f "$D/batch-$last-A.pdf" ] && [ -n "$(pages "$D/batch-$last-A.pdf")" ]; then
    n=$last; nb=$(pages "$D/batch-$n-B.pdf")
    if [ -n "$nb" ]; then ask $'\n'"[batch-$n] A ($(pages "$D/batch-$n-A.pdf") Seiten) und B ($nb Seiten) vorhanden. Enter = mergen, b = B neu scannen, a = A neu scannen, q = Ende: "
    else ask $'\n'"[batch-$n] A ($(pages "$D/batch-$n-A.pdf") Seiten) vorhanden, B fehlt. Enter = B scannen, a = A neu scannen, q = Ende: "; fi
    case $x in q) exit 0;; a) rm -f "$D/batch-$n-"[AB]*.pdf; step=A;; b) step=B;; *) step=B; [ -n "$nb" ] && step=M;; esac
  fi
  while :; do
    case $step in
      A) scan A $'\n'"[batch-$n] $PA" || exit 0; step=B;;
      B) scan B "$PB" || exit 0; step=M;;
      M) rm -f "$D/batch-$n-merged.pdf"
         echo "  merge, Leerseiten werden geprueft ..."
         "$B/merge-duplex.sh" "$D/batch-$n-A.pdf" "$D/batch-$n-B.pdf" "$D/batch-$n-merged.pdf" 2>/dev/null; rc=$?
         [ $rc -eq 0 ] && { step=O; continue; }
         echo "  A=$(pages "$D/batch-$n-A.pdf") B=$(pages "$D/batch-$n-B.pdf") Seiten: Doppeleinzug? Der kleinere Stapel ist meist der falsche."
         ask '  a = A neu (Ausgabestapel unveraendert einlegen), b = B neu, w = weiter nur mit Vorderseiten, q = Ende: '
         case $x in a) scan A "$PB" || exit 0;; b) step=B;;
           w) cp "$D/batch-$n-A.pdf" "$D/batch-$n-merged.pdf"; seq 1 "$(pages "$D/batch-$n-A.pdf")" | awk '{print $1"\t"$1"\tF"}' > "$D/batch-$n-merged.map.tsv"
              echo "  Rueckseiten verworfen, $(pages "$D/batch-$n-A.pdf") Vorderseiten"; step=O;;
           q) exit 0;; esac;;
      O) # OCR laeuft auf OCR_HOST im Hintergrund weiter, der naechste Stapel kann sofort eingelegt werden.
         (setsid nohup "$B/ocr-batch.sh" "$D" "$n" > "$D/batch-$n.ocr.log" 2>&1 &)
         echo "  OCR fuer batch-$n laeuft im Hintergrund auf ${OCR_HOST:-local} (Log: batch-$n.ocr.log)"; break;;
    esac
  done
done
