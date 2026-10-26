# Scanner validation and protocol traps

Read for this topic; paths below are relative to the repository root unless stated otherwise.

The reference Canon GX4000 advertises only AdfSimplexInputCaps. It accepts a
Duplex=true request but returns simplex; panel ADF duplex is a guided second pass.
Preserve the two-pass workflow instead of assuming HTTP success proves duplex.

A jam can return HTTP 200 with a truncated PDF and ScannerAdfJam or
JobCanceledAtDevice in the job status. escl-scan.sh must inspect that status.
Sticky sheets go on the flatbed. Test scanner-facing changes against a real
scanner; mock HTTP success alone does not establish hardware behavior.

Blank-page/duplicate thresholds were tuned on one scanner/archive. Re-evaluate
them with representative documents without publishing personal archive contents.
