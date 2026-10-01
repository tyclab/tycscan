#!/usr/bin/env python3
"""Fortsetzungserkennung zwischen Batches: laeuft ein Dokument vom Ende von batch-N in den Anfang von batch-M weiter?
usage: check-continuation.py <staging-dir> [NNN]   -- ohne NNN alle Nachbarpaare, mit NNN nur die Paare um diesen Batch.
Schreibt je Paar eine Zeile nach stdout und in batch-M.cont.txt (M = der spaetere Batch). Stufen: FORTSETZUNG (Seite x/y -> x+1/y), WAHRSCHEINLICH (gleiche Akten-/Versicherungsnummer),
MOEGLICH (Wortueberlappung), NEIN. Auch Luecken werden geprueft (bis drei Batches zurueck, Zeile mit "Luecke"), gemeldet nur wenn nicht NEIN.
Exit 0 = ueberall NEIN, sonst 1."""
import re,sys,os,glob
from scanlib import txt,pages,ids,seite,toks
D=sys.argv[1]; only=sys.argv[2] if len(sys.argv)>2 else None
nums=sorted(int(m[1]) for f in glob.glob(os.path.join(D,"batch-*.pdf")) if (m:=re.fullmatch(r"batch-(\d{3})\.pdf",os.path.basename(f))))
def pdf(n): return os.path.join(D,f"batch-{n:03d}.pdf")
def tail_text(n,k=2):   # letzte k Seiten mit Text (Rueckseiten koennen leer sein)
    P=pages(pdf(n)); out=[]
    for p in range(P,0,-1):
        t=txt(pdf(n),p)
        if len(t.strip())>=40: out.append(t)
        if len(out)>=k: break
    return out
def head_text(n,k=2):
    P=pages(pdf(n)); out=[]
    for p in range(1,P+1):
        t=txt(pdf(n),p)
        if len(t.strip())>=40: out.append(t)
        if len(out)>=k: break
    return out
def judge(a,b):
    A=tail_text(a); B=head_text(b)
    if not A or not B: return ("NEIN","kein Text am Rand")
    sA=seite(A[0]); sB=seite(B[0]); why=[]; strong=False
    if sA and sB and sA[1]==sB[1] and sB[0]==sA[0]+1: why.append(f"Seite {sA[0]}/{sA[1]} -> {sB[0]}/{sB[1]}"); strong=True
    elif sA and sA[0]==sA[1]: return ("NEIN",f"batch-{a:03d} endet mit Seite {sA[0]}/{sA[1]}")
    elif sB and sB[0]==1: return ("NEIN",f"batch-{b:03d} beginnt mit Seite 1/{sB[1]}")
    i=set().union(*map(ids,A))&set().union(*map(ids,B))
    c=len(set().union(*map(toks,A))&set().union(*map(toks,B)))
    if strong: return ("FORTSETZUNG","; ".join(why+[f"tokens={c}"]))
    if i: return ("WAHRSCHEINLICH","ID "+",".join(sorted(i))[:40]+f"; tokens={c}")   # gleiche Akte, evtl. naechstes Dokument derselben Serie
    if c>=10: return ("MOEGLICH",f"tokens={c}")
    return ("NEIN",f"tokens={c}")
rc=0
for j,b in enumerate(nums):
    lines=[]
    for back in (1,2,3):
        if j-back<0: break
        a=nums[j-back]
        if only and int(only) not in (a,b): continue
        v,why=judge(a,b)
        if back>1 and v=="NEIN": continue
        lines.append(f"batch-{a:03d} -> batch-{b:03d}: {v} ({why}{'; Luecke' if back>1 else ''})")
        if v!="NEIN": rc=1
    if lines:
        print("\n".join(lines)); open(os.path.join(D,f"batch-{b:03d}.cont.txt"),"w").write("\n".join(lines)+"\n")
sys.exit(rc)
