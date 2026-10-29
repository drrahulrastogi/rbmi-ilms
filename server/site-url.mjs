export function librarySiteURL(){
 const url=new URL(process.env.APP_URL||'https://rbmi-ilms.vercel.app');
 if(url.protocol!=='https:'||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw new Error('APP_URL must be an HTTPS site origin');
 return url.origin;
}
