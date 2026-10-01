# tycscan

Paper-to-archive pipeline for a single-sided ADF scanner: duplex scanning over eSCL, blank-back
removal, orientation vote, OCR, order and continuation checks, duplicate detection against an
existing archive, and journaled filing. Built for a German household archive (letters, invoices,
insurance, tax), language-agnostic where it matters.

No scanner driver, no SANE: the scanner is driven over plain eSCL/AirScan HTTP, so any
AirPrint-capable multifunction device works. OCR is Tesseract via ocrmypdf.

## Pipeline

```
scan-batch.sh            interactive loop at the device: scan fronts (A), reload the output
                         stack unchanged, scan backs (B), merge, OCR in the background
  escl-scan.sh           one ADF pass → PDF (jam-aware, resumable)
  merge-duplex.sh        interleave A[i] with B[N+1-i]; drop blank backs
    blank-pages.sh       two-stage blank detection (Ghostscript ink coverage, then
                         connected-component size at 300 dpi), keep-biased
  ocr-batch.sh           run ocr-remote.sh locally or on OCR_HOST over ssh, then the checks
    ocr-remote.sh        per-page 0°/180° vote by OCR word confidence, then ocrmypdf
    check-order.py       swapped neighbours in the back pass; "Seite x von y" gaps/dups
    check-continuation.py  does batch N continue the document that ended batch N-1..N-3?
    contact-sheet.sh     thumbnail sheet of the batch, rotated pages framed red
check-dups.py            same sheet scanned twice within the staging directory
check-archived.py        pages already filed, matched by word AND number coverage
file-docs.py             split by spec, duplicate-check against the target folder, copy, journal
scanlib.py               shared text heuristics (IDs, page markers, coverage thresholds)
```

Output per batch: `batch-NNN.pdf` (OCRed, oriented), `batch-NNN-merged.map.tsv` (page → sheet/side),
`batch-NNN.check.txt`, `batch-NNN.cont.txt`, `batch-NNN.sheet.png`.

## Requirements

- Nix with flakes: every script fetches its tools with `nix shell nixpkgs#…` (poppler-utils, qpdf,
  ghostscript, imagemagick, tesseract, ocrmypdf, dejavu_fonts). Nothing else to install.
- bash ≥ 4, python3, curl, ssh/scp (only for a remote OCR host).
- An eSCL scanner with an ADF.

## Configuration (environment)

| Variable | Default | Meaning |
|---|---|---|
| `ESCL_BASE` | required | Scanner endpoint, e.g. `http://192.0.2.10/eSCL` |
| `OCR_HOST` | `local` | `local`, or an ssh host that has Nix; OCR runs there |
| `OCR_LANG` | `deu+eng` | Tesseract languages; the first one drives the orientation vote |
| `SCAN_STOPWORDS` | empty | Lowercase words that appear on every letter (recipient name, street, town) and must not link pages |
| `ARCHIVE_ROOT` | – | Archive directory, passed to `check-archived.py` / `file-docs.py` |
| `SCAN_JOURNAL` | – | CSV journal (`scan,<batch> S.x,<relative path>` rows) |

Staging directory defaults to `~/scan-staging`.

## Usage

```bash
export ESCL_BASE=http://<scanner-ip>/eSCL
bin/scan-batch.sh                     # follow the prompts; q quits, a restart resumes
```

Then, per batch, decide where each page range goes and write `batch-NNN.spec.tsv`
(`<pages>\t<relative target | SKIP | REPLACE <old> => <new>>\t<reason>`), and file:

```bash
nix shell nixpkgs#poppler-utils -c python3 bin/check-dups.py ~/scan-staging
nix shell nixpkgs#poppler-utils -c python3 bin/check-archived.py ~/scan-staging "$SCAN_JOURNAL" "$ARCHIVE_ROOT"
nix shell nixpkgs#qpdf nixpkgs#poppler-utils -c python3 bin/file-docs.py \
  ~/scan-staging/batch-001.pdf ~/scan-staging/batch-001.spec.tsv "$ARCHIVE_ROOT" "$SCAN_JOURNAL" Papier/2026-09-07-001
```

`skills/scan-file/SKILL.md` is a Claude Code skill that drives the classification step in three
separate phases (propose, review, apply). Copy it into a plugin or `.claude/skills/` to use it.

## Notes

- Prompts and comments are German; the heuristics look for German page markers first
  (`Seite x von y`) but also accept `Page x of y`.
- Journal paths are written with backslashes because the reference archive lives on a Windows
  share. Adjust `file-docs.py` if yours does not.
- The blank-page thresholds (0.2 % ink, 10 mm component) and the duplicate thresholds in
  `scanlib.py` were tuned on one scanner and one archive. Expect to re-tune.

## License

MIT
