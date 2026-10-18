using System.Text.Json.Nodes;
using ApuestaJornada.Core;

var now = new DateTimeOffset(2026,10,17,10,0,0,TimeSpan.Zero);
List<Fixture> Fixtures() => Enumerable.Range(0,10).Select(i => new Fixture(i.ToString(), $"Local {i}", $"Visitante {i}", now.AddHours(3*i).AddMinutes(4))).ToList();
JsonObject Raw() => J.Object(JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "dart_authorization.json"))))!;
Authorization Auth() => Authorization.Parse(Raw());
Bet BetFor(string id="0", int cents=100) => new(id,id,cents,3.2,now);
int checks = 0;
void Check(bool condition, string label) { if (!condition) throw new Exception("FALLO: " + label); checks++; Console.WriteLine("OK " + label); }
void Reject(Action action, string label) { bool rejected=false; try { action(); } catch { rejected=true; } Check(rejected,label); }
async Task RejectAsync(Func<Task> action, string label) { bool rejected=false; try { await action(); } catch { rejected=true; } Check(rejected,label); }

Check(Engine.Decide(Auth(), Fixtures(), [], now) is {Status:"ready",Cents:100,Match.Id:"0"}, "Autorización exportada por Dart: empieza en 1 euro");
Check(Engine.Decide(Auth(), Fixtures(), [], now.AddMinutes(-1)).Status == "stopped", "No ejecuta antes del OK");
Check(Engine.Decide(Auth(), Fixtures(), [], now.AddDays(3)).Status == "stopped", "Caducidad");
var matches=Fixtures(); matches[0]=matches[0] with {HomeGoals=0,AwayGoals=0};
Check(Engine.Decide(Auth(),matches,[BetFor()],now).Status=="waiting", "0-0 en directo no es empate final");
matches[0]=matches[0] with {Finished=true,HomeGoals=1};
Check(Engine.Decide(Auth(),matches,[BetFor()],now.AddHours(3)) is {Status:"ready",Cents:200}, "Duplica solo tras derrota final");
var limited=Auth() with {Budget=100};
Check(Engine.Decide(limited,matches,[BetFor()],now).Status=="stopped", "Presupuesto acumulado");
matches=Fixtures(); matches[4]=matches[4] with {Finished=true,HomeGoals=2,AwayGoals=2};
Check(Engine.Decide(Auth() with {Selected=["0"]},matches,[],now).Status=="stopped", "Empate no apostado detiene");
matches=Fixtures(); matches[0]=matches[0] with {Kickoff=now.AddMinutes(6)};
Check(Engine.Decide(Auth(),matches,[],now).Status=="stopped", "Cambio de calendario");
Check(Engine.Decide(Auth(),Fixtures(),[],now.AddMinutes(5)).Status=="waiting", "Partido iniciado sin final bloquea");
Check(Engine.Decide(Auth() with {Approved=now.AddHours(-4)},Fixtures(),[],now.AddHours(-2)).Status=="waiting", "No adelanta fuera de ventana");
matches=Fixtures().Select(m=>m with {Finished=true,HomeGoals=1,AwayGoals=0}).ToList();
var nine=Enumerable.Range(0,9).Select(i=>BetFor(i.ToString(),100*(1<<i))).ToList();
Check(Engine.Decide(Auth(),matches,nine,now).Status=="stopped", "Tope nueve derrotas");
Check(Engine.Decide(Auth(),matches,[BetFor(),BetFor("0",200)],now).Status=="stopped", "Duplicado bloqueado");
Check(Engine.Decide(Auth(),matches,[BetFor("0",200)],now).Status=="stopped", "Progresión incorrecta bloqueada");
foreach(var field in new[]{"mode","budgetCents","scope","rehearsalOdds"})
{
 var raw=Raw(); raw[field]=field switch {"mode"=>JsonValue.Create("live"),"budgetCents"=>JsonValue.Create(51200),"scope"=>JsonValue.Create("LaLiga/2026-2028/1"),_=>JsonValue.Create(2.7)};
 Reject(()=>Authorization.Parse(raw),"Rechazo campo " + field);
}
var bad=Raw();bad["selectedIds"]=new JsonArray("0","0");Reject(()=>Authorization.Parse(bad),"Elecciones duplicadas");
bad=Raw();bad["selectedIds"]=new JsonArray("otra");Reject(()=>Authorization.Parse(bad),"Elección ajena");
var a=Raw();var rows=(JsonArray)JsonNode.Parse(J.Text(a["schedule"]))!; rows[1]![3]=rows[0]![3]!.DeepClone();a["schedule"]=rows.ToJsonString();Reject(()=>Authorization.Parse(a),"Solapes rechazados");
var firestore=FirebaseClient.DecodeFields(FirebaseClient.EncodeFields(new JsonObject { ["schema"]=1,["yes"]=true,["items"]=new JsonArray(1,2.8,null,"x"),["empty"]=new JsonObject() }));
Check(J.Int(firestore["schema"])==1 && J.Bool(firestore["yes"]) && ((JsonArray)firestore["items"]!).Count==4,"Codificación Firebase y enteros REST");
Check(J.Number(JsonValue.Create(3L))==3,"Cuotas enteras recibidas por REST");
Reject(()=>J.Int(JsonValue.Create("1")),"No convierte texto en entero de esquema");
Reject(()=>J.Time("2026-10-17T10:00:00"),"Fecha sin zona rechazada");
var micro=BetFor() with {ApprovedAt=now.AddTicks(1234567)};
Check(Bet.Parse(micro.ToJson())==micro,"Persistencia conserva precisión temporal");
var events=new JsonArray(Fixtures().Select(m=>(JsonNode)new JsonObject { ["strHomeTeam"]=m.Home,["strAwayTeam"]=m.Away,["strTimestamp"]=J.Iso(m.Kickoff!.Value),["strStatus"]="Not Started",["intHomeScore"]="0",["intAwayScore"]="0" }).ToArray());
Check(!SportsDbResults.Match(Fixtures(),events)[0].Draw,"Proveedor: 0-0 pendiente");
Reject(()=>SportsDbResults.Match(Fixtures(),new JsonArray()),"Proveedor incompleto bloquea");

