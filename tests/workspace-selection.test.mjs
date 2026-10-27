import {test} from 'node:test';
import assert from 'node:assert/strict';
import {selectWorkspaceInstitution} from '../src/workspace-selection.mjs';

const sheeba=[
 {institution_id:'RBCET',role:'patron'},
 {institution_id:'RBCN',role:'librarian'},
 {institution_id:'RBCP',role:'patron'},
 {institution_id:'RBGN',role:'patron'}
];

test('a librarian with cross-library borrowing opens her staff library on sign-in',()=>{
 assert.equal(selectWorkspaceInstitution(sheeba),'RBCN');
 for(const home of ['RBCET','RBCN','RBCP','RBGN']){
  const memberships=sheeba.map(m=>({...m,role:m.institution_id===home?'librarian':'patron'}));
  assert.equal(selectWorkspaceInstitution(memberships),home);
 }
 assert.equal(sheeba[0].role,'patron');
});

test('a current-session selection is retained when memberships reload',()=>{
 assert.equal(selectWorkspaceInstitution(sheeba,'RBCET'),'RBCET');
 assert.equal(selectWorkspaceInstitution(sheeba,'RBGN'),'RBGN');
});

test('a removed selection falls back to the current staff assignment',()=>{
 assert.equal(selectWorkspaceInstitution(sheeba,'REMOVED'),'RBCN');
});

test('borrower-only accounts keep their available library without gaining staff roles',()=>{
 const memberships=sheeba.map(m=>({...m,role:'patron'}));
 assert.equal(selectWorkspaceInstitution(memberships),'RBCET');
 assert.equal(selectWorkspaceInstitution(memberships,'RBCP'),'RBCP');
 assert.equal(selectWorkspaceInstitution([]),'');
});
