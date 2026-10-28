export function readRecoveryLink(location){
 const query=new URLSearchParams(location.search||''),fragment=new URLSearchParams((location.hash||'').replace(/^#/,''));
 const type=query.get('type')||fragment.get('type');
 const error=query.get('error_code')||fragment.get('error_code')||query.get('error')||fragment.get('error');
 const requested=query.get('recovery')==='1'||type==='recovery'||error==='otp_expired';
 return {requested,tokenHash:requested&&(!type||type==='recovery')?query.get('token_hash'):null,code:requested?query.get('code'):null,accessToken:type==='recovery'?fragment.get('access_token'):null,error:requested&&error?'This reset link has expired, is invalid, or has already been used. Request a new reset email.':null};
}

export async function confirmRecoveryLink(client,link){
 if(link.error)throw Error(link.error);
 let result;
 if(link.tokenHash)result=await client.auth.verifyOtp({token_hash:link.tokenHash,type:'recovery'});
 else if(link.code)result=await client.auth.exchangeCodeForSession(link.code);
 else if(link.accessToken){
  result=await client.auth.getSession();
  if(result.data?.session?.access_token!==link.accessToken)throw Error('This reset session is invalid. Request a new reset email.');
  const checked=await client.auth.getUser(link.accessToken);if(checked.error||!checked.data?.user)throw Error('This reset link has expired. Request a new reset email.');
 }else throw Error('Open the complete link from your reset email, or request a new reset email.');
 if(result.error)throw Error('This reset link has expired, is invalid, or has already been used. Request a new reset email.');
 if(!result.data?.session)throw Error('The reset session could not be verified. Request a new reset email.');
 return result.data.session;
}
