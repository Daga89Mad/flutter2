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
 const v2 = {...command, schema:2, requestId:'b'.repeat(32), authorization:{...command.authorization,
   mode:'round-simulation-v2', startMode:'from-now', baselineFinishedIds:['old'],previousSpentCents:0}};
 await ok(setDoc(doc(owner,'PuenteJornada/owner'),v2));
 await no(setDoc(doc(owner,'PuenteJornada/owner'),{...v2,requestId:'c'.repeat(32),schema:1}));
 await no(setDoc(doc(owner,'PuenteJornada/owner'),{...command,requestId:'c'.repeat(32),schema:2}));
 for (const extra of [{previousSpentCents:-1},{previousSpentCents:51100},{previousSpentCents:100},{baselineFinishedIds:['old','old']},{startMode:'auto-restart'}]) {
   await no(setDoc(doc(owner,'PuenteJornada/owner'),{...v2,requestId:'c'.repeat(32),authorization:{...v2.authorization,...extra}}));
 }
 await no(setDoc(doc(owner,'PuenteJornada/owner'),{...v2,requestId:'c'.repeat(32),initialBets:[{mode:'simulation',cents:100}]}));
 await ok(setDoc(doc(owner,'PuenteJornada/owner'),command));
 const live = {schema:1,mode:'live-pilot',currency:'EUR',requestId:'d'.repeat(32),action:'authorize',scope:command.scope,
   matchId:'one',home:'A',away:'B',kickoff:Timestamp.fromMillis(Date.now()+3600000),approvedAt:serverTimestamp(),
   expiresAt:Timestamp.fromMillis(Date.now()+3540000),updatedAt:serverTimestamp(),stakeCents:100,budgetCents:100,minPrice:2.8,maxPrice:20,
   betType:'BACK',selectionId:'58805',marketId:'1.263700796',eventId:'36180903',marketConfirmed:true,schedule:'[]',fromNow:false,baselineFinishedIds:[]};
 // Derivar ambos timestamps del mismo instante: la igualdad debe ser exacta.
 live.expiresAt=Timestamp.fromMillis(live.kickoff.toMillis()-60000);
 const realRef=doc(owner,'PuenteJornadaReal/owner');
 await no(setDoc(doc(other,'PuenteJornadaReal/other'),live));
 await no(setDoc(doc(anon,'PuenteJornadaReal/owner'),live));
 for(const extra of [{mode:'simulation'},{stakeCents:200},{budgetCents:200},{betType:'LAY'},{marketConfirmed:false},{marketId:'1.bad'},{baselineFinishedIds:['one']}]) await no(setDoc(realRef,{...live,...extra}));
 await ok(setDoc(realRef,live));
 await ok(getDoc(realRef));
 await no(getDoc(doc(other,'PuenteJornadaReal/owner')));
 await no(getDocs(collection(owner,'PuenteJornadaReal')));
 await no(updateDoc(realRef,{requestId:'e'.repeat(32),updatedAt:serverTimestamp()}));
 await no(updateDoc(realRef,{stakeCents:200,updatedAt:serverTimestamp()}));
 await no(deleteDoc(realRef));
 await no(setDoc(doc(owner,'PuenteJornadaReal/owner/Unexpected/doc'),{}));
 const realStateRef=doc(owner,'PuenteJornadaReal/owner/Estado/actual');
 const realState={mode:'live-pilot',agentId:'pc',lastSeenAt:Timestamp.now(),leaseUntil:Timestamp.now(),requestId:live.requestId,dispatchReserved:false,status:'waiting',message:'waiting'};
 await ok(setDoc(realStateRef,realState));
 await no(setDoc(realStateRef,{...realState,mode:'simulation'}));
 await ok(updateDoc(realStateRef,{dispatchReserved:true}));
 await no(updateDoc(realStateRef,{dispatchReserved:false}));
 await no(deleteDoc(realStateRef));
 await no(getDoc(doc(other,'PuenteJornadaReal/owner/Estado/actual')));
 await ok(updateDoc(realRef,{action:'revoke',updatedAt:serverTimestamp()}));
 await no(updateDoc(realRef,{action:'authorize',updatedAt:serverTimestamp()}));
 // Ronda REAL aislada: autorización inmutable y reservas monótonas.
 const roundRef=doc(owner,'PuenteJornadaRondaReal/owner');
 const round={schema:1,mode:'live-round-15',requestId:'f'.repeat(32),action:'authorize',scope:'LaLiga/2026-2027/1',
   approvedAt:serverTimestamp(),updatedAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+86400000),
   currency:'EUR',budgetCents:1500,maxBets:4,minPrice:2.8,maxPrice:20,excludeBigThree:true,marketConfirmed:true,fromNow:true,
   schedule:'[]',legs:'[]',baselineFinishedIds:[]};
 await no(setDoc(doc(other,'PuenteJornadaRondaReal/other'),round));
 await no(setDoc(doc(anon,'PuenteJornadaRondaReal/owner'),round));
 for(const extra of [{mode:'simulation'},{budgetCents:1600},{maxBets:5},{excludeBigThree:false},{currency:'GBP'},{marketConfirmed:false}]) await no(setDoc(roundRef,{...round,...extra}));
 await ok(setDoc(roundRef,round));
 await no(getDoc(doc(other,'PuenteJornadaRondaReal/owner')));
 await no(getDocs(collection(owner,'PuenteJornadaRondaReal')));
 await no(setDoc(doc(owner,'PuenteJornadaRondaReal/owner/Unexpected/doc'),{}));
 await no(updateDoc(roundRef,{budgetCents:3100,updatedAt:serverTimestamp()}));
 await no(deleteDoc(roundRef));
 const roundState=doc(owner,'PuenteJornadaRondaReal/owner/Estado/actual');
 const rs={mode:'live-round-15',requestId:round.requestId,fingerprint:'hash',reservedCount:0,orders:[],terminal:false,
   agentId:'pc',lastSeenAt:Timestamp.now(),leaseUntil:Timestamp.now(),status:'waiting',message:'checking'};
 await no(setDoc(roundState,{...rs,reservedCount:1,orders:[{}]}));
 await ok(setDoc(roundState,rs));
 await no(updateDoc(roundState,{reservedCount:2,orders:[{},{}]}));
 await ok(updateDoc(roundState,{reservedCount:1,orders:[{cents:100}]}));
 await no(updateDoc(roundState,{reservedCount:0,orders:[]}));
 await no(updateDoc(roundState,{fingerprint:'other'}));
 await no(updateDoc(roundState,{requestId:'a'.repeat(32)}));
 await no(updateDoc(roundState,{spentCents:1600}));
 await no(deleteDoc(roundState));
 await no(getDoc(doc(other,'PuenteJornadaRondaReal/owner/Estado/actual')));
 await ok(updateDoc(roundState,{terminal:true}));
 await no(updateDoc(roundState,{terminal:false}));
 await no(updateDoc(roundState,{reservedCount:2,orders:[{},{}]}));
 await ok(updateDoc(roundRef,{action:'revoke',updatedAt:serverTimestamp()}));
 await no(updateDoc(roundRef,{action:'authorize',updatedAt:serverTimestamp()}));
 // Ronda REAL aislada: autorización inmutable y reservas monótonas.
 const round128Ref=doc(owner,'PuenteJornadaRonda128Real/owner');
 const round128={schema:1,mode:'live-round-128-v1',requestId:'f'.repeat(32),action:'authorize',scope:'LaLiga/2026-2027/1',
   approvedAt:serverTimestamp(),updatedAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+86400000),
   currency:'EUR',budgetCents:25500,maxStakeCents:12800,maxBets:8,minPrice:2.8,maxPrice:20,excludeBigThree:true,marketConfirmed:true,fromNow:true,
   schedule:'[]',legs:'[]',baselineFinishedIds:[]};
 await no(setDoc(doc(other,'PuenteJornadaRonda128Real/other'),round128));
 await no(setDoc(doc(anon,'PuenteJornadaRonda128Real/owner'),round128));
 for(const extra of [{mode:'simulation'},{budgetCents:25600},{maxBets:9},{maxStakeCents:12900},{mode:'live-round-15'},{excludeBigThree:false},{currency:'GBP'},{marketConfirmed:false}]) await no(setDoc(round128Ref,{...round128,...extra}));
 const missingMax={...round128}; delete missingMax.maxStakeCents; await no(setDoc(round128Ref,missingMax));
 await ok(setDoc(round128Ref,round128));
 await no(getDoc(doc(other,'PuenteJornadaRonda128Real/owner')));
 await no(getDocs(collection(owner,'PuenteJornadaRonda128Real')));
 await no(setDoc(doc(owner,'PuenteJornadaRonda128Real/owner/Unexpected/doc'),{}));
 await no(updateDoc(round128Ref,{budgetCents:3100,updatedAt:serverTimestamp()}));
 await no(deleteDoc(round128Ref));
 const round128State=doc(owner,'PuenteJornadaRonda128Real/owner/Estado/actual');
 const rs128={mode:'live-round-128-v1',requestId:round128.requestId,fingerprint:'hash',reservedCount:0,orders:[],terminal:false,
   agentId:'pc',lastSeenAt:Timestamp.now(),leaseUntil:Timestamp.now(),status:'waiting',message:'checking'};
 await no(setDoc(round128State,{...rs128,reservedCount:1,orders:[{}]}));
 await ok(setDoc(round128State,rs128));
 await no(updateDoc(round128State,{reservedCount:2,orders:[{},{}]}));
 await ok(updateDoc(round128State,{reservedCount:1,orders:[{cents:100}]}));
 await no(updateDoc(round128State,{reservedCount:0,orders:[]}));
 await no(updateDoc(round128State,{fingerprint:'other'}));
 await no(updateDoc(round128State,{requestId:'a'.repeat(32)}));
 await no(updateDoc(round128State,{spentCents:25600}));
 await no(deleteDoc(round128State));
 await no(getDoc(doc(other,'PuenteJornadaRonda128Real/owner/Estado/actual')));
 await ok(updateDoc(round128State,{terminal:true}));
 await no(updateDoc(round128State,{terminal:false}));
 await no(updateDoc(round128State,{reservedCount:2,orders:[{},{}]}));
 await ok(updateDoc(round128Ref,{action:'revoke',updatedAt:serverTimestamp()}));
 await no(updateDoc(round128Ref,{action:'authorize',updatedAt:serverTimestamp()}));
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
