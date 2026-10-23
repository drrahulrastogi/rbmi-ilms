# RBMI Integrated Library Management System 2.0

React 19 / Vite, Supabase PostgreSQL and Auth, and Vercel server functions. Live application: https://rbmi-ilms.vercel.app . Source: https://github.com/drrahulrastogi/rbmi-ilms .

Four physical libraries: RBCET (shared RBCET/RBMI Central Library), RBCP, RBCN and RBGN. One administrator, rahul.r@rbmi.in, manages the network. Distinct designated librarians operate each library. Passwords and private data are never committed.

## Features
Bibliographic records separate from accession/barcoded copies; patron profiles; issue/return/renewal/holds; saved circulation policies; holiday/weekend and dated librarian-unavailability fine exclusions; payments/waivers; issue library/operator snapshots and enforced same-library return; CSV and UTF-8 MARC imports; acquisitions/budgets/funds/baskets; authorities; public/private reading lists; serial predictions/receiving; advanced/item search; anonymous OPAC; stock verification; safe saved reports/CSV; audit; staff account management and email recovery for every role.

## Run locally
Install Node.js >=20.16, then run npm ci and npm run dev. Without both Supabase variables the app starts a fictional browser-local PostgreSQL demonstration. It downloads a substantial runtime on first load. It is not live Auth; do not enter private operational records there.

Run npm test and npm run build for validation. npm run preview serves a production build. scripts/start-windows.cmd helps on Windows.

## Deploy a complete installation
1. Follow database/README.md. In a NEW Supabase project, run database/install-new-supabase.sql once, create the administrator Auth user and apply scripts/bootstrap-admin.sql with its UUID.
2. Disable public signup, retain email/password login, set Auth Site URL to the HTTPS deployment, allow /?recovery=1, configure SMTP, and require strong 12-character passwords.
3. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to the public URL/key. Set SUPABASE_SERVICE_ROLE_KEY as a sensitive server-only Production variable in Vercel, never with a VITE_ prefix.
4. Deploy this repository root as Vite with vercel.json. It runs npm test and npm run build and publishes the UI plus api/password.js and api/accounts.js. Static-only GitHub Pages cannot provide these server endpoints.
5. Confirm intended Vercel scope/project before deploying. Current production uses the linked Vercel CLI project rbmi-ilms, scope engg1. CLI release is used; GitHub automatic deployment is not assumed.
6. Verify sign-in, isolation, recovery, issue/return/fines and backups before opening a new installation for staff.

## Manuals and Windows CHM
Open docs/help/index.html, docs/help/user-guide.pdf or printable.html. The 24-section manual describes actual workflows and limitations. The live site serves it at /manual/ .

Run scripts/build-chm.ps1 after installing Microsoft HTML Help Workshop, or pass -Compiler with the full hhc.exe path. Complete .hhp/.hhc/.hhk/HTML/assets are included. A compiled CHM is supplied only when an installed compiler can produce and verify it.

## Data, security and scope
Real RBCET students and Central Library holdings are imported privately into the hosted database. This repository and source ZIP contain schema, policy seed and fictional demo records only. Protected import archives preserve source fields and provenance. Anonymous OPAC excludes students, accounts, fines and prices. All private tables deny direct API-role access; RPCs enforce membership.

The Koha documentation informed targeted modules; this is not full Koha compatibility. See docs/koha-coverage.md and the manual. Holdings load through library-scoped keyset pages; indexed lookups and bounded rendering handle the current collection. The browser keeps the loaded collection, and very large audit histories may need additional pagination. Partial acquisitions receipts, offline circulation, RFID/SIP2, EDI, full MARC editing, automated claims/hold emails and public tags/reviews are outside this release. Restore drills and provider quota monitoring remain operational responsibilities.
