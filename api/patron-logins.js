import {createClient} from '@supabase/supabase-js';
import {strongPassword} from '../server/patron-credentials.mjs';
import {secureAccountEndpoint} from '../server/account-security.mjs';
export const config={maxDuration:60};
export default secureAccountEndpoint('patron-logins',['POST'],async(req,res,{client,service,opts,auth,token,url,key})=>{
 try{
  if(req.body?.mode==='first_change'){
   const {currentPassword,password,confirmPassword}=req.body;
   const {data:state,error:stateError}=await client.rpc('library_onboarding');
   if(stateError||!state?.required)return res.status(403).json({error:'No initial password change pending'});
   if(state.expired)return res.status(403).json({error:'This invitation has expired. Ask your librarian to resend the setup email.'});
   if(!strongPassword(password)||password!==confirmPassword||password===currentPassword)return res.status(400).json({error:'Choose a different password: 12–128 characters, uppercase, lowercase, number and symbol. Both new password entries must match.'});
   if(state.method!=='invite'){
   if(typeof currentPassword!=='string')return res.status(400).json({error:'Current password required'});
   const verifier=createClient(url,key,opts),{data:v,error:ve}=await verifier.auth.signInWithPassword({email:auth.user.email,password:currentPassword});
   if(ve||v.user?.id!==auth.user.id)return res.status(403).json({error:'Your initial/current password is incorrect'});
   await verifier.auth.signOut({scope:'local'});
   }else if(!auth.user.email_confirmed_at)return res.status(403).json({error:'Open your invitation email to verify this account first'});
   const {error:revokeError}=await service.auth.admin.signOut(token,'global');if(revokeError)return res.status(503).json({error:'Could not end the initial sessions securely. Sign out, sign in again and retry setup.'});
   const {error:updateError}=await service.auth.admin.updateUserById(auth.user.id,{password});if(updateError)return res.status(400).json({error:'Could not update password. Sign in with the initial password and try another strong password.'});
   const {error:completeError}=await service.rpc('library_complete_first_login',{target:auth.user.id});if(completeError)return res.status(503).json({error:'Password changed but setup is still pending. Sign in with the new password and finish setup again.'});
   return res.status(200).json({ok:true,signInAgain:true});
  }
  const {institution,rows}=req.body||{};
  if(typeof institution!=='string'||!Array.isArray(rows)||!rows.length||rows.length>10||rows.some(r=>!r||typeof r.code!=='string'||typeof (r.password??'')!=='string')||new Set(rows.map(r=>r.code)).size!==rows.length)return res.status(400).json({error:'Provide 1 to 10 unique patron codes per request'});
  const {data:targets,error:targetError}=await client.rpc('library_login_targets',{i:institution,codes:rows.map(r=>r.code)});
  if(targetError||!Array.isArray(targets))return res.status(403).json({error:'Library administrator or librarian required'});
  const results=[];
  for(const row of rows){
   const p=targets.find(p=>p.code===row.code);
   if(!p){results.push({code:row.code,status:'not_found',message:'No student/faculty membership in this library'});continue;}
   if(p.linked_user){
    if(p.pending_invite&&req.body.resend===true){const {data:target,error}=await service.auth.admin.getUserById(p.linked_user);if(error||target.user?.email?.toLowerCase()!==p.email?.trim().toLowerCase()){results.push({code:p.code,status:'review',message:'Account email differs; administrator review required'});continue;}
     const sent=await service.auth.resetPasswordForEmail(target.user.email,{redirectTo:'https://rbmi-ilms.vercel.app/?setup=invite'});if(sent.error){results.push({code:p.code,status:'review',message:'Setup email could not be sent; check SMTP or retry later'});continue;}
     await service.rpc('library_refresh_invitation',{target:p.linked_user});results.push({code:p.code,status:'resent',message:'A new setup email was requested; earlier expired links should be discarded'});
    }else results.push({code:p.code,status:p.pending_invite?'pending_invite':'existing',message:p.pending_invite?'Invitation awaiting password setup. Resend if the email has expired.':'Existing login retained; password unchanged'});continue;}
   if(!p.active){results.push({code:p.code,status:'inactive',message:'Activate membership before creating login'});continue;}
   if(typeof p.email!=='string'||!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(p.email)||p.email.toLowerCase().endsWith('.invalid')){results.push({code:p.code,status:'missing_email',message:'A real, unique email address is required for login'});continue;}
   const {data:created,error:ce}=await service.auth.admin.inviteUserByEmail(p.email.trim(),{data:{full_name:p.name},redirectTo:'https://rbmi-ilms.vercel.app/?setup=invite'});
   if(ce||!created?.user){results.push({code:p.code,status:'review',message:'Account could not be created. Email may already be used; existing accounts are never overwritten or automatically linked.'});continue;}
   const {error:bindError}=await service.rpc('library_bind_imported_login',{i:institution,actor_id:auth.user.id,patron:p.id,target:created.user.id});
   if(bindError){await service.auth.admin.deleteUser(created.user.id);results.push({code:p.code,status:'review',message:'Could not link account to this membership; retry or ask administrator'});continue;}
   const {error:setupError}=await service.rpc('library_mark_invitation',{target:created.user.id});
   if(setupError){results.push({code:p.code,status:'review',message:'Account linked; setup needs administrator review before access is allowed.'});continue;}
   results.push({code:p.code,email:p.email,status:'created',message:'Invitation email requested. Open the one-use link to choose your own password.'});
  }
  return res.status(200).json({results});
 }catch{return res.status(503).json({error:'Account provisioning interrupted. Retry the upload; existing login passwords will be preserved.'});}
});
