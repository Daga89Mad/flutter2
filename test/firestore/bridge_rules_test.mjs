import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, serverTimestamp, Timestamp, writeBatch, deleteDoc, collection, getDocs } from 'firebase/firestore';
import { readFileSync } from 'node:fs';
const env = await initializeTestEnvironment({projectId:'demo-jornada', firestore:{host:'127.0.0.1',port:8089,rules:readFileSync(new URL('../../firestore.rules', import.meta.url),'utf8')}});
const owner = env.authenticatedContext('owner').firestore();
const other = env.authenticatedContext('other').firestore();
const anon = env.unauthenticatedContext().firestore();
const command = {schema:1, mode:'simulation', requestId:'a'.repeat(32), action:'authorize', scope:'LaLiga/2026-2027/1',
  authorization:{mode:'round-simulation-v1',scope:'LaLiga/2026-2027/1',schedule:'[]',selectedIds:['one'], budgetCents:100,rehearsalOdds:3.2,approvedAt:'2026-10-17T10:00:00Z',expiresAt:'2026-10-18T10:00:00Z'}, initialBets:[],updatedAt:serverTimestamp()};
let checks=0;
async function ok(p){await assertSucceeds(p);checks++;}
async function no(p){await assertFails(p);checks++;}
try {
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async context => {
   await setDoc(doc(context.firestore(),'AccesoApuestaJornada/owner'), {activo:true});
 });
 const firstUid = 'DBbLkTOEvqMTUP4zMAn7ap8iLFZ2';
 const first = env.authenticatedContext(firstUid).firestore();
 await no(setDoc(doc(other,'AccesoApuestaJornada/other'), {activo:true}));
 await no(setDoc(doc(other,`AccesoApuestaJornada/${firstUid}`), {activo:true}));
 await no(setDoc(doc(first,`AccesoApuestaJornada/${firstUid}`), {activo:true}));
 await no(setDoc(doc(first,'AccesoApuestaJornada/_inicializacion'), {uidInicial:firstUid}));
 const batch = writeBatch(first);
 batch.set(doc(first,`AccesoApuestaJornada/${firstUid}`), {activo:true});
 batch.set(doc(first,'AccesoApuestaJornada/_inicializacion'), {uidInicial:firstUid});
 await ok(batch.commit());
 await ok(getDoc(doc(first,`AccesoApuestaJornada/${firstUid}`)));
 await no(getDoc(doc(other,`AccesoApuestaJornada/${firstUid}`)));
 await no(getDocs(collection(first,'AccesoApuestaJornada')));
 await no(updateDoc(doc(first,`AccesoApuestaJornada/${firstUid}`), {activo:false}));
 await no(deleteDoc(doc(first,'AccesoApuestaJornada/_inicializacion')));
 await no(setDoc(doc(other,'PuenteJornada/other'),command));
 await ok(setDoc(doc(owner,'PuenteJornada/owner'),command));
 await ok(getDoc(doc(owner,'PuenteJornada/owner')));
 await no(getDoc(doc(other,'PuenteJornada/owner')));
 await no(getDoc(doc(anon,'PuenteJornada/owner')));
 await no(setDoc(doc(other,'PuenteJornada/owner'),command));
 await no(setDoc(doc(anon,'PuenteJornada/stranger'),command));
 await no(updateDoc(doc(owner,'PuenteJornada/owner'),{mode:'live',updatedAt:serverTimestamp()}));
 await no(updateDoc(doc(owner,'PuenteJornada/owner'),{'authorization.budgetCents':100000,updatedAt:serverTimestamp()}));
 await no(updateDoc(doc(owner,'PuenteJornada/owner'),{'authorization.budgetCents':200,updatedAt:serverTimestamp()}));
 await ok(updateDoc(doc(owner,'PuenteJornada/owner'),{action:'revoke',updatedAt:serverTimestamp()}));
 const state = {mode:'simulation',agentId:'pc',lastSeenAt:Timestamp.now(),leaseUntil:Timestamp.now()};
 await ok(setDoc(doc(owner,'PuenteJornada/owner/Estado/actual'),state));
 await ok(setDoc(doc(owner,'PuenteJornada/owner/Estado/actual'),{...state,requestId:command.requestId,scope:command.scope,status:'waiting',message:'Ensayo',bets:[],results:{},spentCents:0}));
 await no(getDoc(doc(other,'PuenteJornada/owner/Estado/actual')));
 await no(setDoc(doc(other,'PuenteJornada/owner/Estado/actual'),state));
 await no(setDoc(doc(owner,'PuenteJornada/owner/Estado/actual'),{...state,mode:'live'}));
 await no(setDoc(doc(owner,'PuenteJornada/owner/Unexpected/doc'),state));
 await ok(setDoc(doc(owner,'LaLiga/Resultados/Jornadas/1/Partidos/one'),{Local:'A',Visitante:'B'}));
 await ok(getDoc(doc(other,'LaLiga/Resultados/Jornadas/1/Partidos/one')));
 await env.withSecurityRulesDisabled(async context => {
   await updateDoc(doc(context.firestore(),'AccesoApuestaJornada/owner'), {activo:false});
   await deleteDoc(doc(context.firestore(),`AccesoApuestaJornada/${firstUid}`));
 });
 await no(getDoc(doc(owner,'PuenteJornada/owner')));
 await no(setDoc(doc(owner,'PuenteJornada/owner'),{...command,requestId:'b'.repeat(32)}));
 await no(setDoc(doc(owner,'PuenteJornada/owner/Estado/actual'),state));
 await ok(updateDoc(doc(owner,'PuenteJornada/owner'),{action:'revoke',updatedAt:serverTimestamp()}));
 const retry = writeBatch(first);
 retry.set(doc(first,`AccesoApuestaJornada/${firstUid}`),{activo:true});
 retry.set(doc(first,'AccesoApuestaJornada/_inicializacion'),{uidInicial:firstUid});
 await no(retry.commit());
 await no(getDoc(doc(anon,'AccesoApuestaJornada/owner')));
 console.log(`${checks} comprobaciones de reglas superadas.`);
} finally {await env.cleanup();}