var midNow = new DateTimeOffset(2026,10,18,15,0,0,TimeSpan.Zero);
JsonObject MidRaw() => J.Object(JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"dart_authorization_midround.json"))));
List<Fixture> MidFixtures() => Enumerable.Range(0,10).Select(i=>new Fixture(i.ToString(),$"Local {i}",$"Visitante {i}",midNow.AddHours((i-2)*3).AddMinutes(4),i<2,i<2?1:null,i==0?1:i==1?0:null)).ToList();
var mid=Authorization.Parse(MidRaw());
Check(mid.FromNow && mid.BaselineFinishedIds.SetEquals(["0","1"]) && mid.PreviousSpentCents==300,"Contrato Dart v2 conserva baseline y gasto");
Check(Engine.Decide(mid,MidFixtures(),[],midNow) is {Status:"ready",Cents:100,Match.Id:"2"},"Inicio a mitad de jornada tras empate previo");
var midUpdated=MidFixtures();midUpdated[3]=midUpdated[3] with {Finished=true,HomeGoals=0,AwayGoals=0};
Check(Engine.Decide(mid,midUpdated,[],midNow).Status=="stopped","Segundo empate no elegido detiene nuevo ensayo");
midUpdated=MidFixtures();midUpdated[2]=midUpdated[2] with {Finished=true,HomeGoals=1,AwayGoals=0};
var midBet=new Bet("2","nuevo",100,3.2,midNow);
Check(Engine.Decide(mid,midUpdated,[midBet],midNow.AddHours(3)) is {Status:"ready",Cents:200},"Solo duplica pérdidas del ensayo nuevo");
Check(Engine.Decide(mid with {PreviousSpentCents=51000},midUpdated,[midBet],midNow.AddHours(3)).Status=="stopped","Gasto previo limita el nuevo ensayo");
midUpdated=MidFixtures();midUpdated[0]=midUpdated[0] with {Finished=false};
Check(Engine.Decide(mid,midUpdated,[],midNow).Status=="stopped","No ignora pérdida de confirmación anterior");
Check(Engine.Decide(mid,MidFixtures(),[new Bet("0","anterior",100,3.2,midNow)],midNow).Status=="stopped","No reaprovecha apuestas del baseline");
foreach(var node in new JsonNode[]{new JsonArray("ajeno"),new JsonArray("0","0"),new JsonArray("2")})
{var invalid=MidRaw();invalid["baselineFinishedIds"]=node;Reject(()=>Authorization.Parse(invalid),"Baseline v2 inválido rechazado");}
foreach(var value in new[]{-1,51100,int.MaxValue})
{var invalid=MidRaw();invalid["previousSpentCents"]=value;Reject(()=>Authorization.Parse(invalid),"Acumulado v2 inválido rechazado");}
var mixed=MidRaw();mixed["mode"]="round-simulation-v1";Reject(()=>Authorization.Parse(mixed),"v1 no admite campos de reinicio");

