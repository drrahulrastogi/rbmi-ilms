-- Preserve historical records; lifecycle restrictions affect access and new borrowing.
alter table app.copies add column accessioned_on date;
alter table app.copies alter column accessioned_on set default app.today();
create unique index copies_accession_casefold on app.copies(institution_id,lower(btrim(accession)));

alter table app.patrons add column status text not null default 'active' check(status in ('active','inactive','passed_out'));
alter table app.patrons add column course_end_date date;
alter table app.patrons add column graduation_override boolean not null default false;
update app.patrons set status='inactive' where not active;

create table app.course_policies(
 institution_id text not null references app.institutions,
 course text not null check(length(btrim(course)) between 1 and 200),
 duration_years integer not null check(duration_years in (2,3,4)),
 completion_month integer not null default 6 check(completion_month between 1 and 12),
 completion_day integer not null default 30 check(completion_day between 1 and 31),
 primary key(institution_id,course)
);
alter table app.course_policies enable row level security;
revoke all on app.course_policies from public,anon,authenticated;
grant all on app.course_policies to service_role;

insert into app.course_policies(institution_id,course,duration_years)
select institution_id,course,years from (
 select distinct institution_id,profile->>'course' course,
 case
 when lower(profile->>'course') ~ 'b[.]?tech|bachelor of pharmacy|bachelor of nursing' then 4
 when lower(profile->>'course') ~ 'master|bachelor of education|diploma in pharmacy' then 2
 when lower(profile->>'course') ~ 'hon' then null
 when lower(profile->>'course') ~ 'diploma.*engineering|bachelor of computer application|bachelor of business administration|bachelor of commerce|bsc' then 3
 end years from app.patrons where category='student' and nullif(btrim(profile->>'course'),'') is not null
) x where years is not null;

create function app.student_completion_date(p app.patrons) returns date language plpgsql stable security definer set search_path='' as $$
declare pol app.course_policies; y integer; last_day integer;admission text;end_year text;begin
 if p.category<>'student' then return null;end if;
 if p.course_end_date is not null then return p.course_end_date;end if;
 admission:=coalesce(p.profile->>'admission_year','');
 if admission !~ '^[12][0-9]{3}(-([12][0-9]{3}|[0-9]{2}))?$' then return null;end if;
 y:=left(admission,4)::integer;end_year:=split_part(admission,'-',2);
 if end_year<>'' and ((length(end_year)=4 and end_year::integer<>y+1) or (length(end_year)=2 and end_year::integer<>mod(y+1,100))) then return null;end if;
 select * into pol from app.course_policies where institution_id=p.institution_id and course=p.profile->>'course';
 if not found then return null;end if;
 y:=y+pol.duration_years;
 last_day:=extract(day from (make_date(y,pol.completion_month,1)+interval '1 month - 1 day'))::integer;
 return make_date(y,pol.completion_month,least(pol.completion_day,last_day));
end$$;
create function app.student_passed_out(p app.patrons) returns boolean language sql stable security definer set search_path='' as $$
 select p.category='student' and not p.graduation_override and (p.status='passed_out' or coalesce(app.student_completion_date(p)<app.today(),false))
$$;
create function app.sync_patron_lifecycle() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and app.student_passed_out(old) and (not app.student_passed_out(new) or new.category is distinct from old.category) and auth.uid() is not null and app.role_for(new.institution_id) is distinct from 'admin' then raise exception 'Only the administrator can reactivate a passed-out student';end if;
 if TG_OP='UPDATE' and new.graduation_override is distinct from old.graduation_override and auth.uid() is not null and app.role_for(new.institution_id) is distinct from 'admin' then raise exception 'Only the administrator can override course completion';end if;
 if new.category<>'student' then
  new.graduation_override:=false;
  if new.status='passed_out' then new.status:=case when new.active then 'active' else 'inactive' end;end if;
 elsif new.status='passed_out' and (TG_OP='INSERT' or new.status is distinct from old.status) then
  new.graduation_override:=false;new.active:=false;
 end if;
 if app.student_passed_out(new) then new.status:='passed_out';new.active:=false;
 elsif TG_OP='UPDATE' and new.status is distinct from old.status then new.active:=new.status='active';
 else new.status:=case when new.active then 'active' else 'inactive' end;
 end if;
 return new;
end$$;
create trigger patron_lifecycle before insert or update on app.patrons for each row execute function app.sync_patron_lifecycle();

