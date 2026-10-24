import {createClient} from '@supabase/supabase-js';
import {secureAccountEndpoint} from '../server/account-security.mjs';
export default secureAccountEndpoint('password',['POST'],async(req,res,{client,service,opts,auth,token,url,key})=>{
 const {institution,target,currentPassword,password,confirmPassword,mode}=req.body||{};
 if(!['reset','change'].includes(mode)||typeof institution!=='string'||typeof currentPassword!=='string'||typeof password!=='string'||password!==confirmPassword||password.length<12||password.length>128||!/[a-z]/.test(password)||!/[A-Z]/.test(password)||!/[0-9]/.test(password)||!/[^a-zA-Z0-9]/.test(password))return res.status(400).json({error:'Use matching passwords of 12-128 characters with uppercase, lowercase, a number and a symbol'});
 const targetId=mode==='change'?auth.user.id:target;
 if(!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(targetId||''))return res.status(400).json({error:'Select a valid account'});
 if(password===currentPassword)return res.status(400).json({error:'Choose a different password'});
 try{
  if(mode==='reset'){
   const {error}=await client.rpc('library_password_authorize',{i:institution,target:targetId});
   if(error)return res.status(403).json({error:error.message});
  }else{
   const {data,error}=await client.rpc('library_bootstrap');
   if(error||!Array.isArray(data?.memberships)||!data.memberships.some(m=>m?.institution_id===institution))return res.status(403).json({error:'Institution membership required'});
  }
  const verifier=createClient(url,key,opts);
  const {data:verified,error}=await verifier.auth.signInWithPassword({email:auth.user.email,password:currentPassword});
  if(error||verified.user?.id!==auth.user.id)return res.status(403).json({error:'Your current password is incorrect'});
  await verifier.auth.signOut({scope:'local'});
  // Record only actor/target, never credentials. Abort if the audit cannot be written.
  const {error:auditError}=await service.rpc('library_password_audit',{i:institution,actor_id:auth.user.id,target:targetId,event:mode==='reset'?'password_reset':'password_change'});
  if(auditError)return res.status(503).json({error:'Unable to record password operation; try again later'});
  const {error:updateError}=await service.auth.admin.updateUserById(targetId,{password});
  if(updateError)return res.status(400).json({error:'Password update failed. Check the password requirements and try again.'});
  return res.status(200).json({ok:true});
 }catch{return res.status(503).json({error:'Password service unavailable; try again later'});}
});
