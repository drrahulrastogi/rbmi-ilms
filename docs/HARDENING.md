# Security and scaling update - 24 October 2026

## What changes for staff

- New student, faculty and staff accounts receive Supabase invitation emails and choose their own password. CSV templates omit passwords; a legacy password column is ignored. Existing passwords are retained. SMTP delivery and its quotas must be configured in Supabase. Import results distinguish a saved membership from a successful invitation request; failed invitations can be retried. A pending invitation can be resent by the librarian; the administrator can send account recovery from Settings.
- The administrator can enroll an authenticator in Settings. After entering a valid TOTP code and enabling protection, database and account endpoints require an `aal2` session. Enrollment/activation is an owner action; this release does not silently create a factor or lock the owner out before verification. Preserve the authenticator and a protected Supabase project-owner recovery path. MFA recovery must verify the owner and be audited; do not remove database protection just to bypass a lost device.
- Patron, active-loan, returned-loan, audit and membership tables query pages of 50 records; search covers the complete selected dataset. Overview totals remain server aggregates. Stock verification uses per-session pages and complete aggregates/exports. Other growing workflow modules offer Load next controls with explicit loaded/total counts; their local search covers loaded rows.
- Public catalogue titles and copy details have separate cursors. Title cards show exact total/available counts with a small preview. The legacy catalogue endpoint is also bounded.
- Reports load their complete sources on demand through bounded pages. CSV and PDF exports include all matching rows; an export exceeding 50,000 records per dataset fails explicitly and needs a narrower saved date range. Preparation and PDF generation can be cancelled.
- Large audit details are summarized in list/CSV results. The complete original remains in the database and can be read through detail pages of 16,000 characters. No audit record is deleted by this change.

## Shared limits and monitoring

Quotas are atomic database counters, not per-process memory: password operations 10/user/minute; account management 30/user/minute; patron provisioning 240/user/minute; account pre-authentication 120/IP/minute. IP subjects are salted hashes, never raw stored addresses. Vercel's trusted forwarded IP is used only on Vercel; local execution uses the peer address. Account endpoints fail closed if quota/security checks are unavailable and return HTTP 429 plus Retry-After when limited.

Catalogue reads have a shared anonymous budget of 600/minute; signed-in paged reads use a 2,000/user/minute budget. This is an intentional resource ceiling, not a claim to serve 5,000 anonymous visitors in one minute. The limit may need tuning for a larger deployment after staged measurement. Direct browser data/role access remains revoked; privileged functions check library membership and password/MFA state.

Vercel adds a Content-Security-Policy, anti-framing, MIME and Permissions-Policy headers. Inline scripts/eval are blocked; WebAssembly compilation is allowed for the isolated sample database. Static inline styles are retained for existing UI/print support. Account logs contain only operation, request ID, status and duration, without request bodies, email, passwords, tokens or raw IP. `/api/health` returns only a minimal status and checks schema/database availability. The GitHub workflow checks the health endpoint and public page every 15 minutes; GitHub's failure notification settings determine alert delivery. Scheduled-job timing and provider outages remain outside the application.

## Concurrency and restore evidence

An isolated PostgreSQL 17.10 cluster over loopback TCP tested 5,000 distinct database identities with 64 concurrent workflows and a 32-connection pool. The final read phase completed with zero errors, p95 359.56 ms and about 295.9 workflows/second. This is a database test with an Auth stub, not 5,000 authenticated browser sessions or a hosted Vercel/Supabase capacity guarantee.

Mixed concurrent hold/issue requests exposed real deadlocks. Title locking alone did not fix the foreign-key cycle: the institutional FOR UPDATE lock also conflicted with inserts' KEY SHARE locks. Holds now lock the title before the patron; institutional operations use NO KEY UPDATE because they do not change the institution key. The same 200-request contention test then completed in 1.12 seconds with zero deadlocks, one open loan and expected duplicate/unavailable rejections. Successful hold/issue requests preserve FIFO/uniqueness rules; they are not all expected to succeed against one copy.

A synthetic restore rebuilt a fresh database from migrations, restored all 35 application/Auth-stub tables, matched per-table content hashes, restored sequences and verified a post-restore write. This does not cover live Supabase Auth secrets, Storage, PITR or a production disaster-recovery exercise. Keep a supported protected production backup and test hosted recovery separately.

## Reproduce

`npm ci && npm test && npm run build` runs the regular suite and build. `npm run test:postgres` requires a dedicated disposable PostgreSQL cluster on loopback port 55439 with superuser `qa_owner` (override `QA_PG_PORT` / `QA_PG_USER`). It refuses the standard port 5432, creates fresh uniquely named `rbmi_qa_*` databases and uses synthetic data only. It never connects to the hosted project. Set `QA_OUTPUT_DIR` to select an output folder. PostgreSQL server binaries are not bundled in the source archive; the original Windows test used the npm package `@embedded-postgres/windows-x64@17.10.0-beta.17` in a separate tooling folder.

`scripts/load-staging.k6.js` remains available for an isolated hosted staging project. Production targets are blocked. Hosted Auth/login storms, mobile-device throughput and internet/Gateway limits require separate staging measurement. No paid project or provider upgrade was created for these checks.
