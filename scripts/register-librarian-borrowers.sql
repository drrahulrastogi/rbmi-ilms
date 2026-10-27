-- Operator setup for the existing, verified designated librarians.
-- Creates borrowing memberships, not Auth accounts or additional staff roles.
-- Reuses an unambiguous existing borrower and never resets a password.
begin;
do $$
declare
 administrator uuid;
 library record;
 colleague record;
 borrower app.patrons%rowtype;
 matches integer;
 borrower_code text;
 existing_role text;
 linked_patron uuid;
begin
 perform pg_advisory_xact_lock(hashtext('rbmi-register-librarian-borrowers'));
 select n.user_id into strict administrator
 from app.network_admin n join auth.users u on u.id=n.user_id
 where lower(u.email)='rahul.r@rbmi.in';
 if not exists(select 1 from app.library_staff) then
  raise exception 'Assign the designated librarians before registering borrowers';
 end if;
 for library in select id from app.institutions where active order by id loop
  perform 1 from app.institutions where id=library.id for update;
  if not exists(select 1 from app.policies where institution_id=library.id and category='staff') then
   raise exception 'Staff borrowing policy missing for %',library.id;
  end if;
  for colleague in
   select s.user_id,s.institution_id home_library,s.display_name,u.email,u.email_confirmed_at,u.banned_until
   from app.library_staff s join app.institutions i on i.id=s.institution_id and i.active
   join auth.users u on u.id=s.user_id order by s.institution_id
  loop
   if colleague.email_confirmed_at is null or nullif(btrim(colleague.email),'') is null
      or colleague.banned_until>now() then
    raise exception 'Librarian account needs review for %',colleague.home_library;
   end if;
   select count(*) into matches from app.patrons
    where institution_id=library.id and lower(btrim(email))=lower(btrim(colleague.email));
   if matches>1 then raise exception 'Duplicate librarian borrower email in %',library.id;end if;
   if matches=1 then
    select * into strict borrower from app.patrons
     where institution_id=library.id and lower(btrim(email))=lower(btrim(colleague.email)) for update;
    if not borrower.active or borrower.expires<app.today() then
     raise exception 'Existing borrower inactive or expired: %',borrower.code;
    end if;
   else
    borrower_code:=library.id||'-LIB-'||colleague.home_library;
    if exists(select 1 from app.patrons where institution_id=library.id and code=borrower_code) then
     raise exception 'Librarian borrower code already belongs to another record: %',borrower_code;
    end if;
    insert into app.patrons(institution_id,code,name,email,category,department,active,profile)
    values(library.id,borrower_code,colleague.display_name,lower(btrim(colleague.email)),'staff','Library',true,
      jsonb_build_object('designation','Librarian','home_library_code',colleague.home_library,'registration_type','librarian_borrower'))
    returning * into borrower;
    insert into app.audit(institution_id,actor,action,details)
    values(library.id,administrator,'librarian_borrower_registered',
      jsonb_build_object('patron_id',borrower.id,'code',borrower.code,'user_id',colleague.user_id,'home_library',colleague.home_library));
   end if;
   existing_role:=null;linked_patron:=null;
   select role,patron_id into existing_role,linked_patron from app.memberships
    where user_id=colleague.user_id and institution_id=library.id for update;
   if library.id=colleague.home_library and existing_role is distinct from 'librarian' then
    raise exception 'Designated librarian membership needs review for %',library.id;
   end if;
   if linked_patron is not null and linked_patron<>borrower.id then
    raise exception 'Account already linked to a different borrower in %',library.id;
   end if;
   if existing_role is null then
    insert into app.memberships(user_id,institution_id,role,patron_id)
    values(colleague.user_id,library.id,'patron',borrower.id);
   elsif linked_patron is null then
    update app.memberships set patron_id=borrower.id
    where user_id=colleague.user_id and institution_id=library.id;
   else continue;
   end if;
   insert into app.audit(institution_id,actor,action,details)
   values(library.id,administrator,'librarian_borrower_linked',
    jsonb_build_object('user_id',colleague.user_id,'patron_id',borrower.id,'role',coalesce(existing_role,'patron')));
  end loop;
 end loop;
end $$;
commit;
