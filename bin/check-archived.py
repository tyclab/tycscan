#!/usr/bin/env python3
"""Bereits abgelegtes Papier: vergleicht jede Staging-Seite mit den Seiten der Dateien, die das Journal als abgelegt oder
digital geholt fuehrt (scan-/fetch-Zeilen). Ein zweites Mal gescannter Stapel faellt so schon in propose auf.
Zwei unabhaengige Scans sind nie zeilengleich, deshalb Wortdeckung (Anteil der Woerter der Staging-Seite, die auf der
Archivseite stehen) plus Zahlendeckung (Datum, Nummern, Betraege): gleiche Vorlage mit anderen Zahlen (Rechnung des
Folgejahres) hat hohe Wort-, aber niedrige Zahlendeckung. Aufeinanderfolgende Seiten, die auf dieselbe Datei zeigen,
werden als Dokument gemeinsam beurteilt.
usage: check-archived.py <staging-dir> <journal.csv> <archive-root> [NNN ...]  -- schreibt ARCHIVED.txt, Exit 1 bei Treffern."""
import sys,os,csv,glob
from scanlib import wn_pages as pages,best_page,same_paper
D,J,ROOT=sys.argv[1:4]; only=[n.zfill(3) for n in sys.argv[4:]]
def path(dst):
    dst=dst.strip(); return dst if dst.startswith("/") else os.path.join(ROOT,dst.replace("\\","/"))
arch={}   # datei -> (journal-quelle, seiten)
with open(J,newline="",encoding="utf-8") as f:
    for row in csv.reader(f):
        if len(row)>=3 and row[0] in ("scan","fetch"):
            p=path(row[2])
            if os.path.isfile(p) and p not in arch: arch[p]=(row[1],pages(p))
hits=[]
for pdf in sorted(glob.glob(os.path.join(D,"batch-[0-9][0-9][0-9].pdf"))):
    n=os.path.basename(pdf)[6:9]
    if only and n not in only: continue
    ap={p:pp for p,(_,pp) in arch.items()}
    best=[best_page(c,cn,ap) for c,cn in pages(pdf)]   # je seite: (w, nz, datei, archivseite) oder None
    i=0
    while i<len(best):
        if not best[i]: i+=1; continue
        k=i
        while k+1<len(best) and best[k+1] and best[k+1][2]==best[i][2] and best[k+1][3]==best[k][3]+1: k+=1
        grp=best[i:k+1]; mw=sum(g[0] for g in grp)/len(grp); mn=sum(g[1] for g in grp)/len(grp)
        if same_paper(grp):
            src,_=arch[best[i][2]]
            hits.append(f"batch-{n} S.{i+1}"+(f"-{k+1}" if k>i else "")+f" = {os.path.relpath(best[i][2],ROOT)} S.{best[i][3]}"+(f"-{best[k][3]}" if k>i else "")+f" (Journal {src}; worte={mw:.2f} zahlen={mn:.2f})")
        i=k+1
with open(os.path.join(D,"ARCHIVED.txt"),"w") as out:
    for h in hits: print("ABGELEGT: "+h); out.write(h+"\n")
print(f"{len(hits)} Treffer, {len(arch)} Journal-Dateien verglichen")
sys.exit(1 if hits else 0)
