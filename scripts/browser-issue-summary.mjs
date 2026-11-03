import {chromium} from '@playwright/test';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const base=process.env.RBMI_TEST_URL||'http://127.0.0.1:4198',out=process.env.RBMI_QA_DIR||'work/issue-summary-qa';
await mkdir(out,{recursive:true});const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));
try{
 await page.goto(base);await page.getByRole('button',{name:'Issue a book',exact:true}).first().waitFor({timeout:120000});
 await page.getByRole('button',{name:'Issue a book',exact:true}).first().click();let dialog=page.getByRole('dialog');
 await dialog.getByLabel('Scan barcode / accession *').fill('NO-SUCH-COPY');await dialog.getByLabel('Patron code *').fill('RBCET-S008');await dialog.getByRole('button',{name:'Issue book',exact:true}).click();
 await dialog.getByText('No matching copy in this library',{exact:true}).waitFor();assert.equal(await page.getByRole('heading',{name:'Book issued successfully',exact:true}).count(),0);checks.push('Rejected issues keep the form and never show a success summary');
 await dialog.getByLabel('Scan barcode / accession *').fill('RBCET-120');await dialog.getByRole('button',{name:'Issue book',exact:true}).click();
 await page.getByRole('heading',{name:'Book issued successfully',exact:true}).waitFor();const summary=page.getByRole('region',{name:'Book issue summary'});
 await summary.getByText('Isha Joshi',{exact:true}).waitFor();assert.equal(await summary.getByText('RBCET-S008',{exact:true}).count(),1);
 const values=await summary.locator('dd').allTextContents();assert.ok(values[2]);assert.ok(values[3]);for(const n of [4,5,6])assert.match(values[n],/^\d{2} [A-Za-z]+ \d{4}$/);
 assert.ok(new Date(values[5])>=new Date(values[4]));assert.ok(new Date(values[6])>new Date(values[5]));checks.push('Successful issue immediately shows borrower, book, accession, issue date, return due date and authoritative fine start');
 await page.screenshot({path:out+'/issue-summary.png',fullPage:true});await page.setViewportSize({width:390,height:844});await page.screenshot({path:out+'/issue-summary-mobile.png',fullPage:true});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth));checks.push('Issue summary fits mobile');
 await summary.getByRole('button',{name:'Done',exact:true}).click();assert.equal(await page.getByRole('dialog').count(),0);checks.push('Done dismisses the summary without issuing another book');assert.deepEqual(errors,[]);
 await writeFile(out+'/results.json',JSON.stringify({checks,errors,displayed:values},null,2));console.log(JSON.stringify({checks,errors,displayed:values}));
}finally{await browser.close();}
