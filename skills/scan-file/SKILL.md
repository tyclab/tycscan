---
name: scan-file
description: File scanned paper batches from the scan staging directory into the document archive in three strictly separate phases — propose (bulk classification, fine on Sonnet), review (second model pass over the proposals), apply (split, coverage-dedupe, file, journal). Scanning itself is scan-batch.sh at the printer, no LLM in the loop. Use when batch-NNN.pdf files wait in ~/scan-staging.
argument-hint: "propose | review | apply [batch-nr ...]"
user-invocable: true
---

# scan-file

Environment: `ARCHIVE_ROOT` (archive directory), `SCAN_JOURNAL` (CSV journal, usually inside the archive), optional `SCAN_STOPWORDS` (recipient name, street, town — words that appear on every letter and must not link pages).

Paper mail keeps arriving; this is the standing path from the ADF to the archive. Phases never mix: propose only after every stack is scanned, apply only after review.

## Scanning (at the printer, no LLM)

`scan-batch.sh [staging-dir]` on any box that reaches the scanner (`ESCL_BASE=http://<scanner-ip>/eSCL`): load ≤35 sheets → Enter → put the output stack back into the feeder *unchanged* (no turning, no re-sorting) → Enter. It runs `escl-scan.sh` twice (any number of ≤35-sheet portions per pass, `f` ends the pass), `merge-duplex.sh` (interleaves A[i] with B[N+1−i]; blank backs are decided by `blank-pages.sh`, two-stage and keep-biased: Ghostscript `ink_cov` ≥ 0.2 % keeps, else a connected component ≥ 10 mm at native 300 dpi keeps — punch holes, print marks and show-through stay below; every dropped back is listed with its numbers and `batch-NNN-B.pdf` is retained for recovery), then hands off to `ocr-batch.sh`, which runs `ocr-remote.sh` in the background on `OCR_HOST` (default `local`; an ssh host name runs it remotely): orientation per page by an OCR-confidence vote at 0°/180° (undecided pages such as blanks and barcodes follow the majority of their pass; Tesseract OSD is unreliable on these scans and ocrmypdf `--rotate-pages` loses the text layer on pre-rotated pages), then OCR, then `check-order.py`, which flags neighbouring sheets that swapped in the output tray and checks every `Seite x von y` run for gaps, swaps and duplicates, then `check-continuation.py`, which compares the last text pages of the previous batches (up to three back, so a document interrupted by another stack is found too) with the first of this one (`Seite x/y → x+1/y` = FORTSETZUNG, shared file/insurance number = WAHRSCHEINLICH, word overlap = MOEGLICH) into `batch-NNN.cont.txt`, and `contact-sheet.sh`, which renders `batch-NNN.sheet.png` — every page as a thumbnail in reading order, rotated pages framed red; the loop moves on to the next stack at once and prints finished results and continuation hints before each prompt. Batches are not capped at 35 sheets (portions), so a long document fits in one batch when a new batch starts at a document boundary. Result: `batch-NNN.pdf`, `batch-NNN-merged.map.tsv` (page → sheet/side), `batch-NNN.check.txt`, `batch-NNN.sheet.png`. **The contact sheets are the quality gate**: before propose, every `.sheet.png` is opened and orientation and order confirmed by eye; a batch that looks wrong is rescanned or its OCR rerun, propose never argues with the sheet. Sticky or folded sheets jam the ADF — flatbed. A jam mid-portion keeps the pages delivered before it as a finished portion (the jammed sheet is never among them), so only the jammed sheet plus the rest go back into the feeder; `x` discards that portion if the jammed sheet turns out to have passed through. A jam or Ctrl-C leaves `batch-NNN-A.pdf`/`-B.pdf` in place; restarting the script offers to resume at the missing step (or to rerun a stuck OCR), and a page-count mismatch offers to rescan A or B or keep the fronts only.

## propose (bulk, no filing, no questions)

First two sweeps over the whole staging, both `nix shell nixpkgs#poppler-utils -c python3 "$(command -v <script>)" …`:

