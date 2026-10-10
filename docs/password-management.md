# Password management

Open https://rbmi-ilms.vercel.app and sign in.

## Forgotten password: administrator
1. Verify the account owner's identity.
2. Select their institution and open Settings → Institution access.
3. Match the Auth user UUID to the account in your private login list.
4. Click Reset password beside that account.
5. Enter your own current password, then enter and confirm a unique new password of 12–128 characters containing uppercase, lowercase, a number and a symbol.
6. Save changes. Share the new password privately and ask the user to change it after signing in.

This works even for demo email addresses that cannot receive email. Administrators cannot view existing passwords. A shared account can be reset only by an administrator assigned to every institution on that account. An administrator cannot reset their own account this way; if they forget their password, the project owner must restore access through Supabase Auth.

## Change your own password
Every signed-in role has a Change my password button beneath Help in the sidebar. Enter your current password, new password and confirmation, then Save changes. The original private login CSV is not updated automatically after a password change.

## Deployment
Apply supabase/migrations/202610100002_password_management.sql after the original schema. Deploy the Vercel api/password.js server function together with the React app. Set SUPABASE_SERVICE_ROLE_KEY as a sensitive server-only production environment variable (never prefix it with VITE_, place it in browser code, or publish it). The other two public Supabase variables must also exist. Plain static hosting cannot support this server function. Local testing of this endpoint requires vercel dev.

Authorization is checked using the authenticated caller and institution membership. Current-password verification is required for either operation. Audit events store actor and target UUID only; they record an attempted authorized operation before the Auth update, so an Auth failure may also leave an event. The success message confirms completion. Passwords are never sent to database RPCs. Old access tokens may remain usable until their expiry; password updates should not be treated as instantaneous session revocation.
