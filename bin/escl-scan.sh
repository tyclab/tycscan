#!/usr/bin/env bash
# usage: escl-scan.sh <out.pdf> [dpi]   -- scannt den kompletten ADF-Stapel in eine PDF
# exit: 2 scanner nicht idle, 3 ADF leer/Stau gemeldet, 4 job abgelehnt, 5 HTTP, 6 Stau ohne Seiten (Datei geloescht),
#       7 Stau nach n>=1 vollstaendigen Seiten (Datei bleibt, Aufrufer setzt mit dem Rest fort)
set -euo pipefail
OUT=$1; DPI=${2:-300}; P=${ESCL_BASE:-}
[ -n "$P" ] || { echo "ESCL_BASE nicht gesetzt (z.B. export ESCL_BASE=http://<scanner-ip>/eSCL)"; exit 2; }
pages() { nix shell nixpkgs#poppler-utils -c pdfinfo "$1" 2>/dev/null | awk '/^Pages/{print $2}' || true; }
# Jeder Abbruch (auch set -e) laesst keine halbe PDF zurueck; die Meldung kommt vom jeweiligen Pfad.
trap 'case $? in 0|7) ;; *) rm -f "$OUT";; esac' EXIT
# Nach einem Stau bleibt der Scanner Sekunden bis Minuten "Processing"; erst dann ist der Einzug wieder frei.
for i in $(seq 1 30); do
  st=$(curl -s -m 8 "$P/ScannerStatus") || st=
  grep -q '<pwg:State>Idle' <<<"$st" && break
  [ "$i" -eq 1 ] && echo "  warte auf Scanner (Stau beheben, Klappe schliessen) ..."
  sleep 3
done
grep -q '<pwg:State>Idle' <<<"$st" || { echo "scanner nicht idle"; exit 2; }
grep -q 'ScannerAdfJam' <<<"$st" && { echo "Stau noch gemeldet: Klappe auf, Papier raus, Klappe zu"; exit 3; }
grep -q 'ScannerAdfLoaded' <<<"$st" || { echo "ADF leer"; exit 3; }
XML=$(cat <<X
<?xml version="1.0" encoding="UTF-8"?>
<scan:ScanSettings xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
 <pwg:Version>2.6</pwg:Version><scan:Intent>Document</scan:Intent>
 <pwg:InputSource>Feeder</pwg:InputSource><scan:ColorMode>Grayscale8</scan:ColorMode>
 <pwg:DocumentFormat>application/pdf</pwg:DocumentFormat>
 <scan:XResolution>$DPI</scan:XResolution><scan:YResolution>$DPI</scan:YResolution>
 <pwg:ScanRegions><pwg:ScanRegion><pwg:XOffset>0</pwg:XOffset><pwg:YOffset>0</pwg:YOffset>
 <pwg:Width>2480</pwg:Width><pwg:Height>3507</pwg:Height>
 <pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits></pwg:ScanRegion></pwg:ScanRegions>
</scan:ScanSettings>
X
)
LOC=$(curl -s -m 30 -D - -o /dev/null -X POST -H 'Content-Type: text/xml' --data-binary "$XML" "$P/ScanJobs" \
      | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')
[ -n "$LOC" ] || { echo "job abgelehnt"; exit 4; }
echo "  scanne ... (Stau: Klappe oeffnen, Papier raus; das Skript merkt es selbst)"
# Strg-C mitten im Download: halbe PDF weg, Job am Geraet abbrechen, sonst haengt der naechste Start.
trap 'rm -f "$OUT"; curl -s -m 5 -X DELETE "$LOC" -o /dev/null || true; exit 130' INT TERM
code=$(curl -s -m 900 -o "$OUT" -w '%{http_code}' "$LOC/NextDocument")
[ "$code" = 200 ] || { echo "NextDocument HTTP $code"; rm -f "$OUT"; exit 5; }
curl -s -m 60 -o /dev/null "$LOC/NextDocument" || true   # Job sauber abschliessen
trap - INT TERM
st=$(curl -s -m 8 "$P/ScannerStatus")
adf=$(grep -oE 'ScannerAdf[A-Za-z]+' <<<"$st" | head -1); job=$(grep -oE '<pwg:JobStateReason>[^<]*' <<<"$st" | head -1 | sed 's/.*>//')
n=$(pages "$OUT" || true)
echo "seiten=${n:-0} bytes=$(stat -c %s "$OUT") adf=$adf job=$job"
# Bei Stau liefert das Geraet trotzdem HTTP 200 und eine abgeschnittene PDF.
# Die bis zum Stau gelieferten Seiten sind vollstaendig, aber der PDF fehlt der Trailer (kein startxref):
# qpdf baut die Struktur neu, sonst scheitern pdftoppm/merge daran. qpdf meldet Canon-JPEGs immer als
# "corrupt" und endet mit 3 (Warnungen), das ist kein Fehler.
if [ "$adf" = ScannerAdfJam ] || [ "$job" != JobCompletedSuccessfully ] || [ -z "$n" ] || [ "$n" -lt 1 ]; then
  if [ "${n:-0}" -ge 1 ]; then
    rc=0; nix shell nixpkgs#qpdf -c qpdf "$OUT" "$OUT.fix" 2>/dev/null || rc=$?   # || haelt set -e fern
    if { [ $rc -eq 0 ] || [ $rc -eq 3 ]; } && [ "$(pages "$OUT.fix")" = "$n" ]; then
      mv -f "$OUT.fix" "$OUT"; echo "STAU nach $n Seiten, die sind gesichert"; exit 7
    fi
    rm -f "$OUT.fix"; echo "STAU nach $n Seiten, PDF nicht reparierbar"
  fi
  rm -f "$OUT"; echo "STAU/ABBRUCH ohne Seiten: Papier entfernen, Portion neu einlegen"; exit 6
fi
# Erfolg mit noch geladenem ADF: das Geraet hat vorzeitig beendet, der Rest liegt noch im Einzug.
if [ "$adf" = ScannerAdfLoaded ]; then echo "  ADF noch geladen: Rest liegt noch im Einzug, einfach Enter fuer die naechste Portion"; fi
exit 0
