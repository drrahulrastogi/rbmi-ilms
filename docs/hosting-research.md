# Hosting decision - 9 October 2026

Recommended live stack: React/Vite on Cloudflare Pages + Supabase PostgreSQL/Auth. This avoids a separate always-running API process. The frontend calls three database RPCs with a Supabase Auth user token; transactional writes and permissions execute in PostgreSQL.

| Option | Current free offering / operational tradeoff | Decision |
|---|---|---|
| Supabase | 500 MB database, 50,000 monthly active users, 5 GB egress, two active projects; low-activity projects pause after one week; automatic database backups excluded from Free | Selected: integrated PostgreSQL, Auth and Data API make role-controlled institutional deployment simpler. Provide your own backups. |
| Cloudflare Pages | Free plan: 500 builds per month; static asset requests free and unlimited; 25 MiB single asset maximum. Functions have separate Workers quotas. | Selected frontend host. This application needs static hosting only. |
| Neon | Official 2 October 2026 announcement: Free storage increased to 1 GB per project, up to 100 projects. | Strong PostgreSQL alternative, but this Supabase-oriented Auth/API contract would need an additional API/auth integration. |
| Render | Free web services sleep after 15 minutes without incoming traffic; local filesystem is ephemeral. | Suitable alternate frontend static host; a sleeping API is unnecessary for the chosen architecture. |
| ChatGPT Sites | Available connected publishing channel in this task; new Sites are private by default. | Hosted demonstration with browser-local PostgreSQL and fictional data. It does not provision a live Supabase database. |

The best free option is not a promise of guaranteed institutional uptime. Free plans are suitable for evaluation and smaller workloads inside their limits. Measure actual catalogue/audit size and egress; price and quotas can change. Keep a current backup and consider a paid tier when continuity requirements exceed Free.

Primary sources checked:

- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/free-project-pausing
- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://developers.cloudflare.com/pages/platform/limits/
- https://developers.cloudflare.com/pages/functions/pricing/
- https://neon.com/blog/neon-free-plan-1-gb-per-project
- https://render.com/docs/free

HTML Help compiler reference: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/htmlhelp/about-html-help-workshop
