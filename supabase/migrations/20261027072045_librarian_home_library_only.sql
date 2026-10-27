-- A librarian's login is restricted to the one designated library.
-- Borrower records remain available to the librarian operating the issuing desk.
create or replace function app.role_for(i text) returns text language sql stable security definer set search_path='' as $$
 select case
 when exists(select 1 from app.network_admin where user_id=auth.uid()) then 'admin'
 when exists(select 1 from app.library_staff where user_id=auth.uid())
      and not exists(select 1 from app.library_staff where user_id=auth.uid() and institution_id=i) then null
 when m.role='admin' then null
 when m.role='librarian' and not exists(select 1 from app.library_staff where institution_id=i and user_id=auth.uid()) then null
 else m.role end
 from app.institutions x left join app.memberships m on m.institution_id=x.id and m.user_id=auth.uid()
 where x.id=i and x.active
$$;

with removed as (
 delete from app.memberships m using app.library_staff s
 where m.user_id=s.user_id and m.institution_id<>s.institution_id and m.role='patron'
 returning m.*
)
insert into app.audit(institution_id,actor,action,details)
select institution_id,null,'librarian_cross_library_login_removed',
 jsonb_build_object('user_id',user_id,'patron_id',patron_id,'previous_role',role,'reason','Assigned-library-only login policy')
from removed;
