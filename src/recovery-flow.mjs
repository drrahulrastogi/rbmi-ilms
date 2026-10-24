export async function saveRecoveredPassword(client,request,password){
 const {data:setup,error}=await client.rpc('library_onboarding');if(error)throw error;
 if(setup?.required&&setup.method==='invite'){
  const {data}=await client.auth.getSession();if(!data.session?.access_token)throw Error('Recovery session expired. Request a new email.');
  const response=await request('/api/patron-logins',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+data.session.access_token},body:JSON.stringify({mode:'first_change',password,confirmPassword:password})});const result=await response.json();if(!response.ok)throw Error(result.error||'Could not finish account setup');
 }else{const {error}=await client.auth.updateUser({password});if(error)throw error;}
}
