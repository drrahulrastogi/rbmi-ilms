import React,{useState,useEffect} from 'react';
import {supabase,assetURL,returnToSignIn,recoveryEntry} from './api';
import {requestPasswordRecovery,saveRecoveredPassword} from './recovery-flow.mjs';
import {confirmRecoveryLink} from './recovery-link.mjs';
import {strongPassword} from '../server/patron-credentials.mjs';

export function ForgotPassword({onBack}){
 const [email,setEmail]=useState(''),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState(false),[cooldown,setCooldown]=useState(0);
 useEffect(()=>{if(!cooldown)return;const timer=setTimeout(()=>setCooldown(value=>Math.max(0,value-1)),1000);return()=>clearTimeout(timer);},[cooldown]);
 async function submit(event){
  event.preventDefault();if(busy||cooldown)return;setBusy(true);setMessage('');setError(false);
  try{const result=await requestPasswordRecovery(fetch,email);setMessage(result.message);setCooldown(result.retryAfter);}
  catch(error){setMessage(error.message);setError(true);if(error.retryAfter)setCooldown(error.retryAfter);}
  finally{setBusy(false);}
 }
 return <div className="login"><div className="login-art"><img className="login-logo" src={assetURL('rbmi-logo.png')} alt="RBMI Group of Institutions"/><h1>Recover your library account</h1><p>For every role, including the administrator.</p></div><form onSubmit={submit}><h2>Forgot password</h2><p>Enter your registered email address. Open the newest reset link to choose a new password.</p><label>Account email<input type="email" required maxLength={254} autoComplete="email" autoCapitalize="none" spellCheck={false} value={email} onChange={e=>setEmail(e.target.value)} disabled={busy}/></label>{message&&<p role={error?'alert':'status'} className={'alert'+(error?' error':'')}>{message}</p>}<button className="button primary" disabled={busy||cooldown>0}>{busy?'Requesting…':cooldown?'Request again in '+cooldown+'s':'Send recovery email'}</button><button type="button" className="text-button" disabled={busy} onClick={onBack}>Back to sign in</button><p className="muted">Cannot access your email or receive a reset message? Ask your librarian to arrange an administrator password reset. You will choose your own private password after signing in.</p></form></div>;
}

export function Recovery({recoverySession}){
 const [verified,setVerified]=useState(Boolean(recoverySession)),[password,setPassword]=useState(''),[confirm,setConfirm]=useState(''),[busy,setBusy]=useState(false),[checking,setChecking]=useState(false),[message,setMessage]=useState(recoveryEntry.error||'');
 useEffect(()=>{if(recoverySession)setVerified(true);},[recoverySession]);
 useEffect(()=>{
  if(verified||!recoveryEntry.accessToken||recoveryEntry.tokenHash||recoveryEntry.code||recoveryEntry.error)return;
  let active=true;setChecking(true);
  confirmRecoveryLink(supabase,recoveryEntry).then(()=>{if(active)setVerified(true);}).catch(error=>{if(active)setMessage(error.message);}).finally(()=>{if(active)setChecking(false);});
  return()=>{active=false;};
 },[verified]);
 useEffect(()=>{if(verified)history.replaceState({},'',location.pathname+'?recovery=1');},[verified]);
 async function submit(event){
  event.preventDefault();if(busy||checking)return;setBusy(true);setMessage('');
  try{
   if(!verified){await confirmRecoveryLink(supabase,recoveryEntry);setVerified(true);return;}
   if(password!==confirm||!strongPassword(password))throw Error('Use matching passwords of 12–128 characters with uppercase, lowercase, a number and a symbol.');
   await saveRecoveredPassword(supabase,fetch,password);
   await returnToSignIn('password_changed',{scope:'global',skipRemote:false});
  }catch(error){setMessage(error.message);}finally{setBusy(false);}
 }
 return <div className="login"><div className="login-art"><img className="login-logo" src={assetURL('rbmi-logo.png')} alt="RBMI"/><h1>Choose a new password</h1><p>RBCET / RBMI · RBCP · RBCN · RBGN</p></div><form onSubmit={submit}><h2>{verified?'Reset password':'Confirm password recovery'}</h2>{!verified?<p>{checking?'Verifying your private reset session…':'Continue to verify the one-use link from your recovery email.'}</p>:<><label>New password<input type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={password} onChange={e=>setPassword(e.target.value)}/></label><label>Confirm new password<input type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={confirm} onChange={e=>setConfirm(e.target.value)}/></label><p>Use 12–128 characters with uppercase, lowercase, a number and a symbol.</p></>}{message&&<p role="alert" className="alert error">{message}</p>}<button className="button primary" disabled={busy||checking||(!verified&&Boolean(recoveryEntry.error))}>{busy||checking?'Please wait…':verified?'Save new password':'Continue securely'}</button>{!verified&&<button type="button" className="text-button" disabled={busy||checking} onClick={()=>window.location.replace(location.pathname+'?forgot=1')}>Request a new reset email</button>}<button type="button" className="text-button" disabled={busy||checking} onClick={()=>returnToSignIn()}>Return to sign in</button></form></div>;
}
