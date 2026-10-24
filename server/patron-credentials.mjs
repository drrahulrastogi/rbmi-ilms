export function initialPassword(institute,code,supplied='') {
 if(typeof supplied!=='string')throw Error('Password must be text');
 const value=supplied||`${institute}@${code}`;
 if(value.length<8||value.length>128)throw Error('Initial password must contain 8 to 128 characters');
 return value;
}
export function strongPassword(value){return typeof value==='string'&&value.length>=12&&value.length<=128&&/[A-Z]/.test(value)&&/[a-z]/.test(value)&&/[0-9]/.test(value)&&/[^A-Za-z0-9]/.test(value);}
export function withoutPasswords(row){const {password,...safe}=row;const {password:profilePassword,...profile}=safe.profile&&typeof safe.profile==='object'?safe.profile:{};return {...safe,...(safe.profile?{profile}:{})};}
