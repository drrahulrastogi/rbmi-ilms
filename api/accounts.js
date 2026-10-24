import {createClient} from '@supabase/supabase-js';
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(!['GET','POST'].includes(req.method))return res.status(405).json({error:'GET or POST required'});
 const token=/^Bearer (.+)$/.exec(req.headers.authorization||'')?.[1],url=process.env.VITE_SUPABASE_URL,key=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!token)return res.status(401).json({error:'Sign in required'});
 if(!url||!key||!secret)return res.status(503).json({error:'Account service is not configured'});
 const opts={auth:{persistSession:false,autoRefreshToken:false}},client=createClient(url,key,{...opts,global:{headers:{Authorization:'Bearer '+token}}});
 const {data:auth,error:authError}=await client.auth.getUser(token);
 if(authError||!auth.user)return res.status(401).json({error:'Sign in required'});
 const {data:boot,error:bootError}=await client.rpc('library_bootstrap');
 if(bootError||!Array.isArray(boot?.memberships)||!boot.memberships.some(m=>m?.role==='admin'))return res.status(403).json({error:'Network administrator required'});
 const service=createClient(url,secret,opts);
 try{
 if(req.method==='GET'){
 const users=[];for(let page=1;page<=100;page++){const {data,error}=await service.auth.admin.listUsers({page,perPage:100});if(error)throw error;users.push(...data.users.map(u=>({id:u.id,email:u.email,name:u.user_metadata?.full_name||u.email})));if(data.users.length<100)break;}
 return res.status(200).json({users});}
 const {action,institution,currentPassword,email,name,password,role,target}=req.body||{};
 if(!boot.memberships.some(m=>m.institution_id===institution&&m.role==='admin'))return res.status(403).json({error:'Library administrator required'});
 if(!['create','update_email','send_reset'].includes(action)||typeof currentPassword!=='string')return res.status(400).json({error:'Valid account operation required'});
 const verify=createClient(url,key,opts);const {data:v,error:ve}=await verify.auth.signInWithPassword({email:auth.user.email,password:currentPassword});if(ve||v.user?.id!==auth.user.id)return res.status(403).json({error:'Your administrator password is incorrect'});await verify.auth.signOut({scope:'local'});
 if(action==='create'){
 if(!['librarian','assistant','accountant','auditor'].includes(role)||typeof name!=='string'||!name.trim()||typeof email!=='string'||!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)||typeof password!=='string'||password.length<12||password.length>128||!/[A-Z]/.test(password)||!/[a-z]/.test(password)||!/[0-9]/.test(password)||!/[^A-Za-z0-9]/.test(password))return res.status(400).json({error:'Provide a real email, name, permitted role and strong 12–128 character password'});
 const {data,error}=await service.auth.admin.createUser({email:email.trim(),password,email_confirm:true,user_metadata:{full_name:name.trim()}});if(error)return res.status(400).json({error:'Could not create account. Check whether the email already exists.'});
 const assignment=await client.rpc('library_action',{i:institution,action:role==='librarian'?'assign_librarian':'member',p:{user_id:data.user.id,display_name:name.trim(),role}});
 if(assignment.error){await service.auth.admin.deleteUser(data.user.id);return res.status(400).json({error:assignment.error.message});}
 return res.status(200).json({ok:true,id:data.user.id});
 }
 if(!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(target||''))return res.status(400).json({error:'Select a valid account'});
 const {data:targetData,error:te}=await service.auth.admin.getUserById(target);if(te)return res.status(400).json({error:'Account not found'});
 if(action==='update_email'){
 if(target===auth.user.id)return res.status(400).json({error:'The designated administrator email is fixed. Contact the project owner for an administrator email change.'});
 if(typeof email!=='string'||!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)||email.endsWith('.invalid'))return res.status(400).json({error:'A real verified email is required'});
 const {error}=await service.auth.admin.updateUserById(target,{email:email.trim(),email_confirm:true});if(error)return res.status(400).json({error:'Unable to update email; check whether it is already used'});
 // Only non-secret identity information is audited.
 await client.rpc('library_action',{i:institution,action:'account_email_audit',p:{target_user_id:target}});
 return res.status(200).json({ok:true});}
 const targetEmail=targetData.user.email;
 if(targetEmail?.endsWith('.invalid'))return res.status(400).json({error:'Replace the sample address with a real email first'});
 const {error}=await service.auth.resetPasswordForEmail(targetEmail,{redirectTo:'https://rbmi-ilms.vercel.app/?recovery=1'});if(error)return res.status(503).json({error:'Recovery email could not be sent. Check the Supabase SMTP configuration.'});
 return res.status(200).json({ok:true});
 }catch{return res.status(503).json({error:'Account service unavailable; try again later'});}
}
