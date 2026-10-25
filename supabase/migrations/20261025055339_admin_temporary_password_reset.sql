-- Passwords remain in Supabase Auth only. This transaction records the guard and audit before Auth updates.
alter table app.account_setup drop constraint account_setup_method_check;
alter table app.account_setup add constraint account_setup_method_check check(method in ('legacy','invite','admin_reset'));
create function public.library_prepare_admin_password_reset(i text,actor_id uuid,target uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if target=actor_id then raise exception 'Use Change my password for your own account';end if;
 if not exists(select 1 from app.network_admin where user_id=actor_id) or not exists(select 1 from app.memberships where user_id=actor_id and institution_id=i and role='admin') then raise exception 'Administrator required';end if;
 if not exists(select 1 from app.memberships where user_id=target and institution_id=i) then raise exception 'Account is not assigned to this library';end if;
 if exists(select 1 from app.memberships where user_id=target and role='admin') then raise exception 'Use administrator account recovery';end if;
 if exists(select 1 from app.memberships m where m.user_id=target and not exists(select 1 from app.memberships a where a.user_id=actor_id and a.institution_id=m.institution_id and a.role='admin')) then raise exception 'Administrator access to every assigned library required';end if;
 insert into app.account_setup(user_id,required,method,expires_at,completed_at,token_cutoff) values(target,true,'admin_reset',null,null,floor(extract(epoch from clock_timestamp()))::bigint)
 on conflict(user_id) do update set required=true,method='admin_reset',expires_at=null,completed_at=null,token_cutoff=excluded.token_cutoff;
 insert into app.audit(institution_id,actor,action,details) values(i,actor_id,'password_reset',jsonb_build_object('target_user_id',target,'temporary',true,'status','requested'));
end$$;
revoke all on function public.library_prepare_admin_password_reset(text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.library_prepare_admin_password_reset(text,uuid,uuid) to service_role;
create or replace function public.library_onboarding() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 return coalesce((select jsonb_build_object('required',required,'method',method,'expired',required and expires_at is not null and expires_at<now(),'stale',required and method='admin_reset' and coalesce((nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'iat')::bigint,0)<=coalesce(token_cutoff,0)) from app.account_setup where user_id=auth.uid()),jsonb_build_object('required',false,'method','legacy','expired',false,'stale',false));
end$$;
notify pgrst,'reload schema';
