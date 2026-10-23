-- Add the separately operated RBGN library; no existing collection is moved.
insert into app.institutions(id,name,active,campuses) values('RBGN','RBGN Library',true,array['RBGN']) on conflict(id) do update set active=true;
insert into app.policies(institution_id,category,loan_days,max_loans,max_renewals,fine_rate,grace_days,fine_cap,block_balance,exclude_weekends)
select 'RBGN',c,case when c='faculty' then 30 else 14 end,case when c='faculty' then 10 else 3 end,2,2,1,500,100,true from unnest(array['student','faculty','staff','alumni','guest']) c on conflict(institution_id,category) do nothing;
insert into app.memberships(user_id,institution_id,role) select user_id,'RBGN','admin' from app.network_admin on conflict(user_id,institution_id) do update set role='admin',patron_id=null;
insert into app.audit(institution_id,actor,action,details) select 'RBGN',user_id,'library_added',jsonb_build_object('code','RBGN','name','RBGN Library') from app.network_admin;
