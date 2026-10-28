import React,{useState} from 'react';
import {Sun,Moon} from 'lucide-react';
import './theme.css';
const key='rbmi-theme';
function initialTheme(){try{const saved=localStorage.getItem(key);if(saved==='dark'||saved==='light')return saved;}catch{}return window.matchMedia?.('(prefers-color-scheme: dark)').matches?'dark':'light';}
document.documentElement.dataset.theme=initialTheme();
export function ThemeToggle(){
 const [theme,setTheme]=useState(document.documentElement.dataset.theme);
 function toggle(){const next=theme==='dark'?'light':'dark';document.documentElement.dataset.theme=next;setTheme(next);try{localStorage.setItem(key,next);}catch{}}
 return <button type="button" className="theme-toggle" onClick={toggle} aria-label={'Switch to '+(theme==='dark'?'light':'dark')+' mode'} title={'Current theme: '+theme}>{theme==='dark'?<Sun size={16}/>:<Moon size={16}/>}<span>{theme==='dark'?'Light':'Dark'}</span></button>;
}
