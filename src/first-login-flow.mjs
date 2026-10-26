export async function saveInitialPassword(client,send,values){
 const {data,error}=await client.auth.getSession();
 if(error||!data?.session?.access_token){const expired=Error('Your sign-in has expired. Return to sign in.');expired.code='session_not_found';throw expired;}
 const response=await send('/api/patron-logins',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+data.session.access_token},body:JSON.stringify({...values,mode:'first_change'})});
 const result=await response.json();
 if(!response.ok){const failed=Error(result.error||'Could not complete password setup');if(response.status===401)failed.code='session_not_found';throw failed;}
 return result;
}
