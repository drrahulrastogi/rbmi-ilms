import {createClient} from '@supabase/supabase-js';
import {initialPassword,strongPassword} from '../server/patron-credentials.mjs';
export const config={maxDuration:60};
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(req.method!=='POST')return res.status(405).json({error:'POST required'});
 const token=/^Bearer (.+)$/.exec(req.headers.authorization||'')?.[1];if(!token)return res.status(401).json({error:'Sign in required'});
 const url=process.env.VITE_SUPABASE_URL,key=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key||!secret)return res.status(503).json({error:'Account service is not configured'});
 const opts={auth:{persistSession:false,autoRefreshToken:false}},client=createClient(url,key,{...opts,global:{headers:{Authorization:'Bearer '+token}}}),service=createClient(url,secret,opts);
 const {data:auth,error:authError}=await client.auth.getUser(token);if(authError||!auth.user)return res.status(401).json({error:'Sign in required'});
 try{
  if(req.body?.mode==='first_change'){
   const {currentPassword,password,confirmPassword}=req.body;
   const {data:state,error:stateError}=await client.rpc('library_onboarding');
   if(stateError||!state?.required)return res.status(403).json({error:'No initial password change pending'});
   if(typeof currentPassword!=='string'||!strongPassword(password)||password!==confirmPassword||password===currentPassword)return res.status(400).json({error:'Choose a different password: 12–128 characters, uppercase, lowercase, number and symbol. Both new password entries must match.'});
   const verifier=createClient(url,key,opts),{data:v,error:ve}=await verifier.auth.signInWithPassword({email:auth.user.email,password:currentPassword});
   if(ve||v.user?.id!==auth.user.id)return res.status(403).json({error:'Your initial/current password is incorrect'});
   await verifier.auth.signOut({scope:'local'});
   const {error:revokeError}=await service.auth.admin.signOut(token,'global');if(revokeError)return res.status(503).json({error:'Could not end the initial sessions securely. Sign out, sign in again and retry setup.'});
   const {error:updateError}=await service.auth.admin.updateUserById(auth.user.id,{password});if(updateError)return res.status(400).json({error:'Could not update password. Sign in with the initial password and try another strong password.'});
   const {error:completeError}=await service.rpc('library_complete_first_login',{target:auth.user.id});if(completeError)return res.status(503).json({error:'Password changed but setup is still pending. Sign in with the new password and finish setup again.'});
   return res.status(200).json({ok:true,signInAgain:true});
  }
  const {institution,rows}=req.body||{};
  if(typeof institution!=='string'||!Array.isArray(rows)||!rows.length||rows.length>10||rows.some(r=>!r||typeof r.code!=='string'||typeof (r.password??'')!=='string')||new Set(rows.map(r=>r.code)).size!==rows.length)return res.status(400).json({error:'Provide 1 to 10 unique patron codes per request'});
  const {data:targets,error:targetError}=await client.rpc('library_login_targets',{i:institution,codes:rows.map(r=>r.code)});
  if(targetError)return res.status(403).json({error:'Library administrator or librarian required'});
  const results=[];
  for(const row of rows){
   const p=targets.find(p=>p.code===row.code);
   if(!p){results.push({code:row.code,status:'not_found',message:'No student/faculty membership in this library'});continue;}
   if(p.linked_user){results.push({code:p.code,status:'existing',message:'Existing login retained; password unchanged'});continue;}
   if(!p.active){results.push({code:p.code,status:'inactive',message:'Activate membership before creating login'});continue;}
   if(typeof p.email!=='string'||!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(p.email)||p.email.toLowerCase().endsWith('.invalid')){results.push({code:p.code,status:'missing_email',message:'A real, unique email address is required for login'});continue;}
   let password;try{password=initialPassword(p.institute,p.code,row.password||'');}catch{results.push({code:p.code,status:'invalid_password',message:'Initial password must contain 8 to 128 characters'});continue;}
   const {data:created,error:ce}=await service.auth.admin.createUser({email:p.email.trim(),password,email_confirm:true,user_metadata:{full_name:p.name}});
   if(ce||!created?.user){results.push({code:p.code,status:'review',message:'Account could not be created. Email may already be used; existing accounts are never overwritten or automatically linked.'});continue;}
   const {error:bindError}=await service.rpc('library_bind_imported_login',{i:institution,actor_id:auth.user.id,patron:p.id,target:created.user.id});
   if(bindError){await service.auth.admin.deleteUser(created.user.id);results.push({code:p.code,status:'review',message:'Could not link account to this membership; retry or ask administrator'});continue;}
   results.push({code:p.code,email:p.email,status:'created',message:'Login created; initial password change required. Email not sent.'});
  }
  return res.status(200).json({results});
 }catch{return res.status(503).json({error:'Account provisioning interrupted. Retry the upload; existing login passwords will be preserved.'});}
}
