#!/usr/bin/env python3
"""Dubletten im Staging: Seiten mit weitgehend gleichem OCR-Text ueber alle Batches, z.B. zweimal gescannte Blaetter oder
mehrfach zugestellte Schreiben. Kandidaten ueber Wortmengen (Schwelle 0.8 bezogen auf die kleinere Seite), bestaetigt durch
gleiche Zahlen und gleiche Textfolge, weil gleiche Vorlagen sonst als Dublette durchgehen und zwei Scans nie zeichengleich sind. usage: check-dups.py <staging-dir> [schwelle=0.8]
Schreibt DUPS.txt, Exit 1 wenn Treffer."""
import re,sys,os,glob,collections
from scanlib import txt,pages
D=sys.argv[1]; THR=float(sys.argv[2]) if len(sys.argv)>2 else 0.8
W=re.compile(r"[a-zäöüß]{4,}|\d{4,}")
docs=[]   # (name, tokens)
for f in sorted(glob.glob(os.path.join(D,"batch-[0-9][0-9][0-9].pdf"))):
    n=os.path.basename(f)[6:9]
    for p in range(1,pages(f)+1):
        raw=re.sub(r"\s+"," ",txt(f,p).lower()); t=set(W.findall(raw))
        if len(t)>=30: docs.append((f"batch-{n} S.{p}",t,raw))   # Leerseiten, Stempel, duenne Formulare nicht vergleichen
# Kandidaten ueber einen invertierten Index seltener Woerter, sonst 1000x1000 Vergleiche mit grossen Mengen.
idx=collections.defaultdict(list)
for i,(_,t,_r) in enumerate(docs):
    for w in t: idx[w].append(i)
cand=collections.Counter()
for w,ids in idx.items():
    if len(ids)>20: continue   # Allerweltswoerter (Adresse, Anrede) tragen nichts bei
    for a in range(len(ids)):
        for b in range(a+1,len(ids)): cand[(ids[a],ids[b])]+=1
# Gleiche Vorlage (Rechnungen einer Praxis, Bescheide einer Behoerde) teilt fast alle Woerter und die Zahlen des
# Briefkopfs. Entscheidend sind die kennzeichnenden Zahlen (Rechnungsnummer, Datum, Betrag, Versicherungsnummer: auf
# hoechstens 12 Seiten, ein mehrseitiger Brief in zwei Kopien liegt darunter): weichen sie ab, ist es eine andere Rechnung
# derselben Praxis; sind sie gleich, ist es dieselbe Seite. Ohne kennzeichnende Zahlen zaehlt nur eine fast identische Textfolge.
import difflib
NUM=re.compile(r"\d[\d.,/-]{2,}\d")
nums=[set(NUM.findall(r)) for _,_,r in docs]
df=collections.Counter()
for ns in nums: df.update(ns)
key=[{x for x in ns if df[x]<=12} for ns in nums]
hits=[]
for (a,b),c in cand.items():
    ta,tb=docs[a][1],docs[b][1]
    if c<5: continue
    sim=len(ta&tb)/min(len(ta),len(tb))
    if sim<THR: continue
    ka,kb=key[a],key[b]; same=ka&kb; diff=ka^kb
    if same or diff:
        # eine Abweichung kann OCR-Rauschen sein, wenn genug uebereinstimmt; zwei sind ein anderes Dokument
        if len(diff)>=2 or (diff and len(same)<3): continue
        why=f"gleiche Kennzahlen {','.join(sorted(same))[:40]}"+(f", abweichend {','.join(diff)}" if diff else "")
    else:
        seq=difflib.SequenceMatcher(None,docs[a][2],docs[b][2],autojunk=False).quick_ratio()
        if seq<0.95 or sim<0.9: continue
        why=f"Textfolge {seq:.2f}"
    hits.append((sim,docs[a][0],docs[b][0],why))
hits.sort(key=lambda h:(h[1],h[2]))
with open(os.path.join(D,"DUPS.txt"),"w") as out:
    for sim,a,b,why in hits:
        line=f"DUBLETTE {sim:.2f}: {a} = {b} ({why})"; print(line); out.write(line+"\n")
print(f"{len(hits)} Dubletten-Paar(e), Schwelle {THR}")
sys.exit(1 if hits else 0)
