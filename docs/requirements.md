# Requirement traceability

The recovered referenced conversation returned five recent turns and no older cursor or Java files. The user's current enumerated requirements and the recovered feature list are authoritative. No inaccessible detailed Java policy rules are assumed. Default rules are explicitly configurable.

| Requirement | Implementation | Verification |
|---|---|---|
| React responsive UI | 11 modules, mobile navigation, desk actions, forms and search | Chrome browser workflow and 390px layout checks |
| RBCET/RBMI/RBCP/RBCN/RBTTI | institution seed, selector, per-institution memberships and RPC filters | PostgreSQL isolation tests + browser institution switch |
| RBAC | admin/librarian/assistant/accountant/auditor/patron; server-side checks | role denial, patron privacy, direct-table denial tests |
| Patrons | categories, code, department, active/expiry, membership editing | issue eligibility tests and bulk upload |
| Titles separate from copies | title entity with author/ISBN/etc.; copy entity with accession/barcode/shelf/status/price | schema, issue and catalogue UI checks |
| Barcodes/accessions | global unique barcode, campus-unique accession; Code128 printable labels | constraints/import rollback; barcode popup UI |
| Issue/return/renewal | copy/patron locks, loan cap, balance/overdue checks, renewal cap, policy snapshot | database and browser tests |
| Holds | per-title FIFO, unique waiting hold, cancellation and automatic fulfilment on issue | priority/renewal block/privacy tests |
| Holiday-aware fines | configurable rate, grace, cap, weekends, holidays, due-date shift | fixed-date calendar tests |
| Fine payment/waiver | ledger, receipt/reference/reason, balance constraints | overpayment/waiver/audit tests |
| Bulk books/students | templates, CSV preflight, preview/review, all-or-nothing SQL import | rollback test + browser student import |
| Acquisitions | vendors, order/invoice, full receipt and cancellation | once-only receipt and generated copies test |
| Stock verification | snapshot, scan, close, expected vs actual report/export | scan/close test |
| Reporting | catalogue/loans/overdue/fines/patrons/acquisitions CSV, popularity table, dashboard | browser module render and exports |
| Audit | successful writes and waiver reasons append to institution log | audit assertions |
| Free deployment | Cloudflare config, Supabase migrations and bootstrap guide; Sites demo | production build + hosted publication result |
| CHM manual | HHP/HHC/HHK and HTML/CSS, Windows build script, printable HTML | source/link validation; compiler unavailable locally |

Database tests use real PostgreSQL via PGlite, not mocked functions. Supabase Auth service integration, live backup restore, simultaneous multi-connection load, printers/scanners, and Windows CHM compilation need confirmation in the institution's environment before go-live.
