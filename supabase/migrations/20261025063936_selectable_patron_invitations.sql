create index patrons_invitation_scope on app.patrons(institution_id,category,id);
create function public.library_invitation_candidates_page(i text,patron_category text,campus_filter text default '',q text default '',after_id uuid default null,page_size integer default 50,eligible_only boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;begin
 perform app.require_role(i,array['admin','librarian']);perform app.read_budget('invitations');
 if patron_category not in ('student','faculty') or patron_category is null then raise exception 'Select students or faculty';end if;
 if page_size is null or page_size<1 or page_size>1000 or length(coalesce(q,''))>150 or eligible_only is null then raise exception 'Invalid invitation page';end if;
 if coalesce(campus_filter,'')<>'' and not exists(select 1 from app.institutions where id=i and campus_filter=any(campuses)) then raise exception 'Institute is not part of this library';end if;
 with candidates as materialized (
  select p.id,p.code,p.name,p.email,p.category,p.department,p.active,p.expires,coalesce(p.profile->>'institute',i) institute,
   case when not p.active then 'inactive' when p.expires is not null and p.expires<app.today() then 'expired' when p.email is null or p.email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or lower(p.email) like '%.invalid' then 'missing_email' when m.user_id is null then 'not_created' when s.required and s.method='invite' then 'pending_invite' else 'existing' end login_status
  from app.patrons p left join app.memberships m on m.institution_id=p.institution_id and m.patron_id=p.id and m.role='patron' left join app.account_setup s on s.user_id=m.user_id
  where p.institution_id=i and p.category=patron_category and (coalesce(campus_filter,'')='' or coalesce(p.profile->>'institute',i)=campus_filter) and (coalesce(q,'')='' or p.name ilike '%'||q||'%' or p.code ilike '%'||q||'%' or p.email ilike '%'||q||'%' or p.department ilike '%'||q||'%' or p.profile::text ilike '%'||q||'%')
 ), marked as(select *,login_status in ('not_created','pending_invite') eligible from candidates),
 page as(select * from marked where (not eligible_only or eligible) and (after_id is null or id>after_id) order by id limit page_size+1),shown as(select * from page order by id limit page_size)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(t) order by id) from shown t),'[]'::jsonb),'next_id',case when (select count(*) from page)>page_size then (select id::text from shown order by id desc limit 1) else null end,'total',(select count(*) from marked where not eligible_only or eligible),'eligible_count',(select count(*) from marked where eligible)) into answer;
 return answer;
end$$;
revoke all on function public.library_invitation_candidates_page(text,text,text,text,uuid,integer,boolean) from public,anon;
grant execute on function public.library_invitation_candidates_page(text,text,text,text,uuid,integer,boolean) to authenticated;
create or replace function public.library_login_targets(i text,codes jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform app.require_role(i,array['admin','librarian']);
 if jsonb_typeof(codes) is distinct from 'array' or jsonb_array_length(codes)>10 then raise exception 'At most ten patron codes per request';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'email',p.email,'active',p.active,'expired',p.expires is not null and p.expires<app.today(),'category',p.category,'institute',coalesce(p.profile->>'institute',i),'linked_user',m.user_id,'pending_invite',coalesce(s.required and s.method='invite',false))) from app.patrons p left join app.memberships m on m.institution_id=p.institution_id and m.patron_id=p.id and m.role='patron' left join app.account_setup s on s.user_id=m.user_id where p.institution_id=i and p.category in ('student','faculty') and p.code in(select jsonb_array_elements_text(codes))),'[]'::jsonb);end$$;
notify pgrst,'reload schema';