var temp=Path.Combine(Path.GetTempPath(),"jornada-tests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);
try
{
 var ledger=new Ledger(Path.Combine(temp,"local")); var client=new FakeClient(Raw(), Fixtures());var provider=new FakeProvider();var worker=new BridgeWorker(client,ledger,provider,"pc",()=>now);
 var state=await worker.TickAsync(default);
 Check(((JsonArray)state["bets"]!).Count==1,"Registra primer ensayo");
 await new BridgeWorker(client,new Ledger(Path.Combine(temp,"local")),provider,"pc",()=>now).TickAsync(default);
 Check(((JsonArray)client.State!.Data["bets"]!).Count==1,"Reinicio no duplica");
 var other=new Ledger(Path.Combine(temp,"other"));client.Expire();await new BridgeWorker(client,other,provider,"other-pc",()=>now).TickAsync(default);
 Check(other.Bets(new string('a',32)).Count==1,"Otro PC recupera último historial confirmado");
 await RejectAsync(()=>worker.TickAsync(default),"Lease impide otro PC simultáneo");
 client.Expire(); client.Command.Data["action"]="revoke";client.Command=new(client.Command.Data,"revoked");state=await worker.TickAsync(default);
 Check(J.Text(state["status"])=="revoked" && ((JsonArray)state["bets"]!).Count==1,"Revocación conserva historial");
 client.Command.Data["action"]="authorize";client.Command=new(client.Command.Data,"again");state=await worker.TickAsync(default);
 Check(J.Text(state["status"])=="stopped","Mismo OK no resucita tras revocar");
 client.Command.Data["authorization"]!["budgetCents"]=200;
 await RejectAsync(()=>worker.TickAsync(default),"Mismo identificador no admite cambiar presupuesto");
 var network=new FakeClient(Raw(),Fixtures()){FailState=true};var durable=new Ledger(Path.Combine(temp,"network"));var w=new BridgeWorker(network,durable,provider,"pc",()=>now);
 await RejectAsync(()=>w.TickAsync(default),"Fallo de red tras persistir");network.FailState=false;await w.TickAsync(default);
 Check(durable.Bets(new string('a',32)).Count==1,"Reintento tras red no duplica");
 var revoked=new FakeClient(Raw(),Fixtures()){RevokeOnSecondCommand=true};var l=new Ledger(Path.Combine(temp,"race"));await new BridgeWorker(revoked,l,provider,"pc",()=>now).TickAsync(default);
 Check(l.Bets(new string('a',32)).Count==0,"Revocación durante consulta impide registro");
 var missing=new FakeClient(Raw(),Fixtures());var failLedger=new Ledger(Path.Combine(temp,"feed"));
 await RejectAsync(()=>new BridgeWorker(missing,failLedger,new FakeProvider{Fail=true},"pc",()=>now).TickAsync(default),"Fallo deportivo bloquea");
 Check(J.Text(missing.State!.Data["status"])=="blocked" && failLedger.Bets(new string('a',32)).Count==0,"Bloqueo publicado al móvil");
 var cancelled=new CancellationToken(true);var cancelClient=new FakeClient(Raw(),Fixtures());
 await RejectAsync(()=>new BridgeWorker(cancelClient,new Ledger(Path.Combine(temp,"cancel")),provider,"pc",()=>now).TickAsync(cancelled),"Cancelación no autoriza ensayo");
 var newRound=new FakeClient(Raw(),Fixtures());newRound.Command.Data["requestId"]=new string('b',32);
 state=await new BridgeWorker(newRound,ledger,provider,"pc",()=>now).TickAsync(default);
 Check(Bet.List(state["bets"])[0].Cents==100,"Nuevo OK reinicia en un euro");
 var midClient=new FakeClient(MidRaw(),MidFixtures());
 var midLedger=new Ledger(Path.Combine(temp,"midround"));
 state=await new BridgeWorker(midClient,midLedger,provider,"pc",()=>midNow).TickAsync(default);
 Check(Bet.List(state["bets"])[0].Cents==100,"Trabajador v2 registra primer ensayo tras empate viejo");
 midClient.Command.Data["schema"]=1;midClient.Command=new(midClient.Command.Data,"mismatch");
 await RejectAsync(()=>new BridgeWorker(midClient,midLedger,provider,"pc",()=>midNow).TickAsync(default),"No acepta mezclar esquema y modo");
 var imported=new FakeClient(MidRaw(),MidFixtures());imported.Command.Data["initialBets"]=Ledger.Array([new Bet("0","viejo",100,3.2,midNow)]);
 await RejectAsync(()=>new BridgeWorker(imported,new Ledger(Path.Combine(temp,"imported")),provider,"pc",()=>midNow).TickAsync(default),"Reinicio v2 no importa apuestas de otro ensayo");
 var corrupt=new Ledger(Path.Combine(temp,"corrupt"));corrupt.Initialize(new string('a',32),"hash",[]);File.WriteAllText(Path.Combine(temp,"corrupt",new string('a',32)+".json"),"roto");
 Reject(()=>corrupt.Initialize(new string('a',32),"hash",[]),"Archivo dañado no se reinicia silenciosamente");
}
finally {Directory.Delete(temp,true);}
Console.WriteLine($"{checks} comprobaciones .NET superadas.");

sealed class FakeProvider : IResultsProvider
{
 public bool Fail;
 public Task<List<Fixture>> EnrichAsync(string scope,List<Fixture> fixtures,DateTimeOffset now,CancellationToken ct)
 {ct.ThrowIfCancellationRequested(); if(Fail)throw new IOException("sin proveedor");return Task.FromResult(fixtures);}
}
sealed class FakeClient : IBridgeClient
{
 public string CommandPath=>"command";public string StatePath=>"state";
 public Document Command; public Document? State;public bool FailState, RevokeOnSecondCommand;private int reads,revision;private readonly List<Fixture> fixtures;
 public FakeClient(JsonObject auth,List<Fixture> fixtures)
 {this.fixtures=fixtures;Command=new(new(){["schema"]=J.Text(auth["mode"])=="round-simulation-v2"?2:1,["mode"]="simulation",["requestId"]=new string('a',32),["scope"]=J.Text(auth["scope"]),["authorization"]=auth,["initialBets"]=new JsonArray(),["action"]="authorize"},"v1");}
 public Task<Document?> GetAsync(string path,CancellationToken ct)
 {
  ct.ThrowIfCancellationRequested();
  if(path==CommandPath && ++reads==2 && RevokeOnSecondCommand){Command.Data["action"]="revoke";Command=new(Command.Data,"v2");}
  var d=path==CommandPath?Command:State;return Task.FromResult(d is null?null:new Document((JsonObject)d.Data.DeepClone(),d.Version));
 }
 public Task<string> PatchAsync(string path,JsonObject data,string? expected,bool create,CancellationToken ct)
 {
  ct.ThrowIfCancellationRequested();
  if((create && State is not null)||(!create && State?.Version!=expected))throw new IOException("conflicto de versión");
  if(FailState && data["spentCents"] is not null)throw new IOException("sin red al publicar");
  var version=(++revision).ToString();State=new((JsonObject)data.DeepClone(),version);return Task.FromResult(version);
 }
 public Task<List<Fixture>> FixturesAsync(string scope,CancellationToken ct){ct.ThrowIfCancellationRequested();return Task.FromResult(fixtures);}
 public void Expire(){if(State is not null) State.Data["leaseUntil"]="2000-01-01T00:00:00Z";}
}
