# Verification - RBMI ILMS 2.0

23 October 2026: 34 executable database/MARC tests passed, including legacy regressions, institution isolation, source-profile preservation, private source archives, FIFO holds, renewal checks, unavailability fine exclusions, immutable issue identity, same-library return, budgets/funds, serial dates, reading-list ownership, saved-report restrictions and anonymous OPAC privacy.

The complete new-project installer was executed in fresh PostgreSQL/PGlite: four active libraries, all application tables protected by RLS, repeat installation refused. Production Vite build succeeded. Existing PGlite demo bundler warnings concern its optional browser demo runtime.

Hosted database: all three designated librarian sign-ins passed. Each sees only its assigned library; cross-library snapshots were rejected. RBCET contains 26,071 copies, 9,668 bibliographic records and 278 imported student profiles plus one retained fictional patron linked to a sample Auth account. All 26,349 imported source rows reconciled. RBCP and RBCN have no imported holdings or patrons.

A hosted transactional acceptance probe tested admin access to all four libraries, issue provenance, rejection of another library's return, and zero fine on an unavailable current day. The transaction was rolled back; no test books, patrons, loans or calendar changes remained.

Security advisors identified the intentional RPC security-definer architecture (authenticated business endpoints and an anonymous explicitly projected OPAC). All private table/function access is revoked. The mutable search path on app.today was corrected. Provider leaked-password protection is not enabled on the existing free project; no paid upgrade was selected. These are reviewed limits, not a claim of zero advisor findings.

The 26-page manual was rendered and visually inspected. HTML/CHM source links resolve locally. HTML Help Workshop is not installed; complete CHM sources and the Windows compiler script are supplied instead of claiming a compiled CHM. A full disaster-recovery restore drill has not been performed.

Hosted browser verification found an initial large-snapshot timeout. Migration 20261023093537 replaces repeated JSON concatenation with one assembled object. The administrator dashboard then loaded all 26,071 copies, all three library choices and Nidhi's assignment. Catalogue cards and original workbook source details rendered correctly. Accounts listed the nine existing Auth identities for the administrator. The hosted API rejected anonymous/non-admin account listing, and a disposable account passed one-use recovery, rejection of replay, password change and subsequent sign-in; it was removed.

Final scaling change: secure keyset pages load staff holdings in bounded responses, and OPAC uses server-filtered result pages. Auth refresh no longer reloads the workspace for the same user; an authenticated OPAC visit does not load private staff holdings. Both pagination/isolation tests passed (34 tests total).

RBGN extension: a fourth independent library and fifth-category policy set are added by migration 20261023143719. The network administrator receives RBGN membership. A dedicated local acceptance test verifies RBGN-only librarian access, its own availability calendar, issue provenance and rejection of returns at RBCET (35 tests total). Live librarian identity: raveena@rbmi.in. Administrator recovery was completed by the owner without sharing the new password.

## Holiday and faculty update — 23 October 2026
43 tests pass. Bulk holiday upload validates ISO dates, names, duplicates and row limits atomically; admin-only upload and additional holidays exclude fine days per library. Faculty bulk/individual entry records institute within the assigned library, preserves profiles and uses faculty rules; accidental student-code overwrite and cross-library access are rejected. CSV templates and previews are provided.
