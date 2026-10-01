#!/usr/bin/env python3
"""usage: file-docs.py <ocr.pdf> <spec.tsv> <archive-root> <journal.csv> <batch-id>
spec.tsv: <seiten>\t<relativer zielpfad|SKIP|REPLACE <alte archivdatei> => <neuer zielpfad>>[\t<grund>]. Splittet, prueft gegen den
Zielordner, legt ab, journalt. REPLACE: die alte Archivdatei (Foto, Bild-PDF ohne Textebene) wandert nach _Papierkorb/ersetzt/<pfad>,
der Scan wird ohne Dublettenpruefung unter dem neuen Pfad abgelegt (ohne " => <neu>" unter dem alten Pfad); Journal: scan-replace + move.
Dublettenpruefung mit der Wort+Zahlen-Deckung aus scanlib (wie check-archived.py): faengt auch einen zweiten Scan desselben
Papiers, nicht nur denselben PDF-Text. Gleiche Vorlage mit anderen Zahlen (Folgejahr) wird abgelegt."""
import subprocess,os,sys,shutil,glob,csv
from scanlib import wn_pages,best_page,same_paper,long_nums,L_MIN
from collections import Counter
PDF,SPEC,R,J,BATCH=sys.argv[1:6]
os.makedirs("out",exist_ok=True)
cache={}   # zielordner -> {datei: seiten}
def folder(d):
    if d not in cache:
        cache[d]={}
        for e in glob.glob(os.path.join(d,"*.[pP][dD][fF]")):
            try: pp=wn_pages(e)
            except Exception: continue
            if pp: cache[d][e]=pp
    return cache[d]
for line in open(SPEC):
    if not line.strip() or line.startswith("#"): continue
    f=line.rstrip("\n").split("\t"); pages,rel=f[0],f[1]
    if rel.upper()=="SKIP": print(f"S.{pages:6s} SKIP"); continue
    old=None
    if rel.upper().startswith("REPLACE "):
        old,_,new=rel[8:].partition(" => "); old=old.strip(); rel=new.strip() or old
        if not os.path.isfile(os.path.join(R,old)): print(f"S.{pages:6s} REPLACE verweigert, Archivdatei fehlt: {old}"); continue
        if rel!=old and os.path.exists(os.path.join(R,rel)): print(f"S.{pages:6s} REPLACE verweigert, Ziel existiert: {rel}"); continue
    dst=os.path.join(R,rel); tmp=os.path.join("out",os.path.basename(rel))
    subprocess.run(["qpdf","--empty","--pages",PDF,pages,"--",tmp],check=True)
    if old:
        bin_=os.path.join(R,"_Papierkorb","ersetzt",old); os.makedirs(os.path.dirname(bin_),exist_ok=True)
        shutil.move(os.path.join(R,old),bin_); os.makedirs(os.path.dirname(dst),exist_ok=True); shutil.copy2(tmp,dst)
        with open(J,"a",encoding="utf8",newline="") as j:
            w=csv.writer(j,lineterminator="\n")
            w.writerow(["move",os.path.join(R,old),bin_])
            w.writerow(["scan-replace",f"{BATCH} S.{pages}",rel.replace('/',chr(92))])
        print(f"S.{pages:6s} REPLACE {old} -> _Papierkorb/ersetzt; abgelegt: {rel}"); continue
    arch=folder(os.path.dirname(dst)); dup=None; doc=wn_pages(tmp)
    lo=sum((long_nums(cn) for _,cn in doc),Counter())   # Kennzahlen des ganzen Dokuments, auch von textarmen Seiten (SIM-Traeger)
    for e,pp in arch.items():
        grp=[b for b in (best_page(c,cn,{e:pp}) for c,cn in doc) if b]
        if lo and sum((lo&sum((long_nums(dn) for _,dn in pp),Counter())).values())/sum(lo.values())<L_MIN: continue
        if grp and same_paper(grp):
            mw=sum(g[0] for g in grp)/len(grp); mn=sum(g[1] for g in grp)/len(grp)
            if not dup or mn>dup[2]: dup=(os.path.basename(e),mw,mn)
    if dup: print(f"S.{pages:6s} DUP worte={dup[1]:.2f} zahlen={dup[2]:.2f} {dup[0]} -> NICHT abgelegt"); continue
    if os.path.exists(dst): print(f"S.{pages:6s} EXISTIERT -> NICHT abgelegt: {rel}"); continue
    os.makedirs(os.path.dirname(dst),exist_ok=True); shutil.copy2(tmp,dst)
    with open(J,"a",encoding="utf8",newline="") as j:
        w=csv.writer(j,lineterminator="\n")
        w.writerow(["scan",f"{BATCH} S.{pages}",rel.replace('/',chr(92))])
    print(f"S.{pages:6s} OK  {rel}")
