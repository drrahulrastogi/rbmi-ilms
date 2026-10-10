# Architecture

React 19 + Vite 6 provides a responsive single-page application. Supabase Auth establishes identity. PostgreSQL is the authoritative backend. `app` is a private schema, excluded from PostgREST's exposed schemas. All app tables have RLS enabled with no direct client policies; anon/authenticated roles lack schema/table privileges. Only three security-definer public functions are callable by authenticated users. Each function uses an empty search path and checks the caller's membership using `auth.uid()`. Never store authority in editable Auth user metadata.

## Data model

Institutions (five codes) -> memberships, patrons, titles, policies, holidays, vendors and inventory sessions. A title -> many physical copies. Copies -> loan history with a unique partial index allowing one open loan per copy. A loan stores the issue-time policy JSON. Holds are per title/patron, unique while waiting, with FIFO ordering by timestamp and UUID. A returned overdue loan creates one fine. Payments and waivers append ledger entries; fines retain running paid/waived amounts with a constraint that they cannot exceed the assessed amount. Acquisitions refer to vendors and titles and generate copies once upon receipt. Stock items capture expected copy status at session start. Audit is append-only to application users.

Loans and book copies are separate from financial records. No irreversible deletions are exposed. Copy status changes require a reason, cannot change a loaned copy, and are audited. Marking lost does not automatically charge replacement cost: issue the appropriate institutional accounting instruction outside this ledger. Dates use Asia/Kolkata; timestamps are timezone-aware. Stock close is reconciliation reporting, never automatic loss marking.

## API

`library_bootstrap()` returns `{memberships:[{institution_id,name,role,patron_id}]}` for the current user. `library_snapshot(i)` returns arrays keyed by entity table name. Staff receive one institution's data. Patrons receive catalogue/copies, their own profile/loans/holds/fines, policies and holidays; no staff audit, stock, acquisition or membership data.

`library_action(i,action,p)` performs exactly one transaction (nested import calls stay in the enclosing transaction). Allowed actions:

| Group | Actions | Roles |
|---|---|---|
| Catalogue/patrons | title, copy, copy_status, patron, import | admin, librarian |
| Desk | issue, return | admin, librarian, assistant |
| Renewal/holds | renew, hold, cancel_hold | desk roles; patron only own records |
| Finance | pay, waive | admin, librarian, accountant |
| Acquisition | vendor, order, receive, cancel_order | admin, librarian |
| Inventory | stock_start, stock_scan, stock_close | admin, librarian |
| Administration | policy, holiday, member | admin |
| Read-only | bootstrap, snapshot | assigned roles, including auditor |

Authentication failures, constraint failures and policy violations return PostgREST errors. The UI displays them, preserving form data. Database transactions abort without partial records. Do not retry an unknown-result issue/payment automatically: refresh first and inspect loans/audit/ledger. Stock scanner retries are idempotent; payment submissions are not assigned client idempotency keys.

## Concurrency

Issue locks the title, then copy and patron rows. Renew/return lock the title and loan/patron. This serializes copy/hold decisions and loan counts. Hold placement locks patron/title. PostgreSQL may abort one request if opposing lock orders produce a deadlock; refresh and retry the rejected request. The open-loan index, barcode/accession uniqueness and fine constraints protect integrity independently of UI state. Stock sessions are locked on scan/close. Receipt locks the acquisition so a second receipt fails. True multi-connection stress tests against hosted PostgreSQL remain a pre-production check; PGlite tests use one local engine.

## Demonstration

When both environment values are empty, the browser dynamically loads PGlite (PostgreSQL compiled to WebAssembly), creates mock Auth identity/roles, executes the same migration and institutional seed, and inserts fictional patrons/books. IndexedDB `rbmi-library-v1` stores this data per origin/browser. Role switching uses six mock UUIDs. This is not authentication and is clearly labelled throughout the UI. It never connects to a live institution. Delete this site's IndexedDB to reset the demo. In live mode the PGlite chunk is not requested. Demo data/bootstrap scripts are shipped openly and contain no credentials.

## Scale and scope

Snapshots currently load all accessible institution rows, with table rendering in batches of 30. Test resource usage before large imports or extensive audit history; cursor-based server pagination is the next scaling step. Imports are bounded to 1,000 rows; audit currently records row details and the batch. Audit has no retention purge UI. Catalogue is institution-scoped, not a shared cross-campus title union. Authentication is password login; password resets/invitations occur through Supabase administration. Notifications, MARC/Z39.50, RFID, online payments, automated reminders, inter-library transfers and partial purchase receipts are not included. Full purchase receipt creates the ordered quantity in one transaction.

