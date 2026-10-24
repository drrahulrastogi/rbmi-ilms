-- Passwords never enter application records, profiles, audit details or CSV exports.
create table app.account_setup(user_id uuid primary key references auth.users on delete cascade,required boolean not null default true,completed_at timestamptz,token_cutoff bigint);
alter table app.account_setup enable row level security;
revoke all on app.account_setup from public,anon,authenticated;
create or replace function app.require_role(i text,roles text[]) returns void language plpgsql security definer set search_path='' as $$
declare setup app.account_setup;issued bigint;
begin
 select * into setup from app.account_setup where user_id=auth.uid();
 if setup.required then raise exception 'Change your initial password before accessing library records';end if;
 if setup.token_cutoff is not null then
  issued:=coalesce((nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'iat')::bigint,0);
  if issued<=setup.token_cutoff then raise exception 'Sign in again after changing your initial password';end if;
 end if;
 if app.role_for(i) is null or not(app.role_for(i)=any(roles)) then raise exception 'Access denied for this institution/action';end if;
end$$;
create function public.library_onboarding() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 return jsonb_build_object('required',coalesce((select required from app.account_setup where user_id=auth.uid()),false));end$$;
revoke all on function public.library_onboarding() from public,anon;
grant execute on function public.library_onboarding() to authenticated;
create function public.library_login_targets(i text,codes jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform app.require_role(i,array['admin','librarian']);
 if jsonb_typeof(codes) is distinct from 'array' or jsonb_array_length(codes)>10 then raise exception 'At most ten patron codes per request';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'email',p.email,'active',p.active,'category',p.category,'institute',coalesce(p.profile->>'institute',i),'linked_user',(select m.user_id from app.memberships m where m.institution_id=i and m.patron_id=p.id and m.role='patron' limit 1))) from app.patrons p where p.institution_id=i and p.category in ('student','faculty') and p.code in (select jsonb_array_elements_text(codes))),'[]'::jsonb);
end$$;
revoke all on function public.library_login_targets(text,jsonb) from public,anon;
grant execute on function public.library_login_targets(text,jsonb) to authenticated;
create function public.library_bind_imported_login(i text,actor_id uuid,patron uuid,target uuid) returns void language plpgsql security definer set search_path='' as $$
declare p app.patrons;
begin
 if not exists(select 1 from app.network_admin where user_id=actor_id) and not exists(select 1 from app.memberships where institution_id=i and user_id=actor_id and role='librarian') then raise exception 'Library manager required';end if;
 select * into p from app.patrons where id=patron and institution_id=i for update;
 if p.id is null or p.category not in ('student','faculty') or not p.active then raise exception 'Active student or faculty membership required';end if;
 if not exists(select 1 from auth.users where id=target and lower(email)=lower(btrim(p.email))) then raise exception 'Account email must match the imported patron';end if;
 if exists(select 1 from app.memberships where user_id=target) or exists(select 1 from app.memberships where institution_id=i and patron_id=patron) then raise exception 'Account or patron already has a library assignment';end if;
 insert into app.account_setup(user_id) values(target);
 insert into app.memberships(user_id,institution_id,role,patron_id) values(target,i,'patron',patron);
 insert into app.audit(institution_id,actor,action,details) values(i,actor_id,'patron_login_created',jsonb_build_object('patron_id',patron,'user_id',target,'password_change_required',true));
end$$;
revoke all on function public.library_bind_imported_login(text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.library_bind_imported_login(text,uuid,uuid,uuid) to service_role;
create function public.library_complete_first_login(target uuid) returns void language plpgsql security definer set search_path='' as $$begin
 update app.account_setup set required=false,completed_at=now(),token_cutoff=floor(extract(epoch from clock_timestamp()))::bigint where user_id=target and required;
 if not found then raise exception 'No initial password change pending';end if;
 insert into app.audit(institution_id,actor,action,details) select institution_id,target,'initial_password_changed',jsonb_build_object('user_id',target) from app.memberships where user_id=target;
end$$;
revoke all on function public.library_complete_first_login(uuid) from public,anon,authenticated;
grant execute on function public.library_complete_first_login(uuid) to service_role;
-- Reject accidentally supplied password fields before the generic profile importer/auditor sees them.
alter function public.library_action(text,text,jsonb) rename to library_action_pre_accounts;
alter function public.library_action_pre_accounts(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_accounts(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if action in ('import','patron') and (p ? 'password' or p->'profile' ? 'password' or exists(select 1 from jsonb_array_elements(case when jsonb_typeof(p->'rows')='array' then p->'rows' else '[]'::jsonb end) r where r ? 'password' or r->'profile' ? 'password')) then raise exception 'Passwords must use the account provisioning service, not patron records';end if;
 return app.library_action_pre_accounts(i,action,p);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;
