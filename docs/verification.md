# Verification record - 9 October 2026

## Results

- Production Vite build: passed. React renders from the built dist directory.
- PostgreSQL workflow/security suite: 13 tests passed, 0 failed. Actual SQL migration/functions executed in PGlite's PostgreSQL engine.
- Headless Chrome: 10 workflow/layout check groups passed; no unhandled page errors.
- PDF manual: 18 A4 pages. All pages rendered for layout inspection; fine-rule page and final CHM instructions inspected at larger size. Logo, headings, tables, code blocks and footer are legible.
- CHM source: complete HHP/HHC/HHK, 16 topics, contents/printable HTML, local CSS and supplied RBMI logo. Internal local links and project file references validated. hhc.exe unavailable, so CHM compilation was not performed.
- Dependency installation audit reported no known vulnerabilities at installation time. This is not an ongoing security guarantee.

## Database tests

1. Schema/five institutions and membership denial.
2. Fixed-date holiday/weekend/grace/cap fine calculation.
3. Issue, duplicate issue rejection, renewal and return.
4. Hold priority and renewal block.
5. Overdue return, overpayment rejection, waiver and audit.
6. Full import rollback on a later duplicate barcode.
7. Receive acquisition once, generated copies and stock scan/close.
8. Auditor/assistant write denials and patron privacy.
9. Direct authenticated table-access denial and no self-role change.
10. Valid imports, ISBN reuse and cross-campus copy rejection.
11. Inactive/expired memberships, max loan count and zero renewal cap.
12. Own-hold cancellation and unassigned-institution denial.
13. Authenticated RPC works; anonymous RPC denied.

## Browser checks

Fresh demonstration opens with 24 copies in each campus; catalogue search; title creation; issue by barcode; renew/return; CSV preview and student import; all navigation modules; institution data switch; auditor/patron UI boundaries; 390px overview/catalogue without horizontal document overflow. Screenshots visually reviewed for desktop and mobile. Barcode values use Code128 through JsBarcode; actual printer/scanner calibration remains local acceptance work.

## Limits

Live Supabase project provisioning, hosted Auth sign-in, institution-owned backup restore, multi-connection concurrency/load, external scanning hardware and Windows CHM compilation were not tested here. The available hosted demonstration uses fictional browser-local data. RBMI must complete the manual's acceptance checklist before live use.

Vite emits advisory warnings for PGlite's optional Node filesystem adapter and internal eval use, and the mixed static/dynamic PapaParse import. The browser IndexedDB adapter is used in demo mode; both production build and browser checks passed. No CSP with unsafe-eval restrictions is imposed on the demo runtime. A live-mode hardened CSP should be validated separately for Supabase and barcode output.