create function app.mark_passed_out_students(library_code text default null) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 with changed as (
  update app.patrons p set status='passed_out',active=false
  where p.category='student' and p.status<>'passed_out' and (library_code is null or p.institution_id=library_code) and app.student_passed_out(p)
  returning p.*
 ) insert into app.audit(institution_id,actor,action,details)
 select institution_id,null,'student_passed_out',jsonb_build_object('patron_id',id,'completion_date',app.student_completion_date(changed::app.patrons),'automatic',true) from changed;
 get diagnostics n=row_count;return n;
end$$;
revoke all on function app.student_completion_date(app.patrons),app.student_passed_out(app.patrons),app.sync_patron_lifecycle(),app.mark_passed_out_students(text) from public,anon,authenticated;
grant execute on function app.mark_passed_out_students(text) to service_role;

create or replace function app.role_for(i text) returns text language sql stable security definer set search_path='' as $$
 select case
 when exists(select 1 from app.network_admin where user_id=auth.uid()) then 'admin'
 when exists(select 1 from app.library_staff where user_id=auth.uid()) and not exists(select 1 from app.library_staff where user_id=auth.uid() and institution_id=i) then null
 when m.role='admin' then null
 when m.role='librarian' and not exists(select 1 from app.library_staff where institution_id=i and user_id=auth.uid()) then null
 when m.role='patron' and exists(select 1 from app.patrons p where p.id=m.patron_id and app.student_passed_out(p)) then null
 else m.role end
 from app.institutions x left join app.memberships m on m.institution_id=x.id and m.user_id=auth.uid() where x.id=i and x.active
$$;

create or replace function app.require_role(i text,roles text[]) returns void language plpgsql security definer set search_path='' as $$
declare setup app.account_setup;issued bigint;begin
 perform app.require_admin_factor();
 select * into setup from app.account_setup where user_id=auth.uid();
 if setup.required then raise exception 'Change your initial password before accessing library records';end if;
 if setup.token_cutoff is not null then
  issued:=coalesce((nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'iat')::bigint,0);
  if issued<=setup.token_cutoff then raise exception 'Sign in again after changing your initial password';end if;
 end if;
 if app.role_for(i) is null and exists(select 1 from app.memberships m join app.patrons p on p.id=m.patron_id where m.user_id=auth.uid() and m.institution_id=i and m.role='patron' and app.student_passed_out(p)) then raise exception 'Student account is Passed out and disabled';end if;
 if app.role_for(i) is null or not(app.role_for(i)=any(roles)) then raise exception 'Access denied for this institution/action';end if;
end$$;

alter function public.library_onboarding() rename to library_onboarding_before_lifecycle;
revoke all on function public.library_onboarding_before_lifecycle() from public,anon,authenticated;
create function public.library_onboarding() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if not exists(select 1 from app.network_admin where user_id=auth.uid())
 and exists(select 1 from app.memberships m join app.patrons p on p.id=m.patron_id where m.user_id=auth.uid() and m.role='patron' and app.student_passed_out(p))
 and not exists(select 1 from app.memberships m left join app.patrons p on p.id=m.patron_id where m.user_id=auth.uid() and (m.role<>'patron' or (p.id is not null and not app.student_passed_out(p))))
 then return jsonb_build_object('required',false,'account_disabled',true,'reason','Your course is complete and your account is marked Passed out. Contact the administrator if access should be restored.');end if;
 return public.library_onboarding_before_lifecycle()||jsonb_build_object('account_disabled',false);
end$$;
revoke all on function public.library_onboarding() from public,anon;
grant execute on function public.library_onboarding() to authenticated;

