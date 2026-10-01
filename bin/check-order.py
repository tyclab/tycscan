#!/usr/bin/env python3
"""Paarungskontrolle Vorder-/Rueckseite (vertauschte Nachbarblaetter im Rueckseiten-Durchlauf) und Seitenfolge aus
"Seite x von y" (Luecken, Vertauschungen, Doppelte innerhalb des Batches). usage: check-order.py merged-ocr.pdf merged.map.tsv"""
import re,sys,collections
from scanlib import txt as _txt, ids, seite, toks
pdf,mapf=sys.argv[1],sys.argv[2]
def txt(p): return _txt(pdf,p)
sheets=collections.defaultdict(dict)
for l in open(mapf):
    mp,sh,side=l.split(); sheets[int(sh)][side]=txt(int(mp))
def score(F,B):
    if not B or len(B.strip())<40: return ("BLANK",99)
    i=ids(F)&ids(B); sF,sB=seite(F),seite(B)
    if i: return ("ID:"+",".join(sorted(i))[:30],3)
    if sF and sB and sF[1]==sB[1] and sB[0]==sF[0]+1: return (f"Seite {sF[0]}->{sB[0]}/{sF[1]}",3)
    c=len(toks(F)&toks(B)); 
    return (f"tokens={c}",2 if c>=4 else (1 if c>=2 else 0))
N=max(sheets); res={}
for i in range(1,N+1):
    F=sheets[i].get("F",""); B=sheets[i].get("B","")
    why,sc=score(F,B); res[i]=(why,sc)
    if sc<=1 and B:   # schwach: Tausch mit Nachbar j nur, wenn er BEIDE Paarungen verbessert und harte Belege bringt
        for j in (i-1,i+1):
            if j not in sheets or "B" not in sheets[j]: continue
            Fj,Bj=sheets[j]["F"],sheets[j]["B"]; sjj=score(Fj,Bj)[1]
            if sjj>=3: continue                       # Nachbar ist bestaetigt -> kein Tausch moeglich
            wij,sij=score(Fj,B); wji,sji=score(F,Bj)  # Tausch-Hypothese
            if sij+sji>sc+sjj and (sij==3 or sji==3): res[i]=(f"TAUSCH mit Blatt {j}: {wij} / {wji}; eigen: {why}",-1)
            elif sij+sji>sc+sjj and sij>=2 and sji>=2: res[i]=(f"pruefen: Tausch mit Blatt {j} moeglich ({wij}/{wji}); eigen: {why}",0)
bad=[i for i,(w,s) in res.items() if s<0]; weak=[i for i,(w,s) in res.items() if s==0]
for i in range(1,N+1):
    w,s=res[i]; tag={99:"leer",3:"OK",2:"ok",1:"schwach",0:"PRUEFEN",-1:"!!SWAP"}[s]
    print(f"Blatt {i:2d}  {tag:9s} {w}")
# Seitenfolge: Laeufe gleicher Gesamtseitenzahl y in Lesereihenfolge; jeder Lauf muss 1..y lueckenlos steigend sein.
order=sorted((int(mp),int(sh),side) for l in open(mapf) for mp,sh,side in [l.split()])
seq=[]   # (pdf-seite, x, y)
for mp,sh,side in order:
    t=sheets[sh].get(side,""); s_=seite(t)
    if s_: seq.append((mp,)+s_)
runs=[]
for e in seq:
    if runs and runs[-1][0][2]==e[2] and e[1]!=1: runs[-1].append(e)   # neues Dokument erkennt man an Seite 1
    else: runs.append([e])
folge=[]
for r in runs:
    y=r[0][2]; xs=[x for _,x,_ in r]; span=f"S.{r[0][0]}-{r[-1][0]}" if len(r)>1 else f"S.{r[0][0]}"
    if xs==list(range(1,y+1)): continue
    miss=sorted(set(range(1,y+1))-set(xs)); dup=sorted({x for x in xs if xs.count(x)>1})
    why=[]
    if xs!=sorted(xs): why.append("Reihenfolge "+",".join(map(str,xs)))
    if dup: why.append("doppelt "+",".join(map(str,dup)))
    if miss and len(miss)<y: why.append("fehlt "+",".join(map(str,miss)))
    if why: folge.append(f"{span} ({y} Seiten): "+"; ".join(why))
if folge:
    print("\nSeitenfolge:"); [print("  "+f) for f in folge]
print("\nERGEBNIS:", "REIHENFOLGE VERDAECHTIG, Blaetter "+str(bad) if bad else "keine Vertauschung erkannt", "| manuell pruefen:",weak or "-",
      "| Seitenfolge:", f"{len(folge)} Auffaelligkeit(en)" if folge else "ok")
sys.exit(1 if bad or folge else 0)
