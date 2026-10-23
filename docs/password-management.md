# RBMI ILMS 2.0 - password management

Updated 23 October 2026. The authoritative operator guide is docs/help/index.html.

## Change or recover a password

Email recovery is available to every role, including the administrator, through Supabase Auth and the configured SMTP service.

1. When signed in, select Change my password. Enter the current password, a different new password and matching confirmation.
2. When unable to sign in, choose Forgot password? Recover by email. Enter the registered address and check inbox and spam folders.
3. Open the newest recovery link. Continue securely if prompted, then enter and save a matching new password. Successful recovery signs you out; sign in with the new password.
4. Use 12 to 128 characters, including uppercase, lowercase, a number and a symbol. Choose a unique password for each person.
5. Admin may reset another assigned account in Settings > Institution access after verifying the person's identity and entering the administrator password. Share the temporary password privately and ask the person to change it.
6. For an expired, incomplete or previously used link, request a new email. Ask admin to correct a wrong registered email.

Staff cannot reset the administrator; the administrator recovers through their own registered email.

Old passwords cannot be read from Supabase. Passwords are excluded from audit records, GitHub and public source downloads. An initial-password file becomes stale after users change their passwords.

## Accounts and role permissions

Permissions are enforced by the database using memberships and designated librarian assignments. Editable user profile metadata is never used to grant access.

1. Admin manages all libraries, policies, accounts, assignments and audit records. The system permits one network administrator.
2. A librarian manages the assigned library's catalogue, patrons, circulation, fines, availability, acquisitions, authorities and serials. Each library has a distinct primary librarian.
3. Assistant operates circulation and holds. Accountant records payments and waivers. Auditor reads records and reports. Staff access is limited to assigned libraries.
4. Patron sign-ins must be linked to a patron UUID. They see the catalogue and their own loans, holds and fines, and can renew their own loans or manage their own holds.
5. Admin opens Settings > Accounts to create staff, update non-admin email addresses or send recovery messages. Sensitive actions require the administrator's current password.
6. To provision a patron sign-in, create its email/password identity in Supabase Auth, then assign patron role with the linked patron UUID in Institution access.

The create-account form supports librarian, assistant, accountant and auditor roles. Library records and Auth users are separate entities.

Retained sample accounts ending in .invalid cannot receive recovery emails. Replace them with real individual accounts before operational use.

