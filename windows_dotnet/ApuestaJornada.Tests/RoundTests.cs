using System.IO.Compression;
using System.Text.Json.Nodes;
using System.Xml.Linq;
using ApuestaJornada.Core;

static class RoundTests
{
    public static async Task<int> Run()
    {
        var checks = 0;
        void Check(bool ok, string label) { if (!ok) throw new Exception("FALLO RONDA: " + label); checks++; Console.WriteLine("OK RONDA " + label); }
        void Reject(Action a, string label) { var rejected = false; try { a(); } catch { rejected = true; } Check(rejected, label); }
        async Task RejectAsync(Func<Task> a, string label) { var rejected = false; try { await a(); } catch { rejected = true; } Check(rejected, label); }
        var root = Path.Combine(Path.GetTempPath(), "round128-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "live_strategy_reviewed.xml"))
            .Replace("<Name>Empates por jornada</Name>", "<Name>Empates jornada max128 EUR</Name>")
            .Replace("<MaxBetLiability>1</MaxBetLiability>", "<MaxBetLiability>128</MaxBetLiability>")
            .Replace("<ProvidersCSV>EmpatesJornada</ProvidersCSV>", "<ProvidersCSV>EmpatesJornadaRonda128</ProvidersCSV>")
            .Replace("<IgnoreTipStake>true</IgnoreTipStake>", "<IgnoreTipStake>false</IgnoreTipStake>");
        var strategy = Path.Combine(root, "round.gz"); WriteGzip(strategy, xml);
        LiveStrategyValidator.Validate(strategy, true); Check(true, "estrategia CSV variable y responsabilidad máxima 128 EUR");
        Reject(() => LiveStrategyValidator.Validate(strategy), "no confunde estrategia de ronda con piloto");
        var start = new DateTimeOffset(2027, 1, 10, 10, 0, 0, TimeSpan.Zero);
        List<Fixture> Fixtures() => Enumerable.Range(0, 10).Select(i => new Fixture(i.ToString(), "Local " + i, "Visitante " + i,
            start.AddHours(i * 3).AddMinutes(4))).ToList();
        JsonObject Raw(List<Fixture>? fs = null)
        {
            fs ??= Fixtures();
            return new JsonObject
            {
                ["schema"] = 1, ["mode"] = "live-round-128-v1", ["requestId"] = new string('c', 32), ["action"] = "authorize",
                ["scope"] = "LaLiga/2026-2027/20", ["approvedAt"] = J.Iso(start), ["expiresAt"] = J.Iso(fs[7].Kickoff!.Value.AddSeconds(-60)),
                ["currency"] = "EUR", ["budgetCents"] = 25500, ["maxBets"] = 8, ["maxStakeCents"] = 12800, ["minPrice"] = 2.8, ["maxPrice"] = 20,
                ["excludeBigThree"] = true, ["marketConfirmed"] = true, ["fromNow"] = true, ["baselineFinishedIds"] = new JsonArray(),
                ["schedule"] = new JsonArray(fs.OrderBy(f => f.Id, StringComparer.Ordinal).Select(f => (JsonNode)new JsonArray(f.Id, f.Home, f.Away, J.Iso(f.Kickoff!.Value), false)).ToArray()).ToJsonString(),
                ["legs"] = new JsonArray(fs.Take(8).Select((f, i) => (JsonNode)new JsonArray(f.Id, f.Home, f.Away,
                    J.Iso(f.Kickoff!.Value), "1.30000000" + i, "4000000" + i)).ToArray()).ToJsonString()
            };
        }
        var parsed = LiveRoundCommand.Parse(Raw()); Check(parsed.Legs.Count == 8, "contrato completo de ocho partidos");
        foreach (var field in new[] { "budgetCents", "maxBets", "maxStakeCents" })
        { var bad = Raw(); bad[field] = 9999; Reject(() => LiveRoundCommand.Parse(bad), "rechaza ampliar " + field); }
        var oldOk = Raw(); oldOk["mode"] = "live-round-15"; oldOk["budgetCents"] = 1500; oldOk["maxBets"] = 4; oldOk.Remove("maxStakeCents");
        Reject(() => LiveRoundCommand.Parse(oldOk), "el OK antiguo de 15 EUR no autoriza ampliar el riesgo");
        Reject(() => LiveRoundCommand.Csv(parsed.Legs[0], 25600), "rechaza CSV de 256 EUR por superar el máximo de 128");
        Reject(() => LiveRoundCommand.Csv(parsed.Legs[0], 12900), "rechaza importe ajeno a la progresión");
        Check(LiveRoundCommand.Csv(parsed.Legs[7], 12800).Contains("\"128.00\""), "CSV admite exactamente el último escalón de 128 EUR");
        WriteGzip(strategy, xml.Replace("<MaxBetLiability>128</MaxBetLiability>", "<MaxBetLiability>129</MaxBetLiability>"));
        Reject(() => LiveStrategyValidator.Validate(strategy, true), "estrategia con máximo 129 EUR rechazada"); WriteGzip(strategy, xml);
        foreach (var name in new[] { "Real Madrid CF", "FC Barcelona", "Atlético de Madrid", "Club Atlético de Madrid" })
        {
            Check(ExcludedTeams.IsExcluded(name), "normaliza exclusión " + name);
            var fs = Fixtures(); fs[0] = fs[0] with { Away = name }; Reject(() => LiveRoundCommand.Parse(Raw(fs)), "rechaza partido " + name);
        }
        var overlap = Fixtures(); overlap[1] = overlap[1] with { Kickoff = overlap[0].Kickoff }; Reject(() => LiveRoundCommand.Parse(Raw(overlap)), "rechaza simultáneos sin elección");
        var duplicate = Raw(); var legs = JsonNode.Parse(J.Text(duplicate["legs"]))!.AsArray(); legs[1]![4] = legs[0]![4]!.DeepClone(); duplicate["legs"] = legs.ToJsonString();
        Reject(() => LiveRoundCommand.Parse(duplicate), "rechaza mercado duplicado");
        var history = Path.Combine(root, "history.gz"); WriteGzip(history, "<ArrayOfBetHistoryItem/>");
        Check(BfHistory.Read(history).Count == 0, "lee historial vacío sin inventar apuestas");
        WriteGzip(history, "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><ArrayOfBetHistoryItem>&e;</ArrayOfBetHistoryItem>");
        Reject(() => BfHistory.Read(history), "rechaza DTD y entidades externas");
        var manual = HistoryBet(0, 1m, start, start.AddHours(2), -1m);
        manual.Element("Tipster")!.Remove();
        manual.Element("StrategyID")!.Value = "Manual bets";
        manual.Element("StrategyName")!.Value = "Manual bets";
        manual.Element("SimulatedBet")!.Value = "true";
        WriteGzip(history, new XElement("ArrayOfBetHistoryItem", manual).ToString());
        var manualRead = BfHistory.Read(history).Single();
        Check(manualRead.Simulated && manualRead.Tipster == "" && manualRead.StrategyName == "Manual bets",
            "apuesta manual simulada sin Tipster se lee sin atribuir proveedor");
        manual.Element("SimulatedBet")!.Value = "false";
        WriteGzip(history, new XElement("ArrayOfBetHistoryItem", manual).ToString());
        Check(BfHistory.Read(history).Single().Tipster != LiveRoundCommand.Provider,
            "apuesta manual real sin Tipster no adopta proveedor de la ronda");
        manual.Add(new XElement("Tipster", "uno"), new XElement("Tipster", "dos"));
        WriteGzip(history, new XElement("ArrayOfBetHistoryItem", manual).ToString());
        Reject(() => BfHistory.Read(history), "Tipster duplicado sigue rechazado");
        manual.Elements("Tipster").Remove(); manual.Element("BetId")!.Remove();
        WriteGzip(history, new XElement("ArrayOfBetHistoryItem", manual).ToString());
        Reject(() => BfHistory.Read(history), "identificadores obligatorios siguen rechazados");
        var bets = new List<XElement>();
        void History() => WriteGzip(history, new XElement("ArrayOfBetHistoryItem", bets).ToString());
        History();
        var time = start;
        LiveRoundWorker Worker(RoundClient client, string name, bool readOnly = false, string agent = "pc") =>
            new(client, new RoundProvider(), agent, Path.Combine(root, name), strategy, history, readOnly, clock: () => time);
        var ro = new RoundClient(Raw(), Fixtures()); var readWorker = Worker(ro, "read", true);
        Check(J.Text((await readWorker.TickAsync(default))["status"]) == "read_only" && !File.Exists(readWorker.OutboxPath), "modo sólo lectura nunca crea CSV");
        var client = new RoundClient(Raw(), Fixtures()); var worker = Worker(client, "full");
        for (var i = 0; i < 8; i++)
        {
            time = start.AddHours(i * 3);
            var state = await worker.TickAsync(default);
            Check(J.Text(state["status"]) == "exported" && J.Int(state["reservedCount"]) == i + 1, "reserva y publica escalón " + (1 << i));
            Check(File.ReadAllText(worker.OutboxPath).Contains($"\"{(1 << i)}.00\""), "CSV contiene importe correcto " + (1 << i));
            var content = File.ReadAllText(worker.OutboxPath); File.Delete(worker.OutboxPath);
            Check(J.Text((await Worker(client, "full").TickAsync(default))["status"]) == "awaiting_history" && !File.Exists(worker.OutboxPath), "reinicio y borrado CSV no repiten escalón " + i);
            File.WriteAllText(worker.OutboxPath, content);
            var placed = time; time = time.AddMinutes(124);
            bets.Add(HistoryBet(i, 1 << i, placed, time, -(1 << i)));
            client.Fixtures[i] = client.Fixtures[i] with { Finished = true, HomeGoals = 1, AwayGoals = 0 };
            History();
            Check(J.Text((await worker.TickAsync(default))["status"]) == "confirming", "espera segunda lectura de liquidación " + i);
            time = time.AddSeconds(16);
            var settled = await worker.TickAsync(default);
            Check(J.Text(settled["status"]) == (i == 7 ? "completed" : "waiting"), "sólo continúa tras liquidación estable " + i);
        }
        Check(J.Int(client.State!.Data["spentCents"]) == 25500 && J.Bool(client.State.Data["terminal"]), "límite acumulado 255 EUR y terminal tras ocho pérdidas");
        Check(J.Int((await worker.TickAsync(default))["reservedCount"]) == 8, "no existe novena apuesta ni reinicio el lunes");
        bets.Clear(); History(); time = start;
        var winning = new RoundClient(Raw(), Fixtures()); var winWorker = Worker(winning, "win"); await winWorker.TickAsync(default);
        time = start.AddHours(2); bets.Add(HistoryBet(0, 1, start, time, 3)); History();
        Check(J.Text((await winWorker.TickAsync(default))["status"]) == "won", "ganancia liquidada detiene la ronda");
        time = start.AddHours(3); Check(J.Int((await winWorker.TickAsync(default))["reservedCount"]) == 1, "empate ganador impide segunda apuesta");
        bets.Clear(); History(); time = start;
        var partial = new RoundClient(Raw(), Fixtures()); var pw = Worker(partial, "partial"); await pw.TickAsync(default);
        bets.Add(HistoryBet(0, 0.5m, start, start.AddHours(2), -0.5m)); History(); time = start.AddHours(2);
        Check(J.Text((await pw.TickAsync(default))["status"]) == "review" && J.Int(partial.State!.Data["reservedCount"]) == 1, "correspondencia parcial bloquea progresión");
        bets.Clear(); History(); time = start;
        var duplicateClient = new RoundClient(Raw(), Fixtures()); var dw = Worker(duplicateClient, "duplicate"); await dw.TickAsync(default);
        bets.Add(HistoryBet(0, 1, start, start.AddHours(2), -1)); var second = HistoryBet(0, 1, start, start.AddHours(2), -1); second.Element("BetId")!.Value = "another"; bets.Add(second); History(); time = start.AddHours(2);
        Check(J.Text((await dw.TickAsync(default))["status"]) == "review", "dos BetId coincidentes requieren revisión");
        bets.Clear(); History(); time = start;
        var loss = new RoundClient(Raw(), Fixtures()) { LoseExportAck = true }; var lost = Worker(loss, "lost");
        await RejectAsync(() => lost.TickAsync(default), "pérdida de acuse después de CSV no acredita ejecución");
        loss.LoseExportAck = false; File.Delete(lost.OutboxPath);
        Check(J.Text((await Worker(loss, "lost").TickAsync(default))["status"]) == "awaiting_history" && !File.Exists(lost.OutboxPath), "acuse perdido no repite apuesta");
        var race = new RoundClient(Raw(), Fixtures()) { RevokeOnRead = 3 }; var rw = Worker(race, "race");
        Check(J.Text((await rw.TickAsync(default))["status"]) == "review" && !File.Exists(rw.OutboxPath), "revocación tras reserva impide publicar CSV");
        var revoked = new RoundClient(Raw(), Fixtures()); revoked.Command.Data["action"] = "revoke";
        Check(J.Text((await Worker(revoked, "revoke").TickAsync(default))["status"]) == "revoked", "revocación antes del envío");
        var noFile = new RoundClient(Raw(), Fixtures()); File.Delete(history);
        await RejectAsync(() => Worker(noFile, "nohistory").TickAsync(default), "archivo de historial ausente bloquea envío"); History();
        var simulation = new RoundClient(Raw(), Fixtures()); var sw = Worker(simulation, "sim"); await sw.TickAsync(default);
        var simBet = HistoryBet(0, 1, start, start.AddHours(2), -1); simBet.Element("SimulatedBet")!.Value = "true"; bets.Add(simBet); History(); time = start.AddHours(2);
        Check(J.Text((await sw.TickAsync(default))["status"]) == "awaiting_history", "apuesta simulada nunca confirma ejecución real");
        await RejectAsync(() => Worker(simulation, "pc2", agent: "otro").TickAsync(default), "lease bloquea segundo PC");
        bets.Clear(); History(); time = start;
        var legacyClient = new RoundClient(Raw(), Fixtures());
        legacyClient.Extra["PuenteJornadaRondaReal/user"] = new(new JsonObject { ["action"] = "authorize" }, "old-ok");
        legacyClient.Extra["PuenteJornadaRondaReal/user/Estado/actual"] = new(new JsonObject
            { ["terminal"] = false, ["reservedCount"] = 0, ["orders"] = new JsonArray() }, "old-state");
        var legacyWorker = new LiveRoundWorker(legacyClient, new RoundProvider(), "pc", Path.Combine(root,"legacy"), strategy, history,
            readOnly: false, legacyPilotPath: "PuenteJornadaReal/user", clock: () => time);
        await RejectAsync(() => legacyWorker.TickAsync(default), "ronda anterior activa bloquea el nuevo límite");
        Check(!File.Exists(legacyWorker.OutboxPath), "no publica CSV con otra ronda autorizada");
        legacyClient.Extra["PuenteJornadaRondaReal/user"].Data["action"] = "revoke";
        Check(J.Text((await legacyWorker.TickAsync(default))["status"]) == "exported", "ronda anterior revocada sin reservas permite el nuevo OK");
        Directory.Delete(root, true);
        return checks;
    }

    private static void WriteGzip(string path, string xml)
    { using var f = File.Create(path); using var gz = new GZipStream(f, CompressionLevel.Optimal); using var w = new StreamWriter(gz); w.Write(xml); }
    private static XElement HistoryBet(int i, decimal amount, DateTimeOffset placed, DateTimeOffset settled, decimal profit) => new("BetHistoryItem",
        new XElement("MarketId", "1.30000000" + i), new XElement("SelectionId", "58805"), new XElement("StrategyID", "round-strategy"),
        new XElement("StrategyName", LiveRoundCommand.Strategy), new XElement("Tipster", "empatesjornadaronda128"), new XElement("BetId", "bet" + i),
        new XElement("BetType", "BACK"), new XElement("Currency", "EUR"), new XElement("SimulatedBet", false), new XElement("Status", "SETTLED"),
        new XElement("Matched", amount), new XElement("Unmatched", 0), new XElement("AvgPrice", 4), new XElement("ProfitLoss", profit),
        new XElement("PlacedDate", J.Iso(placed)), new XElement("SettledDate", J.Iso(settled)));
}

sealed class RoundProvider : IResultsProvider
{
    public Task<List<Fixture>> EnrichAsync(string scope, List<Fixture> fixtures, DateTimeOffset now, CancellationToken ct) => Task.FromResult(fixtures);
}
sealed class RoundClient(JsonObject raw, List<Fixture> fixtures) : IBridgeClient
{
    public string CommandPath => "round-command"; public string StatePath => "round-state";
    public Dictionary<string, Document> Extra = new();
    public Document Command = new(raw, "v1"); public Document? State; public List<Fixture> Fixtures = fixtures;
    private int revision, reads; public bool LoseExportAck; public int RevokeOnRead;
    public Task<Document?> GetAsync(string path, CancellationToken ct)
    {
        if (path == CommandPath && ++reads == RevokeOnRead) { Command.Data["action"] = "revoke"; Command = new(Command.Data, "revoked"); }
        var d = path == CommandPath ? Command : path == StatePath ? State : Extra.GetValueOrDefault(path);
        return Task.FromResult(d is null ? null : new Document(d.Data.DeepClone().AsObject(), d.Version));
    }
    public Task<string> PatchAsync(string path, JsonObject data, string? expected, bool create, CancellationToken ct)
    {
        if (create ? State is not null : State?.Version != expected) throw new IOException("CAS conflict");
        if (LoseExportAck && J.Optional(data["status"]) == "exported") throw new IOException("lost ACK");
        var version = (++revision).ToString(); State = new(data.DeepClone().AsObject(), version); return Task.FromResult(version);
    }
    public Task<List<Fixture>> FixturesAsync(string scope, CancellationToken ct) => Task.FromResult(Fixtures.ToList());
}
