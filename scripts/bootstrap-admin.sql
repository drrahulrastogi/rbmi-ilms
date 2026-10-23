-- Run in trusted Supabase SQL Editor after creating rahul.r@rbmi.in in Auth.
-- Replace only the UUID. Exactly one network administrator is permitted.
begin;
insert into app.network_admin(singleton,user_id) values(true,'REPLACE_WITH_AUTH_USER_UUID'::uuid);
insert into app.memberships(user_id,institution_id,role)
select 'REPLACE_WITH_AUTH_USER_UUID'::uuid,id,'admin' from app.institutions where active
on conflict(user_id,institution_id) do update set role='admin';
commit;
