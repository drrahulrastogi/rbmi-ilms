# Verification - RBMI ILMS 2.0

23 October 2026: 32 executable database/MARC tests passed, including legacy regressions, institution isolation, source-profile preservation, private source archives, FIFO holds, renewal checks, unavailability fine exclusions, immutable issue identity, same-library return, budgets/funds, serial dates, reading-list ownership, saved-report restrictions and anonymous OPAC privacy.

The complete new-project installer was executed in fresh PostgreSQL/PGlite: three active libraries, all application tables protected by RLS, repeat installation refused. Production Vite build succeeded. Existing PGlite demo bundler warnings concern its optional browser demo runtime.

Hosted database: all three designated librarian sign-ins passed. Each sees only its assigned library; cross-library snapshots were rejected. RBCET contains 26,071 copies, 9,668 bibliographic records and 278 imported student profiles plus one retained fictional patron linked to a sample Auth account. All 26,349 imported source rows reconciled. RBCP and RBCN have no imported holdings or patrons.

A hosted transactional acceptance probe tested admin access to all three libraries, issue provenance, rejection of another library's return, and zero fine on an unavailable current day. The transaction was rolled back; no test books, patrons, loans or calendar changes remained.

Security advisors identified the intentional RPC security-definer architecture (authenticated business endpoints and an anonymous explicitly projected OPAC). All private table/function access is revoked. The mutable search path on app.today was corrected. Provider leaked-password protection is not enabled on the existing free project; no paid upgrade was selected. These are reviewed limits, not a claim of zero advisor findings.

The 26-page manual was rendered and visually inspected. HTML/CHM source links resolve locally. HTML Help Workshop is not installed; complete CHM sources and the Windows compiler script are supplied instead of claiming a compiled CHM. A full disaster-recovery restore drill has not been performed.

Hosted browser verification found an initial large-snapshot timeout. Migration 20261023093537 replaces repeated JSON concatenation with one assembled object. The administrator dashboard then loaded all 26,071 copies, all three library choices and Nidhi's assignment. Catalogue cards and original workbook source details rendered correctly. Accounts listed the nine existing Auth identities for the administrator. The hosted API rejected anonymous/non-admin account listing, and a disposable account passed one-use recovery, rejection of replay, password change and subsequent sign-in; it was removed.
