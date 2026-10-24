# Testing and security review - 24 October 2026

## Automated checks

`npm ci` followed by `npm test` runs 75 executable tests: 13 pure unit/report tests, 50 database integration/security tests and 12 account API integration/fault-injection tests. The API tests invoke real handlers and the Supabase SDK with a controlled HTTP transport; they do not claim to test hosted Auth. Database tests apply application migrations to disposable PostgreSQL-compatible PGlite with an Auth stub. They cover role boundaries, library isolation, atomic imports, holds, circulation, fines, calendars, acquisitions, source privacy, onboarding, report exports and malformed inputs.

For Windows environments that prohibit child-process spawning, invoke each test file separately with Node 24: `node --test --test-isolation=none tests/api-security.test.mjs` (repeat for each `tests/*.test.mjs`). The normal CI command uses process isolation. Tests never need real administrator passwords.

## Test-driven fixes

The new null-bootstrap regression tests were written and run first: eight API cases passed and two failed. Account listing threw a TypeError on a null authorization response; password change returned 503 rather than denying access. Array validation now denies both cases with 403 before privileged writes. Both regressions then passed. This is a red/green cycle for these fixes; it does not retrospectively make the existing application a TDD project. No data disclosure or authentication bypass was demonstrated by these two failures.

## Local load laboratory

Run `npm run test:load`. Optional variables: `QA_OUTPUT_DIR` selects the result folder; `QA_CLIENT_CONCURRENCY=50` bounds simultaneous requests. The script binds only to loopback, applies real migrations to a disposable database and creates synthetic data (26,071 copies, 9,668 titles and 5,000 additional patron profiles). It submits phases of 100, 500, 1,000 and 5,000 logical request workflows, mixing public catalogue queries and authenticated collection-page SQL. It checks HTTP status/response shape and reports p50/p95/p99, throughput, errors and a two-second latency target.

This is a one-connection PGlite system and a local HTTP adapter, not the deployed API. Virtual users here are request workflows, not independent authenticated browser sessions. It excludes hosted Auth, PostgREST, Vercel functions, real connection pools, internet latency and browser rendering. The duplicate-issue test submits 200 requests and checks exactly one open loan, but its serialized connection cannot validate real transaction races, deadlocks or row-lock throughput.

`node scripts/load-transport-control.mjs` repeats HTTP requests without the application/database to distinguish transport saturation. `node scripts/security-scale-probe.mjs` measures bounded/unbounded RPC payloads. All results use synthetic data only.

## Isolated staging load test (provided, not executed)

Install k6 separately. Populate an isolated staging Supabase project with synthetic records; never use production patron data or credentials. Set `STAGING_SUPABASE_URL`, `STAGING_ANON_KEY` and `CONFIRM_STAGING_TARGET` to that exact staging URL, then run `k6 run --summary-export staging-results.json scripts/load-staging.k6.js`. The script explicitly blocks the production project. It ramps 100/500/1,000/5,000 public virtual users with five-second think time and checks error rate below 1% and p95 below two seconds. This can consume substantial staging resources; configure quotas before running. It does not cover staff writes or login storms: those need separate synthetic test identities and a real multi-connection PostgreSQL test plan.

## Remaining improvement priorities

1. Replace the requested predictable `INSTITUTE@CODE` initial passwords with random, short-lived invitations. Mandatory first change helps, but a guessed initial password can still be used before its intended owner signs in. Completed password CSVs must remain private.
2. Add shared per-user/per-IP quotas for privileged account endpoints and expensive anonymous RPCs. Application code has request-size/row limits but no distributed rate limiter; provider limits do not establish a business-level quota.
3. Retire or cap the legacy anonymous `library_catalogue` RPC. The current UI uses bounded search, but the old RPC remains callable and returns the entire collection. Also paginate the copies returned by bounded title search: its title limit does not bound the number of copies for those titles. This is a resource-amplification concern, not evidence of private patron disclosure.
4. Paginate staff patrons, loans and audit history; avoid full snapshots and large all-row report responses as data grows. Continue generating PDFs off the main thread; prefer filtered or queued exports for large reports.
5. Run staging load tests with real PostgreSQL connections to measure contention: issue/return operations currently lock an institution row. Local serialized tests cannot establish production concurrency limits.
6. Add a tested Content-Security-Policy, administrator MFA, central monitoring/alerts and a verified backup/restore drill. These were not configured or certified by this test pass.

## Measured local results

With 50 client requests in flight, 5,000 workflows completed in 136.92 seconds with zero failures (36.52 requests/second, p50 1,201.29 ms, p95 2,316.82 ms, p99 3,198.72 ms). Of these, 595 exceeded two seconds. The functional checks passed; the p95 target did not. Earlier phases at 100/500/1,000 workflows had zero failures; local p95 varied from 469.11 ms to 3,509.51 ms. Other QA processes shared this Windows host, so these are observations, not a reproducible service benchmark.

The 1,000-in-flight burst run failed 4,135 of 5,000 requests. A no-application transport control independently failed 914/5,000 at 500 connections and 991/5,000 at 1,000, with ECONNREFUSED. These runs establish a local transport/harness limit and cannot be attributed to hosted application capacity. The 200 duplicate-issue submissions produced one accepted issue, 199 rejected attempts and one open loan in both database runs.

The synthetic scale probe returned 4,491,234 bytes from the legacy public catalogue (9,668 titles / 26,071 copies). Searching up to 40 titles returned 2,937,139 bytes in an intentionally skewed fixture with 26,023 copies attached to one matching title. Staff workspace returned 1,060,667 bytes for 5,016 patron profiles, without collection payloads. This demonstrates why both child-copy results and growing staff histories need pagination.

## Current guidance consulted

- [Supabase API security: grants, RLS and request checks](https://supabase.com/docs/guides/api/securing-your-api)
- [Supabase performance and connection pooling](https://supabase.com/docs/guides/platform/performance)
- [Supabase changelog](https://supabase.com/changelog)

The current changelog was checked for relevant breaking changes. No database schema or Auth configuration was changed by this review. A dependency audit reported zero known vulnerabilities; this is not a guarantee against undiscovered vulnerabilities. Real production load capacity remains unverified.
