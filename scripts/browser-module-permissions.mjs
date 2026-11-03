import {chromium} from '@playwright/test';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const base=process.env.RBMI_TEST_URL||'http://127.0.0.1:4198',out=process.env.RBMI_QA_DIR||'work/module-permission-qa';
await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));
try{
 await page.goto(base);await page.getByRole('button',{name:'Permissions',exact:true}).waitFor({timeout:120000});
 await page.getByRole('button',{name:'Permissions',exact:true}).click();await page.getByRole('heading',{name:'User module permissions'}).waitFor();
 const librarian=page.getByRole('row').filter({has:page.getByRole('cell',{name:'librarian',exact:true})});
 await librarian.getByRole('button',{name:'Assign / revoke modules'}).click();
 await page.getByRole('button',{name:'Revoke all modules'}).click();await page.getByRole('checkbox',{name:'Catalogue',exact:true}).check();await page.getByLabel('Reason for permission change').fill('Synthetic browser test: catalogue only');
 await page.screenshot({path:out+'/admin-permissions.png',fullPage:true});
 await page.getByRole('button',{name:'Save permissions',exact:true}).click();await page.getByText(/Permissions saved for/).waitFor();checks.push('Admin can save module checkboxes with a required reason');
 await page.getByLabel('Preview role').selectOption('librarian');await page.getByRole('button',{name:'Catalogue',exact:true}).waitFor();await page.getByRole('heading',{name:'Catalogue',exact:true}).waitFor();
 for(const name of ['Permissions','Circulation','Settings','Fines','Book edits'])assert.equal(await page.locator('nav').getByRole('button',{name,exact:true}).count(),0,name);
 await page.getByRole('button',{name:'View copies',exact:false}).first().click();assert.equal(await page.getByRole('button',{name:'Request edit',exact:true}).count(),0);await page.keyboard.press('Escape');
 checks.push('Librarian sees only assigned navigation and no revoked edit-request button');await page.screenshot({path:out+'/librarian-catalogue-only.png',fullPage:true});
 await page.getByLabel('Preview role').selectOption('admin');await page.getByRole('button',{name:'Permissions',exact:true}).click();await librarian.getByRole('button',{name:'Assign / revoke modules'}).click();
 await page.getByRole('button',{name:'Restore role defaults'}).click();await page.getByLabel('Reason for permission change').fill('Synthetic browser test: restore defaults');await page.getByRole('button',{name:'Save permissions',exact:true}).click();await page.getByText(/Permissions saved for/).waitFor();checks.push('Administrator retains access and can restore defaults');
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:out+'/permissions-mobile.png',fullPage:true});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth));checks.push('Permissions view fits a mobile screen');
 assert.deepEqual(errors,[]);await writeFile(out+'/results.json',JSON.stringify({checks,errors},null,2));console.log(JSON.stringify({checks,errors}));
}finally{await browser.close();}
