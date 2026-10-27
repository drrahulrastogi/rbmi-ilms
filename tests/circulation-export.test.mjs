import {test} from 'node:test';
import assert from 'node:assert/strict';
import {unzipSync,strFromU8} from 'fflate';
import {circulationReport} from '../src/circulation-report.mjs';
import {buildReportXLSX} from '../src/report-xlsx.mjs';
test('circulation export keeps joined names, accession spelling and the selected filters for every row',()=>{
 const rows=Array.from({length:125},(_,n)=>({_accession:n?'ACC-'+n:'0001',_barcode:'BC-'+n,_title:n?'Title '+n:'=HYPERLINK("unsafe")',_patron_name:'नाम & Faculty',_patron_code:'P-'+n,issued:'2026-10-27',due:'2026-11-01',returned:null}));
 const report=circulationReport(rows,'RBCP','RBCP Library',{day:'2026-10-27',dateField:'issued',status:'active',query:'faculty'},'2026-10-27');
 assert.equal(report.rows.length,125);assert.equal(report.rows[0].accession,'0001');assert.equal(report.dateDescription,'issued on 2026-10-27');assert.match(report.filterDescription,/faculty/);
 const files=unzipSync(buildReportXLSX(report));const sheet=strFromU8(files['xl/worksheets/sheet1.xml']);
 assert.equal((sheet.match(/<row /g)||[]).length,126);assert.ok(sheet.includes('0001'));assert.ok(sheet.includes('नाम &amp; Faculty'));assert.ok(!sheet.includes('<f>'));assert.ok(sheet.includes('=HYPERLINK(&quot;unsafe&quot;)'));
 assert.ok(files['[Content_Types].xml']);assert.ok(files['xl/workbook.xml']);assert.ok(sheet.includes('autoFilter'));
});
test('an empty circulation export remains a valid workbook with column headers',()=>{
 const report=circulationReport([],'RBCN','RBCN Library',{day:'',dateField:'returned',status:'all',query:''},'2026-10-27');
 const files=unzipSync(buildReportXLSX(report));assert.equal((strFromU8(files['xl/worksheets/sheet1.xml']).match(/<row /g)||[]).length,1);
});
