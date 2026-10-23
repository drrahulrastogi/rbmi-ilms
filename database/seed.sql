insert into app.institutions values ('RBCET','RB College of Engineering & Technology'),('RBMI','RB Management Institute'),('RBCP','RB College of Pharmacy'),('RBCN','RB College of Nursing'),('RBTTI','RB Teacher Training Institute');
insert into app.policies(institution_id,category,loan_days,max_loans,max_renewals,fine_rate,grace_days,fine_cap,block_balance,exclude_weekends)
select id,c,case when c='faculty' then 30 else 14 end,case when c='faculty' then 10 else 3 end,2,2,1,500,100,true from app.institutions cross join unnest(array['student','faculty','staff','alumni','guest']) c;
-- No production patron data or default passwords are seeded.
