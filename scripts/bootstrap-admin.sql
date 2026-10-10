-- Run ONLY in the trusted Supabase SQL Editor after creating a user in Auth > Users.
-- Replace this UUID with that user's actual UUID. Do not run the placeholder unchanged.
insert into app.memberships(user_id,institution_id,role)
select 'REPLACE_WITH_AUTH_USER_UUID'::uuid,id,'admin' from app.institutions
on conflict(user_id,institution_id) do update set role='admin';
