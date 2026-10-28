export async function requestPasswordRecovery(request,email){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
 try{
  const response=await request('/api/recovery',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:email.trim().toLowerCase()}),signal:controller.signal});
  let result;try{result=await response.json();}catch{throw Error('Recovery service is unavailable. Please try again later.');}
  if(!response.ok){const error=Error(result.error||'Recovery email could not be sent. Contact the library administrator.');error.retryAfter=response.status===429?Math.min(86400,Math.max(60,Number(response.headers?.get('Retry-After')||result.retryAfter)||60)):0;throw error;}
  return {message:result.message||'If an account exists for this email, a reset link will be sent. Check your inbox and spam folder.',retryAfter:Math.min(86400,Math.max(60,Number(result.retryAfter)||60))};
 }catch(error){if(error.name==='AbortError')throw Error('Recovery timed out. Check your inbox before retrying.');throw error;}
 finally{clearTimeout(timer);}
}

export async function saveRecoveredPassword(client,request,password){
 const {data:setup,error}=await client.rpc('library_onboarding');if(error)throw error;
 if(setup?.required&&['invite','admin_reset'].includes(setup.method)){
  const {data}=await client.auth.getSession();if(!data.session?.access_token)throw Error('Recovery session expired. Request a new email.');
  const response=await request('/api/patron-logins',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+data.session.access_token},body:JSON.stringify({mode:'first_change',password,confirmPassword:password})});const result=await response.json();if(!response.ok)throw Error(result.error||'Could not finish account setup');
 }else{const {error}=await client.auth.updateUser({password});if(error)throw error;}
}
