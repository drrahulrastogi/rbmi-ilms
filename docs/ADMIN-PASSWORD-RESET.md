# Administrator direct password reset

Open **Settings → Accounts and password management**. Select the person's assigned library in the workspace selector first. Choose **Set temporary password directly (no email needed)**, or click **Set temporary password** beside that account.

Select the account, enter and confirm a unique temporary password (12–128 characters, uppercase, lowercase, number and symbol), then enter **your administrator password** and press **Set temporary password**. The other person's current password is never requested. Share the temporary password privately after verifying the recipient's identity.

The user signs in using their registered email and the temporary password. Before opening library records, they must choose a different private password, then sign in again. No email is sent by the direct reset. Existing email-verification requirements and MFA are not bypassed. Email recovery remains a separate option, including for the administrator's own forgotten password; use Change my password for a normal administrator self-change.

The same controls appear in the Android online client automatically. No new APK is needed for this website update.

## Enforcement

- The server validates the caller's Auth identity and MFA state, checks administrator access to every library assigned to the target, and verifies the caller's current administrator password.
- A service-only transaction re-arms mandatory onboarding, records a token cutoff and writes a credential-free audit event before changing the Auth password. Browser roles cannot call that transaction.
- If preparation fails, the Auth password is untouched. If the subsequent Auth update fails, access remains blocked pending setup and the administrator can retry the direct reset. Auth and application SQL are separate services, so this operation intentionally fails closed rather than claiming a cross-service atomic transaction.
- Previous sessions cannot access library records while setup is required. The completion endpoint also rejects a pre-reset JWT. A new login/recovery token must be newer than the reset's second-resolution cutoff; if a reset and login occur within the same second, sign out and try signing in again after a moment.
- The first-change endpoint refuses reuse of the temporary Auth password, revokes the caller's refresh sessions, updates the private password and completes onboarding. Old JWTs remain excluded by the database cutoff even after completion. Already-issued Auth JWTs are not claimed to be cryptographically revoked.
- Only actor, target and reset-request metadata enter the application audit. No actual password is stored in application SQL, audit details, responses, GitHub or browser console logs. A reset audit event records a requested attempt; the UI shows success only after Auth accepts the password update.
- Shared account rate limits apply. An unrelated library, non-admin, self-reset through the other-user flow, weak password, wrong administrator password or missing audit/setup service is rejected.

## Verification

Regression tests were written first for API authorization, administrator reauthentication, setup-before-update ordering, fail-closed preparation, stale sessions, temporary-password reuse and private-password completion. Database tests cover service-only permissions, account scope, re-arming completed staff onboarding and audit-field privacy. A recovery-flow test prevents bypass of mandatory setup. See the release's test evidence for observed results; no real account password was changed as a test.
