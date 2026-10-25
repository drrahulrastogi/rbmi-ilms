# Send selected student or faculty invitations

1. Select the library, open **Patrons**, then choose **Student invitations** or **Faculty invitations**. These are separate lists and selections.
2. Select an institute within that library. For the shared central library you can choose RBCET, RBMI or both. Search by name, membership code, email, department or class/profile text.
3. Tick individual eligible rows, **Select eligible on this page**, or **Select all students** / **Select all faculty members**. The table header also has **Select all on this page**. Uncheck a master checkbox to deselect its scope; a dash indicates a partial selection. Selection spans pages, with a 5,000-person limit. A wider result must be narrowed. Changing institute, search or recipient type clears the selection.
4. Review the displayed count and recipients, tick the approval checkbox, then press **Send invitations to ... selected students/faculty members**. This is the point that requests actual emails.
5. Keep the page open. Requests run sequentially in batches of ten. **Stop after current batch** prevents later batches; an already submitted batch cannot be recalled. Leaving the screen also stops later batches.
6. Review per-person results and optionally export them as CSV. **Select unsent recipients for retry** selects only people explicitly marked not sent or rate limited, and requires another review/approval. An uncertain result must be inspected before resending, since its email may already have been requested.

New logins get the normal one-use invitation link and choose their own password. Pending setup invitations get a new recovery/setup link. Completed accounts are retained: this screen does not change their passwords or automatically send them recovery emails. Use Accounts and password management for an intentional password reset.

Inactive/expired memberships, missing/invalid emails and completed accounts cannot be selected. The server rechecks category, institute, active state and expiry at the time of each batch, so editing a membership after selection cannot bypass these checks. An email already used by another unlinked Auth account requires administrator review; accounts are never silently merged or overwritten.

The list is available only to the administrator and the assigned library's librarian. Assistants, auditors and patrons cannot read this private invitation directory or send invitations through the API. The same screens work in the existing Android online client; no new APK is needed.

## Sending limits and results

**Requested is not delivered.** Supabase/SMTP acceptance is reported; inbox delivery, bounces and spam filtering remain controlled by the mail provider. SMTP must be configured and its quotas must suit the intended batch. Provider rate limits or server failures pause the remaining queue; there is no automatic retry that could flood recipients. Sending queues/results live in the current browser screen and are not persisted after it closes. Separate simultaneous operators are still subject to the application's shared request limits and the provider's limits.

Common result codes: `created` (new invitation requested), `resent` (pending setup email requested), `existing` (login retained), `inactive`, `expired`, `missing_email`, `wrong_category`, `wrong_institute`, `review`, `rate_limited`, `not_sent` and `unknown` (inspect before retry).

The maximum selection is not a promise that 5,000 emails will be delivered in one session. Review [Supabase Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits) and your SMTP provider's quotas before a large mailing. This feature does not change paid plans, quotas or provider configuration automatically.

## Verification

Tests cover category/campus separation, keyset pagination, role restrictions, invalid/expired/inactive eligibility, selection across pages, duplicate protection, sequential batches, stopping, network uncertainty, provider throttling and email-service failures. Email SDK requests are mocked during regression tests; no real student/faculty invitation is sent as part of release verification.
