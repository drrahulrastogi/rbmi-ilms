import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseHolidayCSV} from '../src/holiday-import.mjs';
test('holiday template accepts UTF-8 BOM, quoted names, leap dates and trims whitespace',()=>{
 const p=parseHolidayCSV('\uFEFFdate,name\r\n2028-02-29,"Approved closure, campus event"\r\n 2028-03-01 , Special holiday \r\n');
 assert.deepEqual(p.errors,[]);assert.equal(p.rows.length,2);assert.equal(p.rows[1].name,'Special holiday');
});
test('holiday upload rejects invalid dates, duplicate dates, empty names and unexpected headers',()=>{
 for(const text of ['date,name\n2027-02-29,Invalid','date,name\n2028-01-01,A\n2028-01-01,B','date,name\n2028-01-01,','date,name,library\n2028-01-01,A,RBCP','date,name\n01/01/2028,A','date,name\n'])assert.ok(parseHolidayCSV(text).errors.length,text);
});
