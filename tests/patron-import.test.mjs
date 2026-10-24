import {test} from 'node:test';import assert from 'node:assert/strict';
import {normalizePatronRow} from '../src/patron-import.mjs';
import {strongPassword,withoutPasswords} from '../server/patron-credentials.mjs';
test('legacy CSV password fields are stripped from records and personal password strength is checked',()=>{
 assert.deepEqual(withoutPasswords({code:'X',password:'PrivateTest123!',profile:{department:'CSE',password:'PrivateTest123!'}}),{code:'X',profile:{department:'CSE'}});
 assert.equal(strongPassword('RBCET@RBCET-F100'),false);assert.equal(strongPassword('NewPersonal123!'),true);
});
test('faculty upload accepts Excel uppercase booleans and preserves FALSE correctly',()=>{
 for(const [value,expected] of [['TRUE',true],['true',true],[' True ',true],['FALSE',false],['false',false],[' False ',false],['',true],[undefined,true]]){
  const result=normalizePatronRow({active:value,expires:'2029-12-31'});assert.deepEqual(result.errors,[]);assert.equal(result.row.active,expected);
 }
 assert.ok(normalizePatronRow({active:'yes'}).errors.length);
});
test('faculty expiry rejects locale formats and impossible dates before saving',()=>{
 for(const expires of ['12/31/2029','31/12/2029','2029-02-29','2029-13-01'])assert.ok(normalizePatronRow({expires}).errors.length);
 for(const expires of ['',undefined,'2028-02-29','2029-12-31'])assert.deepEqual(normalizePatronRow({expires}).errors,[]);
});
