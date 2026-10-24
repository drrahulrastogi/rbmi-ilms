import {createClient} from '@supabase/supabase-js';
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');if(req.method!=='GET')return res.status(405).json({status:'unavailable'});
 try{const url=process.env.VITE_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!url||!key)return res.status(503).json({status:'unavailable'});
 const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(input,init)=>fetch(input,{...init,signal:AbortSignal.timeout(4000)})}});
 const {data,error}=await client.rpc('library_health');return res.status(!error&&data===true?200:503).json({status:!error&&data===true?'ok':'unavailable'});
 }catch{return res.status(503).json({status:'unavailable'});}
}
