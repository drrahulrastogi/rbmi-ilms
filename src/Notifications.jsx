import React,{useEffect,useState} from 'react';
import {rpc} from './api';

export function Notifications({institution,refreshKey}){
 const [alerts,setAlerts]=useState([]),[error,setError]=useState('');
 useEffect(()=>{
  let active=true;setAlerts([]);setError('');
  async function load(){try{const result=await rpc('library_notifications',{i:institution});if(active){setAlerts(result);setError('');}}catch{if(active)setError('Notifications could not be refreshed.');}}
  load();const timer=setInterval(load,60000);window.addEventListener('focus',load);
  return()=>{active=false;clearInterval(timer);window.removeEventListener('focus',load);};
 },[institution,refreshKey]);
 return <details className="notification-menu"><summary aria-label={'Notifications: '+alerts.length}>{alerts.length?'● ':''}Notifications ({alerts.length})</summary><section aria-label="Library notifications" className="notification-list"><h2>Notifications</h2><p>For your borrowing account in {institution}. Due-soon reminders start three days before return is due.</p>{error&&<p role="status">{error}</p>}{!error&&!alerts.length&&<p>No current notifications.</p>}{alerts.map(a=><article key={a.id}><strong>{a.title}</strong><p>{a.message}</p></article>)}</section></details>;
}
