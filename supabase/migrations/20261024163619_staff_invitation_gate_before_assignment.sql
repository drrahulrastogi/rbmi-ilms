-- Establish the mandatory password gate before granting any staff role.
create or replace function public.library_mark_invitation(target uuid) returns void language plpgsql security definer set search_path='' as $$begin
 insert into app.account_setup(user_id,method,expires_at) select target,'invite',now()+interval '24 hours' where exists(select 1 from auth.users where id=target) on conflict(user_id) do update set method='invite',expires_at=now()+interval '24 hours' where app.account_setup.required;
 if not found then raise exception 'Pending setup required';end if;end$$;
revoke all on function public.library_mark_invitation(uuid) from public,anon,authenticated;
grant execute on function public.library_mark_invitation(uuid) to service_role;
notify pgrst, 'reload schema';