- `check-archived.py ~/scan-staging "$SCAN_JOURNAL" "$ARCHIVE_ROOT"` — pages whose words *and* numbers match a file the journal already lists (scan/fetch rows) land in `ARCHIVED.txt`; every such page range gets `SKIP` with reason `bereits abgelegt <Journal-Quelle>: <Datei>` and the batch is listed under "Bereits abgelegt" in `PROPOSE.md`. Same template with other numbers (next year's invoice) is not a hit.
- `check-dups.py ~/scan-staging` — sheets scanned twice within the staging land in `DUPS.txt` (same key numbers, not just the same template); the second copy gets `SKIP` (reason "Dublette von batch-NNN S.x"), the first is filed. Identical boilerplate sheets (terms pages behind different invoices) are listed too — keep them with their document.

For every `~/scan-staging/batch-NNN.pdf` without a `.spec.tsv`:

1. Read `batch-NNN.check.txt`; on `VERDAECHTIG` skip the batch, on a `Seitenfolge` finding treat the affected page range as uncertainty 2 and say what is missing or swapped; and list it under "Nachscannen" in `~/scan-staging/PROPOSE.md`. Read `batch-NNN.cont.txt` if present: on FORTSETZUNG or WAHRSCHEINLICH (also lines marked `Luecke`, where the earlier batch is not the direct predecessor), check whether the first document of this batch continues the last document of the named batch (same `Seite x von y` run, same file number, no new letterhead); if it does, give both parts the same target filename plus a `(Teil 1)` / `(Teil 2)` suffix and list the pair under "Fortsetzungen" in `PROPOSE.md` — apply files them as two PDFs next to each other, joining is a manual `qpdf` step after apply.
2. `nix shell nixpkgs#poppler-utils -c pdftotext -layout` page by page. Document boundaries from sender changes, `Seite x von y`, contract/insurance/tax numbers; the front/back mapping is in the `.map.tsv`.
3. Target from the archive taxonomy under `$ARCHIVE_ROOT` as documented in the archive's own `CLAUDE.md` (example: `Identität Finanzen Steuern/<Jahr> Versicherungen/<Sparte> Wohnen/<Objekt> Gesundheit Fahrzeuge Arbeit Anschaffungen/<Jahr> Familie & Freunde/<Name> IT <Betrieb>/{Stammdaten,Eingangsrechnungen/<Jahr>,Korrespondenz/<Jahr>}`). Keep private and business papers in separate trees; other people's papers go to their own folder. Follow the target folder's naming, else `YYYY-MM-DD Absender Typ.pdf`; the date comes from the document, never the scan date. Advertising, blank forms, statements already held digitally → `SKIP`; when the archive copy is a photo or image-only PDF of the same paper, say so in the reason (`bereits vorhanden: <file> (Foto)`) so the review can turn the row into REPLACE.
4. Write `batch-NNN.spec.tsv` (`<pages>\t<relative target | SKIP>\t<one-line reason>`) and a block in `PROPOSE.md` (pages | document | target | uncertainty 0–2).

## review (second model pass)

Read `PROPOSE.md` and every `.spec.tsv`. Check boundaries (page ranges gapless, `Seite x von y` consistent), targets against the taxonomy and the neighbouring files in the target folder (`ls`), document-derived dates, every uncertainty-2 entry individually. Fix the `.spec.tsv` in place, log changes in `REVIEW.md`, put only open points to the user as a short list, wait for the go.

## apply (after the go)

Per batch:

```bash
nix shell nixpkgs#qpdf nixpkgs#poppler-utils -c python3 "$(command -v file-docs.py)" \
  ~/scan-staging/batch-NNN.pdf ~/scan-staging/batch-NNN.spec.tsv "$ARCHIVE_ROOT" \
  "$SCAN_JOURNAL" Papier/<scan-date>-NNN
```

`file-docs.py` splits with qpdf, skips `SKIP` rows, checks each document against the PDFs in its target folder with the same word-plus-number coverage as `check-archived.py` (a second scan of already filed paper is `DUP` and not filed; the same template with other numbers is filed), copies, and appends `scan,<batch> S.x,<path>` to the journal. A row `<pages>\tREPLACE <old archive file> => <new target>` replaces an archive copy that is worse than the scan (photo, image-only PDF, incomplete): no duplicate check, the old file moves to `_Papierkorb/ersetzt/<same relative path>`, the scan is filed under the new target (or the old path when the `=> <new target>` part is omitted), and the journal gets a `move` row plus `scan-replace,<batch> S.x,<path>`. REPLACE is refused when the old file is missing or the new target exists. Only the review decides on REPLACE rows, never propose. Report the result lines per batch.

Rules: never quote plaintext credentials from the archive. Dead paths in `_Archiv` and dated reports stay as they are. `_Papierkorb` stays.
