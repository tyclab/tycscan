"""Gemeinsame Textheuristiken fuer check-order.py, check-continuation.py, check-archived.py und file-docs.py
(Seitentext, IDs, Seite x von y, Tokens, Wort+Zahlen-Deckung gegen abgelegte PDFs)."""
import re,subprocess
from collections import Counter
import os
# Allerweltswoerter, die keine zwei Seiten verbinden. Eigene Ergaenzungen (Name, Strasse, Ort des Empfaengers stehen auf
# jedem Brief) kommen aus SCAN_STOPWORDS, leerzeichengetrennt, kleingeschrieben.
STOP=set("seite unserer unseren ihrer ihren ihnen dieser diesem dieses einer einem eines werden wurden koennen können bitte sowie durch nicht sehr geehrte geehrter herrn frau deutschland telefon telefax e-mail internet datum betrag euro gesamt".split())
STOP|=set(os.environ.get("SCAN_STOPWORDS","").lower().split())
def txt(pdf,p):
    return subprocess.run(["pdftotext","-f",str(p),"-l",str(p),pdf,"-"],capture_output=True,text=True).stdout
def pages(pdf):
    out=subprocess.run(["pdfinfo",pdf],capture_output=True,text=True).stdout
    m=re.search(r"^Pages:\s+(\d+)",out,re.M); return int(m[1]) if m else 0
def ids(t):
    out=set()
    for m in re.findall(r"\b(?:[A-Z]{1,3}[\s-]?)?\d[\d /.\-]{5,}\d\b",t):
        d=re.sub(r"\D","",m)
        if 7<=len(d)<=22 and not re.fullmatch(r"(\d{2}){3,4}",d): out.add(d)
    out|={m.upper() for m in re.findall(r"\b(?:KV|S0|A6|Nr\.?)\s?\d{6,}\b",t)}
    return out
def seite(t):
    # "Seite 2 von 5", "Seite 2/5", "Blatt 2 von 5", "Page 2 of 5", "S. 2/5"; OCR liest "von" auch als "v0n"/"vom"
    m=re.search(r"(?:Seite|Blatt|Page|S\.)\s*(\d{1,3})\s*(?:von|vom|v0n|of|/)\s*(\d{1,3})\b",t,re.I)
    if m and 1<=int(m[1])<=int(m[2])<=200: return (int(m[1]),int(m[2]))
    return None
def toks(t): return {w for w in re.findall(r"[A-Za-zÄÖÜäöüß]{6,}",t.lower()) if w not in STOP}

# Zweiter Scan desselben Papiers: zwei unabhaengige Scans sind nie zeilengleich, deshalb Wortdeckung (Anteil der Woerter der
# Staging-Seite, die auf der Archivseite stehen) plus Zahlendeckung (Datum, Nummern, Betraege). Gleiche Vorlage mit anderen
# Zahlen (Rechnung des Folgejahres) hat hohe Wort-, aber niedrige Zahlendeckung. Schwellen kalibriert an einem Zweitscan
# eines bereits abgelegten Stapels (alle Seiten Treffer) gegen zwei Jahrgaenge derselben Versicherer-Vorlage (zahlen 0.25-0.45, kein Treffer).
# Zusaetzlich muessen die langen Kennzahlen (>=7 Ziffern: SIM-, Versicherungs-, Rechnungs-, Kundennummern) der Staging-Seite
# auf der Archivseite stehen: zwei SIM-Briefe derselben Vorlage teilen Woerter und Kleinzahlen (Datum, Hotline), nicht die SIM-Nr.
W4=re.compile(r"[a-zäöüß]{4,}"); NUM=re.compile(r"\d[\d.,/-]{2,}\d")
MIN_WORDS=15; W_MIN=0.75; N_MIN_DOC=0.6; N_MIN_PAGE=0.7; L_MIN=0.5
def long_nums(cn):
    """Kennzahlen mit >=7 Ziffern."""
    return Counter({k:v for k,v in cn.items() if len(re.sub(r"\D","",k))>=7})
def wn_pages(pdf):
    """Je Seite (Counter Woerter, Counter Zahlen); leere Schlussseiten entfallen."""
    t=subprocess.run(["pdftotext",pdf,"-"],capture_output=True,text=True).stdout.lower()
    out=[(Counter(W4.findall(x)),Counter(NUM.findall(x))) for x in t.split("\f")]
    while out and not out[-1][0]: out.pop()
    return out
def best_page(c,cn,arch):
    """Beste Archivseite zu einer Staging-Seite: (wortdeckung, zahlendeckung, datei, seite, kennzahldeckung|None) oder
    None (zu wenig Text / unter W_MIN). arch: {datei: [(woerter, zahlen), ...]}."""
    tot=sum(c.values())
    if tot<MIN_WORDS: return None
    b=(0,0,None,None,None)
    for f,pp in arch.items():
        for j,(d,dn) in enumerate(pp,1):
            w=sum((c&d).values())/tot
            if w>b[0]:
                lo=long_nums(cn); l=sum((lo&long_nums(dn)).values())/sum(lo.values()) if lo else None
                b=(w,sum((cn&dn).values())/max(1,sum(cn.values())),f,j,l)
    return b if b[0]>=W_MIN else None
def same_paper(grp):
    """Dokument aus n Seiten-Treffern (best_page-Tupel) ist dasselbe Papier, wenn Wort-, Zahlen- und Kennzahldeckung reichen."""
    if not grp: return False
    mw=sum(g[0] for g in grp)/len(grp); mn=sum(g[1] for g in grp)/len(grp)
    ls=[g[4] for g in grp if len(g)>4 and g[4] is not None]
    if ls and sum(ls)/len(ls)<L_MIN: return False
    return mw>=W_MIN and mn>=(N_MIN_PAGE if len(grp)==1 else N_MIN_DOC)