create function public.library_course_policies(i text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 return (select coalesce(jsonb_agg(x order by x.course),'[]') from (
  select course,duration_years,completion_month,completion_day,true configured from app.course_policies where institution_id=i
  union all
  select distinct p.profile->>'course',null::integer,6,30,false from app.patrons p where p.institution_id=i and p.category='student' and nullif(btrim(p.profile->>'course'),'') is not null and not exists(select 1 from app.course_policies c where c.institution_id=i and c.course=p.profile->>'course')
 ) x);
end$$;
revoke all on function public.library_course_policies(text) from public,anon;
grant execute on function public.library_course_policies(text) to authenticated;

alter function public.library_action(text,text,jsonb) rename to library_action_before_lifecycle;
revoke all on function public.library_action_before_lifecycle(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;tid uuid;pat app.patrons;r jsonb;begin
 if action='course_policy' then
  perform app.require_role(i,array['admin']);
  insert into app.course_policies(institution_id,course,duration_years,completion_month,completion_day) values(i,btrim(p->>'course'),(p->>'duration_years')::integer,coalesce((p->>'completion_month')::integer,6),coalesce((p->>'completion_day')::integer,30))
  on conflict(institution_id,course) do update set duration_years=excluded.duration_years,completion_month=excluded.completion_month,completion_day=excluded.completion_day;
  perform app.mark_passed_out_students(i);
  insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,p);
  return jsonb_build_object('saved',true);
 elsif action in ('reactivate_student','resume_graduation') then
  perform app.require_role(i,array['admin']);
  if length(btrim(coalesce(p->>'reason','')))=0 then raise exception 'Administrator reason required';end if;
  select * into pat from app.patrons where institution_id=i and id=(p->>'id')::uuid and category='student' for update;
  if not found then raise exception 'Student not found in this library';end if;
  update app.patrons set graduation_override=action='reactivate_student',status='active',active=true where id=pat.id;
  insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,jsonb_build_object('patron_id',pat.id,'reason',p->>'reason'));
  return jsonb_build_object('saved',true);
 elsif action='book' then
  perform app.require_role(i,array['admin','librarian']);
  if length(btrim(coalesce(p->>'accession','')))=0 then raise exception 'Accession number is required';end if;
  perform pg_advisory_xact_lock(hashtext('book-barcode:'||lower(coalesce(nullif(btrim(p->>'barcode'),''),btrim(p->>'accession'))))::bigint);
  if exists(select 1 from app.copies where lower(btrim(barcode))=lower(coalesce(nullif(btrim(p->>'barcode'),''),btrim(p->>'accession')))) then raise exception 'Barcode already exists; enter a unique barcode';end if;
  result:=public.library_action_before_lifecycle(i,'title',p-'id');tid:=(result->>'id')::uuid;
  perform public.library_action_before_lifecycle(i,'copy',p||jsonb_build_object('title_id',tid,'accession',btrim(p->>'accession'),'barcode',coalesce(nullif(btrim(p->>'barcode'),''),btrim(p->>'accession'))));
  update app.copies set accessioned_on=coalesce(nullif(p->>'accessioned_on','')::date,app.today()) where institution_id=i and title_id=tid;
  return result;
 elsif action in ('issue','renew','hold') then
  perform app.require_role(i,array['admin','librarian','assistant','patron']);
  if action in ('issue','hold') then select * into pat from app.patrons where institution_id=i and code=p->>'patron_code';
  else select pp.* into pat from app.loans l join app.patrons pp on pp.id=l.patron_id where l.institution_id=i and l.id=(p->>'id')::uuid;end if;
  if pat.id is not null and app.student_passed_out(pat) then raise exception 'Student has passed out; account disabled. Administrator reactivation is required.';end if;
 end if;
 if action='patron' then
  perform app.require_role(i,array['admin','librarian']);
  if p?'graduation_override' then raise exception 'Use the administrator Reactivate or Resume automatic status action';end if;
 end if;
 result:=public.library_action_before_lifecycle(i,action,p);
 if action='copy' and p?'accessioned_on' then
  update app.copies set accessioned_on=coalesce(nullif(p->>'accessioned_on','')::date,app.today()) where institution_id=i and barcode=p->>'barcode';
 elsif action='patron' then
  update app.patrons set course_end_date=case when p?'course_end_date' then nullif(p->>'course_end_date','')::date else course_end_date end,
   status=coalesce(nullif(p->>'status',''),status),
   profile=profile||case when p?'course' then jsonb_build_object('course',btrim(p->>'course')) else '{}' end||case when p?'admission_year' then jsonb_build_object('admission_year',nullif(p->>'admission_year','')) else '{}' end
  where institution_id=i and code=p->>'code';
 elsif action='import' and p->>'kind' in ('students','faculty') then
  for r in select value from jsonb_array_elements(p->'rows') loop
   if r?'course_end_date' or r?'status' or r?'course' or r?'admission_year' then
    update app.patrons set course_end_date=case when r?'course_end_date' then nullif(r->>'course_end_date','')::date else course_end_date end,
     status=coalesce(nullif(r->>'status',''),status),
     profile=profile||case when r?'course' then jsonb_build_object('course',btrim(r->>'course')) else '{}' end||case when r?'admission_year' then jsonb_build_object('admission_year',nullif(r->>'admission_year','')) else '{}' end
    where institution_id=i and code=r->>'code';
   end if;
  end loop;
 end if;
 return result;
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

-- Every request also checks the derived date; cron persists the status after midnight IST.
do $outer$ begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') then
  execute 'create extension if not exists pg_cron with schema pg_catalog';
  execute $schedule$select cron.schedule('rbmi-student-course-completion','35 18 * * *','select app.mark_passed_out_students()')$schedule$;
 end if;
end $outer$;
select app.mark_passed_out_students();
notify pgrst,'reload schema';
