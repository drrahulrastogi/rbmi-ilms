import {createClient} from '@supabase/supabase-js';
import {createHash,randomUUID} from 'node:crypto';

const site='https://rbmi-ilms.vercel.app';
export default async function recovery(req,res){
 const requestId=randomUUID(),started=Date.now();
 res.setHeader('Cache-Control','no-store');res.setHeader('X-Request-ID',requestId);
 try{
  if(req.method!=='POST'){res.setHeader('Allow','POST');return res.status(405).json({error:'POST required'});}
  const origins=new Set([site,'https://rbmi-ilms-engg1.vercel.app']);
  if(process.env.VERCEL_URL)origins.add('https://'+process.env.VERCEL_URL);
  if((req.headers.origin&&!origins.has(req.headers.origin))||req.headers['sec-fetch-site']==='cross-site')return res.status(403).json({error:'Open password recovery from the library website.'});
  if(!String(req.headers['content-type']||'').toLowerCase().startsWith('application/json'))return res.status(415).json({error:'JSON required'});
  if(Buffer.byteLength(JSON.stringify(req.body||{}))>1024)return res.status(413).json({error:'Request too large'});
  const email=typeof req.body?.email==='string'?req.body.email.trim().toLowerCase():'';
  if(!email||email.length>254||!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)||Object.keys(req.body).some(k=>k!=='email'))return res.status(400).json({error:'Enter your registered email address.'});
  if(email.endsWith('.invalid'))return res.status(400).json({error:'Ask the library administrator to replace the sample email with your real email first.'});
  const url=process.env.VITE_SUPABASE_URL,key=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!key||!secret)return res.status(503).json({error:'Email recovery is unavailable. Ask the library administrator for a temporary password.'});
  const deadline=AbortSignal.timeout(12000),opts={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:(input,init)=>fetch(input,{...init,signal:deadline})}};
  const service=createClient(url,secret,opts),client=createClient(url,key,opts);
  const ip=process.env.VERCEL==='1'?String(req.headers['x-vercel-forwarded-for']||req.headers['x-forwarded-for']||req.socket?.remoteAddress||'unknown').split(',')[0].trim():String(req.socket?.remoteAddress||'local');
  const hash=value=>createHash('sha256').update(secret+'\0'+value).digest('hex');
  for(const [operation,subject] of [['preauth','recovery-ip:'+hash(ip)],['password','recovery-email:'+hash(email)]]){
   const {data,error}=await service.rpc('library_api_quota',{operation,subject});
   if(error||typeof data?.allowed!=='boolean')return res.status(503).json({error:'Recovery is temporarily unavailable. Please try again later.'});
   if(!data.allowed){const retry=Math.max(60,Number(data.retry_after)||60);res.setHeader('Retry-After',String(retry));return res.status(429).json({error:'Too many recovery requests. Please wait before trying again.',retryAfter:retry});}
  }
  const {error}=await client.auth.resetPasswordForEmail(email,{redirectTo:site+'/?recovery=1'});
  if(error){
   if(error.status===429||['over_email_send_rate_limit','over_request_rate_limit'].includes(error.code)){res.setHeader('Retry-After','60');return res.status(429).json({error:'Recovery email requests are temporarily limited. Wait before requesting another link.',retryAfter:60});}
   if(!['user_not_found'].includes(error.code))return res.status(503).json({error:'Recovery email could not be sent. Ask the library administrator to check the email service or set a temporary password.'});
  }
  return res.status(200).json({ok:true,retryAfter:60,message:'If an account exists for this email, a reset link will be sent. Check your inbox and spam folder. Use only the newest link.'});
 }catch{return res.status(503).json({error:'Recovery could not finish. Check your inbox before retrying, or ask the library administrator for a temporary password.'});}
 finally{console.info(JSON.stringify({event:'password_recovery_request',request_id:requestId,status:res.statusCode||200,duration_ms:Date.now()-started}));}
}
