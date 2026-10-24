import {createClient} from '@supabase/supabase-js';
import {secureAccountEndpoint} from '../server/account-security.mjs';
export default secureAccountEndpoint('accounts',['GET','POST'],async(req,res,{client,service,opts,auth,token,url,key})=>{
 const {data:boot,error:bootError}=await client.rpc('library_bootstrap');
 if(bootError||!Array.isArray(boot?.memberships)||!boot.memberships.some(m=>m?.role==='admin'))return res.status(403).json({error:'Network administrator required'});
 try{
 if(req.method==='GET'){
 const page=Number(req.query?.page||1);if(!Number.isInteger(page)||page<1||page>1000)return res.status(400).json({error:'Invalid account page'});
 const {data,error}=await service.auth.admin.listUsers({page,perPage:100});if(error)throw error;const users=data.users.map(u=>({id:u.id,email:u.email,name:u.user_metadata?.full_name||u.email}));
 return res.status(200).json({users,nextPage:users.length===100?page+1:null});}
 const {action,institution,currentPassword,email,name,password,role,target}=req.body||{};
 if(!boot.memberships.some(m=>m.institution_id===institution&&m.role==='admin'))return res.status(403).json({error:'Library administrator required'});
 if(!['create','update_email','send_reset'].includes(action)||typeof currentPassword!=='string')return res.status(400).json({error:'Valid account operation required'});
 const verify=createClient(url,key,opts);const {data:v,error:ve}=await verify.auth.signInWithPassword({email:auth.user.email,password:currentPassword});if(ve||v.user?.id!==auth.user.id)return res.status(403).json({error:'Your administrator password is incorrect'});await verify.auth.signOut({scope:'local'});
 if(action==='create'){
 if(!['librarian','assistant','accountant','auditor'].includes(role)||typeof name!=='string'||!name.trim()||typeof email!=='string'||!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))return res.status(400).json({error:'Provide a real email, name and permitted role'});
 const {data,error}=await service.auth.admin.inviteUserByEmail(email.trim(),{data:{full_name:name.trim()},redirectTo:'https://rbmi-ilms.vercel.app/?setup=invite'});if(error)return res.status(400).json({error:'Could not send invitation. Check the email and SMTP configuration.'});
 const assignment=await client.rpc('library_action',{i:institution,action:role==='librarian'?'assign_librarian':'member',p:{user_id:data.user.id,display_name:name.trim(),role}});
 if(assignment.error){await service.auth.admin.deleteUser(data.user.id);return res.status(400).json({error:assignment.error.message});}
 const setup=await service.rpc('library_mark_invitation',{target:data.user.id});if(setup.error)return res.status(503).json({error:'Account assigned; administrator must review pending password setup'});
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
 await service.rpc('library_refresh_invitation',{target});
 return res.status(200).json({ok:true});
 }catch{return res.status(503).json({error:'Account service unavailable; try again later'});}
});
