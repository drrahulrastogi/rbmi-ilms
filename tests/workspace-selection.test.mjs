import {test} from 'node:test';
import assert from 'node:assert/strict';
import {selectWorkspaceInstitution,createWorkspaceRequestGuard} from '../src/workspace-selection.mjs';

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

test('a delayed previous-library response cannot restore its loan count after switching',async()=>{
 let active={institution:'RBCET',owner:'admin',token:'session'};
 const requests=createWorkspaceRequestGuard(()=>active);
 const central=requests.begin({...active});
 let release;const delayed=new Promise(resolve=>{release=resolve;});
 let count=4;const pending=delayed.then(()=>{if(central())count=4;});
 active={...active,institution:'RBGN'};requests.invalidate();count=null;
 assert.equal(central(),false);assert.equal(count,null);
 const greaterNoida=requests.begin({...active});
 assert.equal(greaterNoida(),true);count=0;
 release();await pending;assert.equal(count,0);
});

test('only the latest request for the current library and session can update the workspace',()=>{
 let active={institution:'RBGN',owner:'admin',token:'session'};
 const requests=createWorkspaceRequestGuard(()=>active);
 const first=requests.begin({...active}),latest=requests.begin({...active});
 assert.equal(first(),false);assert.equal(latest(),true);
 const staleLibrary=requests.begin({...active,institution:'RBCET'});
 assert.equal(staleLibrary(),false);assert.equal(latest(),true);
 active={...active,token:'new-session'};assert.equal(latest(),false);
 const refreshed=requests.begin({...active});active={...active,owner:'other-user'};
 assert.equal(refreshed(),false);
});
