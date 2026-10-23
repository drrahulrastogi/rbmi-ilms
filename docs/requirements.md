# RBMI ILMS 2.0 - requirements

Updated 23 October 2026. The authoritative operator guide is docs/help/index.html.

## Start here and library directory

Open https://rbmi-ilms.vercel.app in a current browser. RBMI ILMS 2.0 uses React, shared Supabase PostgreSQL and Supabase email/password authentication. GitHub and hosting dashboard accounts are separate from library sign-in accounts.

1. Sign in with your registered email and private password. Verify that the connection indicator says Supabase connected.
2. Select RBCET for the shared RBCET / RBMI Central Library, RBCP for Pharmacy, or RBCN for Nursing. RBMI is a campus in the shared library, not a fourth issue desk.
3. The single network administrator is rahul.r@rbmi.in and manages all four libraries. Nidhi Dewal, nidhi@rbmi.in, serves RBCET/RBMI. Rekha, rekha@rbmi.in, serves RBCP. Sheeba, sheeba@rbmi.in, serves RBCN.
4. Use the sidebar modules. On a phone open the navigation menu. Refresh data to see a colleague's recent changes. Sign out before leaving a shared computer.

A yellow Sample data banner means an isolated browser demonstration with fictional records. Live staff must use the Supabase-connected deployment.

Passwords are supplied privately to the owner. A patron card number is not a sign-in password; student import does not create authentication accounts.

## Librarian availability and fine-free days

An unavailable date is a full-day exception for one library. The database records the date, reason, operator and change time. Partial-day closures are not modeled.

1. In Overview or Settings > Librarian availability, verify the selected library and librarian name.
2. Select the date, set availability off, enter a reason such as Librarian on approved leave, and save.
3. Confirm the history entry and the No fine badge for a closed current day. Correct an erroneous closure by restoring availability with a reason.
4. The designated librarian can edit today or a future date up to one year ahead. Only admin can correct historical dates.
5. Fine calculation skips unavailable dates only for this library. A due date that falls on a closed day moves to the next eligible open date.
6. Example: at INR 2 per eligible overdue day, three weekdays with one recorded unavailable day produce INR 4 before grace and cap. A date that is both a holiday and unavailable is excluded once.

An unmarked date follows the normal calendar. The system does not infer absence from failed logins or a librarian not signing in.

Historical calendar corrections do not rewrite an already assessed fine. Review the original return and use an authorized audited waiver where appropriate.

## Issue, return and renewal

Issues store the library code/name, operator UUID, timestamp, barcode/accession, title and patron code snapshots. A book must return to its issuing library.

1. Choose the correct library and click Issue a book. Verify the explicit library code, scan barcode or accession and enter patron code.
2. Save. The server checks copy availability, membership/expiry, loan limits, overdue loans, balance threshold and FIFO hold priority. Due dates follow the library calendar.
3. Open Circulation and locate the active loan by book, barcode or patron. Verify the library column and due date.
4. Use Renew only when permitted. Overdue loans, exhausted renewals, waiting holds, inactive memberships and excessive balances block renewal.
5. Use Return in the same library. The server rejects another issuing library code even for admin. Return, fine posting and copy availability commit together.
6. Inspect the return notice and assessed fine. In Returned loans choose Receipt and print its library, patron, book and fine details.

Each loan stores its policy values. Later policy edits apply to new loans; existing issues retain their recorded rules.

Do not repeat a successful return. The database rejects returns on a loan already closed.

## Troubleshooting and Koha coverage limits

The supplied Koha documentation informed the acquisition, advanced/item search, authority, migration, circulation, lists, OPAC, patron, report and serial workflows. This application implements the targeted workflows, not complete Koha compatibility.

1. Wrong password: use the registered React-library email and email recovery. A NetBeans/Derby account or patron number is a different identity.
2. No membership: ask admin to assign the correct library/role. A replaced librarian may retain an Auth identity without access to the old library.
3. Issue rejected: check library code, copy status, active membership, expiry, loan limits, overdue loans, balance threshold and hold priority.
4. Fine seems wrong: inspect saved policy, eligible dates, holidays, availability, grace and cap. Already-posted charges require an authorized waiver when correcting past dates.
5. No email: inspect spam, use the latest request, verify the address, SMTP limits and Auth redirect settings. The owner confirmed administrator recovery-email delivery during setup.
6. Import fails: inspect required columns, duplicates and invalid numbers. A failing batch rolls back.
7. Slow catalogue: narrow the search and use Show more. Accessible library snapshots still load the full collection; substantially larger collections/audit histories require server pagination.

Outside scope: offline circulation, RFID/SIP2, EDI, SSO, federated discovery, complex serial schedules, automated claims/hold emails, purchase suggestions, reviews/tags, partial receipts and full MARC editing/export.

Same-library returns intentionally prevent inter-library returns. Report errors without sharing passwords, private keys or student exports.
