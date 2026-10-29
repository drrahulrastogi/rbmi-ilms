import {test} from 'node:test';
import assert from 'node:assert/strict';
import {normalizeHolidayDate,parseHolidayCSV} from '../src/holiday-import.mjs';
test('holiday template accepts UTF-8 BOM, quoted names, leap dates and trims whitespace',()=>{
 const p=parseHolidayCSV('\uFEFFdate,name\r\n2028-02-29,"Approved closure, campus event"\r\n 2028-03-01 , Special holiday \r\n');
 assert.deepEqual(p.errors,[]);assert.equal(p.rows.length,2);assert.equal(p.rows[1].name,'Special holiday');
});
test('holiday upload rejects invalid dates, duplicate dates, empty names and unexpected headers',()=>{
 for(const text of ['date,name\n2027-02-29,Invalid','date,name\n2028-01-01,A\n2028-01-01,B','date,name\n2028-01-01,','date,name,library\n2028-01-01,A,RBCP','date,name\n01/01/28,A','date,name\n'])assert.ok(parseHolidayCSV(text).errors.length,text);
});

test('Excel dates normalize day first, including leap days, without locale-dependent parsing',()=>{
 for(const date of ['2027-01-26','2027/1/26','26/01/2027','26-1-2027','26.01.2027'])assert.equal(normalizeHolidayDate(date),'2027-01-26');
 assert.equal(normalizeHolidayDate('05/06/2027'),'2027-06-05');
 assert.equal(normalizeHolidayDate('29/02/2028'),'2028-02-29');
 for(const date of ['29/02/2027','31/04/2027','2027-13-01','YYYY-MM-DD','26/01/27','2027','1899-12-31','2101-01-01','1900-02-29'])assert.equal(normalizeHolidayDate(date),null,date);
});

test('duplicate holidays in different date formats are rejected after normalization',()=>{
 const result=parseHolidayCSV('date,name\n2027-01-26,Republic Day\n26/01/2027,Duplicate');
 assert.deepEqual(result.rows.map(r=>r.day),['2027-01-26','2027-01-26']);
 assert.ok(result.errors.some(e=>e.includes('duplicate date 2027-01-26')));
});

test('tab-separated text uploads accept Excel dates and invalid-date errors identify the entered value',()=>{
 const result=parseHolidayCSV('date\tname\r\n26/01/2027\tRepublic Day\r\n15/08/2027\tIndependence Day');
 assert.deepEqual(result.errors,[]);assert.equal(result.rows[0].day,'2027-01-26');
 const invalid=parseHolidayCSV('date,name\nYYYY-MM-DD,Holiday');
 assert.ok(invalid.errors.some(e=>e.includes('Row 2')&&e.includes('"YYYY-MM-DD"')));
});
