insert into app.institutions(id,name) values ('RBCET','RB College of Engineering & Technology'),('RBMI','RB Management Institute'),('RBCP','RB College of Pharmacy'),('RBCN','RB College of Nursing'),('RBTTI','RB Teacher Training Institute');
insert into app.policies(institution_id,category,loan_days,max_loans,max_renewals,fine_rate,grace_days,fine_cap,block_balance,exclude_weekends)
select id,c,case when c='faculty' then 30 else 14 end,case when c='faculty' then 10 else 3 end,2,2,1,500,100,true from app.institutions cross join unnest(array['student','faculty','staff','alumni','guest']) c;
-- No production patron data or default passwords are seeded.

-- Also support the CLI seed order (after all migrations), in addition to the
-- guarded installer/demo order (seed immediately after the original schema).
do $$begin
 if exists(select 1 from information_schema.columns where table_schema='app' and table_name='institutions' and column_name='active') then
  update app.institutions set active=(id in ('RBCET','RBCP','RBCN'));
  update app.institutions set name='RBCET / RBMI Central Library',campuses=array['RBCET','RBMI'] where id='RBCET';
  update app.institutions set name='RBCP Library',campuses=array['RBCP'] where id='RBCP';
  update app.institutions set name='RBCN Library',campuses=array['RBCN'] where id='RBCN';
 end if;
end$$;
