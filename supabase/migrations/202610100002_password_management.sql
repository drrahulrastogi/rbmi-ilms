-- Server-authorized password management; passwords never enter SQL or audit.
create or replace function public.library_password_authorize(i text, target uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform app.require_role(i,array['admin']);
 if target=auth.uid() then raise exception 'Use Change my password for your own account'; end if;
 if not exists(select 1 from app.memberships where user_id=target and institution_id=i) then raise exception 'Account is not assigned to this institution'; end if;
 if exists(select 1 from app.memberships m where m.user_id=target and coalesce(app.role_for(m.institution_id),'')<>'admin') then raise exception 'Reset requires administrator access to every institution assigned to this account'; end if;
 return true;
end$$;
revoke all on function public.library_password_authorize(text,uuid) from public,anon;
grant execute on function public.library_password_authorize(text,uuid) to authenticated;
create or replace function public.library_password_audit(i text, actor_id uuid, target uuid, event text) returns void language plpgsql security definer set search_path='' as $$
begin
 if event not in ('password_reset','password_change') then raise exception 'Invalid password event'; end if;
 if event='password_reset' and not exists(select 1 from app.memberships where user_id=actor_id and institution_id=i and role='admin') then raise exception 'Administrator required'; end if;
 if event='password_change' and actor_id<>target then raise exception 'Own account required'; end if;
 if not exists(select 1 from app.memberships where user_id=target and institution_id=i) then raise exception 'Membership required'; end if;
 insert into app.audit(institution_id,actor,action,details) values(i,actor_id,event,jsonb_build_object('target_user_id',target));
end$$;
revoke all on function public.library_password_audit(text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.library_password_audit(text,uuid,uuid,text) to service_role;
