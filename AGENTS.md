# AGENTS.md — tycscan

Generic scanner and document-filing tools. README owns installation and the
propose/review/apply workflow; skills/scan-file owns its user-facing procedure.

- Keep this public copy generic: use configured scanner/OCR/archive values,
  never personal paths, addresses, account names, document contents or credentials.
- Preserve the separation between proposing, reviewing and applying document
  filing. Follow the scan skill's operator decisions; never infer an answer.
- Read [scanner traps](docs/agents/scanner-traps.md) before eSCL, duplex,
  jam-handling, thresholds or capture validation work. Check job status as well
  as HTTP status, and validate scanner-facing changes on hardware.
- Preserve existing file handling and archive behavior. Test using disposable
  fixtures; never delete or reorganize an operator's archive as a test.
- Respect repository merge defaults and checks; use a public-safe commit identity.

Keep repository-wide instructions here; put task-specific guidance in `docs/agents/`
and link it from this file. README owns human setup and architecture; plans hold open work only.
