import React from 'react';
import {money} from './api';
export const fineMoney=amount=><span className="fine-amount">{money(amount)}</span>;
export function fineText(value,force=false){
 if(typeof value!=='string'||(!force&&!/fine/i.test(value)))return value;
 return value.split(/((?:₹|INR\s*)[\d,]+(?:\.\d{1,2})?)/g).map((part,n)=>/^(?:₹|INR)/.test(part)?<span className="fine-amount" key={n}>{part}</span>:part);
}
