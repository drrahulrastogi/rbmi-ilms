import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const base=process.env.RBMI_TEST_URL||'http://127.0.0.1:4198',out=process.env.RBMI_QA_DIR||'work/full-modules-qa';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));
try{
 await page.goto(base);await page.getByRole('button',{name:'Permissions',exact:true}).waitFor({timeout:120000});await page.getByRole('button',{name:'Permissions',exact:true}).click();
 const row=page.getByRole('row').filter({has:page.getByRole('cell',{name:'accountant',exact:true})});await row.getByRole('button',{name:'Assign / revoke modules'}).click();
 assert.equal(await page.getByRole('checkbox').count(),17);assert.equal(await page.getByRole('checkbox',{checked:true}).count(),1);assert.ok(await page.getByRole('checkbox',{name:'Fines',exact:true}).isChecked());assert.ok(await page.getByRole('checkbox',{name:'Permissions (admin only)',exact:true}).isDisabled());
 await page.getByRole('checkbox',{name:'Catalogue',exact:true}).check();await page.getByRole('checkbox',{name:'Reports',exact:true}).check();await page.getByLabel('Reason for permission change').fill('Browser QA: assigned catalogue and reports');await page.screenshot({path:out+'/all-accountant-modules.png',fullPage:true});
 await page.getByRole('button',{name:'Save permissions',exact:true}).click();await page.getByText(/Permissions saved for/).waitFor();checks.push('Accountant shows every module, with current permissions checked and admin management protected');
 await page.getByLabel('Preview role').selectOption('accountant');await page.locator('nav').getByRole('button',{name:'Catalogue',exact:true}).waitFor();await page.locator('nav').getByRole('button',{name:'Catalogue',exact:true}).click();await page.locator('.book-card').first().waitFor();
 await page.locator('nav').getByRole('button',{name:'Reports',exact:true}).click();await page.getByRole('button',{name:'View Collection register',exact:true}).click();await page.getByRole('heading',{name:'Collection register',exact:true}).last().waitFor();checks.push('Newly assigned accountant modules open and read their data');
 await page.getByLabel('Preview role').selectOption('admin');await page.getByRole('button',{name:'Permissions',exact:true}).click();await row.getByRole('button',{name:'Assign / revoke modules'}).click();await page.getByRole('button',{name:'Restore role defaults'}).click();assert.equal(await page.getByRole('checkbox',{checked:true}).count(),1);await page.getByLabel('Reason for permission change').fill('Browser QA: restore Fines-only default');await page.getByRole('button',{name:'Save permissions',exact:true}).click();await page.getByText(/Permissions saved for/).waitFor();
 await page.getByLabel('Preview role').selectOption('accountant');await page.locator('nav').getByRole('button',{name:'Fines',exact:true}).waitFor();await expect(page.locator('nav').getByRole('button',{name:'Catalogue',exact:true})).toHaveCount(0);await expect(page.locator('nav').getByRole('button',{name:'Reports',exact:true})).toHaveCount(0);checks.push('Restoring defaults revokes extra modules and returns the accountant to Fines only');
 assert.deepEqual(errors,[]);await writeFile(out+'/results.json',JSON.stringify({checks,errors},null,2));console.log(JSON.stringify({checks,errors}));
}finally{await browser.close();}
