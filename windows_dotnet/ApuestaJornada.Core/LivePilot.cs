using System.Globalization;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace ApuestaJornada.Core;

// Una sola orden real por cuenta. No infiere ejecuciones a partir de resultados.
public sealed record LivePilotCommand(string Id, string Scope, string MatchId, string Home, string Away,
    DateTimeOffset Kickoff, DateTimeOffset Approved, string MarketId, string EventId, string Schedule,
    HashSet<string> Baseline, bool FromNow)
{
    public static LivePilotCommand Parse(JsonObject d)
    {
        var id = J.Text(d["requestId"]); var scope = J.Text(d["scope"]);
        var baseline = (d["baselineFinishedIds"] as JsonArray ?? throw new InvalidDataException("Falta el punto de inicio.")).Select(J.Text).ToList();
        var result = new LivePilotCommand(id, scope, J.Text(d["matchId"]), J.Text(d["home"]), J.Text(d["away"]),
            J.Time(d["kickoff"]), J.Time(d["approvedAt"]), J.Text(d["marketId"]), J.Text(d["eventId"]), J.Text(d["schedule"]), baseline.ToHashSet(), J.Bool(d["fromNow"]));
        if (J.Int(d["schema"]) != 1 || J.Text(d["mode"]) != "live-pilot" || J.Text(d["currency"]) != "EUR" ||
            J.Int(d["stakeCents"]) != 100 || J.Int(d["budgetCents"]) != 100 || J.Number(d["minPrice"]) != 2.8 || J.Number(d["maxPrice"]) != 20 ||
            J.Text(d["betType"]) != "BACK" || J.Text(d["selectionId"]) != "58805" || !J.Bool(d["marketConfirmed"]) ||
            !Regex.IsMatch(id, "^[a-f0-9]{32}$") || !Regex.IsMatch(scope, @"^LaLiga/\d{4}-\d{4}/([1-9]|[12]\d|3[0-8])$") ||
            !Regex.IsMatch(result.MarketId, @"^1\.\d{6,12}$") || !Regex.IsMatch(result.EventId, @"^[1-9]\d{3,15}$") ||
            result.MatchId.Length == 0 || result.Home.Length == 0 || result.Away.Length == 0 || result.Approved >= result.Kickoff.AddSeconds(-60) ||
            baseline.Count != result.Baseline.Count || baseline.Count > 9 || result.Baseline.Contains(result.MatchId) || (!result.FromNow && baseline.Count != 0))
            throw new InvalidDataException("El OK no corresponde a la prueba real de una orden BACK de 1 €.");
        if (ExcludedTeams.IsExcludedFixture(result.Home, result.Away)) throw new InvalidDataException("Partido excluido por equipo.");
        if (J.Time(d["expiresAt"]) != result.Kickoff.AddSeconds(-60)) throw new InvalidDataException("Caducidad incoherente.");
        return result;
    }
    public string Fingerprint => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
        $"{Id}|{Scope}|{MatchId}|{Home}|{Away}|{J.Iso(Kickoff)}|{J.Iso(Approved)}|{MarketId}|{EventId}|{Schedule}|{string.Join(',', Baseline.Order())}|{FromNow}")));
    public string Csv => "\"Provider\",\"EventId\",\"MarketId\",\"SelectionId\",\"MarketType\",\"Handicap\",\"BetType\",\"Size\",\"Price\",\"MinPrice\",\"MaxPrice\"\r\n" +
        $"\"EmpatesJornada\",\"{EventId}\",\"{MarketId}\",\"58805\",\"MATCH_ODDS\",\"0\",\"BACK\",\"1.00\",\"2.80\",\"2.80\",\"20.00\"\r\n";
    public string? BlockReason(IReadOnlyList<Fixture> fixtures, DateTimeOffset now)
    {
        if (now < Approved || now >= Kickoff.AddSeconds(-60)) return "El OK ha caducado o el reloj es incorrecto.";
        if (fixtures.Count != 10 || fixtures.Select(f => f.Id).Distinct().Count() != 10) return "Faltan los diez partidos fiables de la jornada.";
        var rows = JsonNode.Parse(Schedule) as JsonArray ?? throw new InvalidDataException("Calendario no válido.");
        var expected = rows.Select(n => { var r = (JsonArray)n!; return new Fixture(J.Text(r[0]), J.Text(r[1]), J.Text(r[2]), r[3] is null ? null : J.Time(r[3]), Unavailable: J.Bool(r[4])); }).OrderBy(f => f.Id, StringComparer.Ordinal);
        if (!fixtures.Select(f => f.ScheduleOnly()).OrderBy(f => f.Id, StringComparer.Ordinal).SequenceEqual(expected)) return "Cambió el calendario; requiere otro OK. Esta autorización no se enviará.";
        var selected = fixtures.SingleOrDefault(f => f.Id == MatchId);
        if (selected is null || selected.Home != Home || selected.Away != Away || selected.Kickoff != Kickoff || selected.Final || selected.Unavailable) return "El partido elegido no coincide o ya no está disponible.";
        if (Baseline.Any(id => !fixtures.Any(f => f.Id == id && f.Final))) return "Un resultado anterior dejó de estar confirmado.";
        if (fixtures.Any(f => f.Draw && !Baseline.Contains(f.Id))) return "Hay un nuevo empate final: no se envía ninguna orden.";
        if (fixtures.Any(f => !f.Final && !f.Unavailable && (f.Kickoff is null || f.Kickoff <= now))) return "Hay partidos iniciados sin final confirmado.";
        var first = fixtures.Where(f => !f.Final && !f.Unavailable).Min(f => f.Kickoff);
        if (first is null || Kickoff >= first.Value.AddMinutes(120)) return "Debes elegir un partido del primer grupo pendiente.";
        return null;
    }
}

public static class LiveStrategyValidator
{
    public static void Validate(string path, bool round = false)
    {
        using var file = File.OpenRead(path); using var gz = new GZipStream(file, CompressionMode.Decompress);
        using var memory = new MemoryStream(); var buffer = new byte[4096]; int count;
        while ((count = gz.Read(buffer)) > 0) { memory.Write(buffer, 0, count); if (memory.Length > 250000) throw new InvalidDataException("Exportación demasiado grande."); }
        var settings = new System.Xml.XmlReaderSettings { DtdProcessing = System.Xml.DtdProcessing.Prohibit, XmlResolver = null };
        memory.Position = 0; using var reader = System.Xml.XmlReader.Create(memory, settings); var xml = XDocument.Load(reader);
        var strategies = xml.Root?.Elements("BettingStrategy").ToList() ?? [];
        if (strategies.Count != 1) throw new InvalidDataException("Exporta únicamente Empates por jornada.");
        var s = strategies[0]; var xsi = XName.Get("type", "http://www.w3.org/2001/XMLSchema-instance");
        var rules = s.Descendants().Where(e => e.Attribute(xsi) is not null).ToDictionary(e => e.Attribute(xsi)!.Value);
        XElement Rule(string name) => rules.GetValueOrDefault(name) ?? throw new InvalidDataException("Falta la regla " + name);
        void Has(XElement e, string key, string expected) { if (e.Element(key)?.Value != expected) throw new InvalidDataException($"Configuración requerida: {key} = {expected}."); }
        void Number(XElement e, string key, decimal expected) { if (!decimal.TryParse(e.Element(key)?.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || value != expected) throw new InvalidDataException($"Configuración requerida: {key} = {expected}."); }
        var known = new HashSet<string> { "TimeToBetCondition", "OverroundCondition", "DefaultBetTypeCondition", "MinMaxSelectionPriceCondition", "BackLayRatioCondition", "PriceRuleCondition", "LevelStakeCondition", "TipsCondition", "CancelIfUnmatchedCondition" };
        if (!known.SetEquals(rules.Keys) || s.Element("StandaloneConditions")?.HasElements == true) throw new InvalidDataException("La estrategia contiene reglas adicionales o le faltan reglas revisadas.");
        Has(s, "Name", round ? "Empates jornada 15 EUR" : "Empates por jornada"); Number(s, "MaxBetLiability", round ? 8 : 1); Number(s, "MaxNumOfBetsPerRunner", 1); Number(s, "MaxNumOfBetsPerMarket", 1); Number(s, "MaxNumOfBetsPerEvent", 1);
        var t = Rule("TimeToBetCondition"); Has(t, "BetBeforeInPlay", "true"); Has(t, "StopBeforeInPlay", "true"); Has(t, "KeepBettingInPlay", "false"); Has(t, "BetAfterInPlay", "false"); Number(t, "BeforeInPlay", 3000000000); Number(t, "StopBeforeInPlayTicks", 600000000);
        Has(Rule("DefaultBetTypeCondition"), "BetType", "BACK");
        var prices = Rule("MinMaxSelectionPriceCondition"); Number(prices, "MinPrice", 2.8m); Number(prices, "MaxPrice", 20); Has(prices, "PriceType", "BackPrice"); Has(prices, "IgnoreBeforeStartTime", "false"); Has(prices, "UseCustomPriceRange", "false");
        var p = Rule("PriceRuleCondition"); Has(p, "InitialPriceChoice", "ActualPrice"); Has(p, "UseStartPrices", "false"); foreach (var key in new[] { "TicksToImprove", "TicksToWorsen", "PercentsToImprove", "PercentsToWorsen" }) Number(p, key, 0);
        Number(Rule("LevelStakeCondition"), "Stake", 1); Has(Rule("LevelStakeCondition"), "UseCustomStake", "false");
        var tips = Rule("TipsCondition"); Has(tips, "ProvidersCSV", round ? "EmpatesJornadaRonda" : "EmpatesJornada"); Has(tips, "IgnoreTipBetType", "false"); Has(tips, "IgnoreTipPrice", "false"); Has(tips, "IgnoreTipStake", round ? "false" : "true"); Has(tips, "IgnoreTipPoints", "true"); Has(tips, "IgnoreMinMaxPrice", "false");
        var cancel = Rule("CancelIfUnmatchedCondition"); Has(cancel, "CancelBeforeStart", "true"); Number(cancel, "BeforeStart", 300000000);
    }
}

public sealed class LivePilotWorker(IBridgeClient client, IResultsProvider provider, string agentId, string folder, string strategyPath, Func<DateTimeOffset>? clock = null)
{
    private DateTimeOffset Now => clock?.Invoke() ?? DateTimeOffset.UtcNow;
    public string OutboxPath => Path.Combine(folder, "EmpatesJornada.csv");
    private string ReceiptPath => Path.Combine(folder, "live-pilot-once.json");
    private void Persist(JsonObject receipt)
    {
        Directory.CreateDirectory(folder); var temporary = ReceiptPath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) { stream.Write(Encoding.UTF8.GetBytes(receipt.ToJsonString())); stream.Flush(true); }
        File.Move(temporary, ReceiptPath, true);
    }
    public async Task<JsonObject> TickAsync(CancellationToken ct)
    {
        Directory.CreateDirectory(folder);
        var command = await client.GetAsync(client.CommandPath, ct);
        var old = await client.GetAsync(client.StatePath, ct);
        var state = old?.Data.DeepClone().AsObject() ?? new JsonObject { ["dispatchReserved"] = false, ["requestId"] = "" };
        if (J.Optional(state["agentId"]) is string other && other != agentId && state["leaseUntil"] is not null && J.Time(state["leaseUntil"]) > Now) throw new InvalidOperationException("Otro PC controla la prueba real.");
        state["mode"] = "live-pilot"; state["agentId"] = agentId; state["lastSeenAt"] = J.Iso(Now); state["leaseUntil"] = J.Iso(Now.AddSeconds(60));
        var version = await client.PatchAsync(client.StatePath, state, old?.Version, old is null, ct);
        async Task<JsonObject> Save(string status, string message) { state["status"] = status; state["message"] = message; state["lastSeenAt"] = J.Iso(Now); await client.PatchAsync(client.StatePath, state, version, false, ct); return state; }
        if (command is null) return await Save("idle", "REAL · Esperando un nuevo OK explícito del móvil. Máximo una orden de 1 €.");
        var c = LivePilotCommand.Parse(command.Data); var fingerprint = c.Fingerprint;
        state["requestId"] = c.Id;
        if (J.Bool(state["dispatchReserved"]) || File.Exists(ReceiptPath) || File.Exists(OutboxPath))
            return await Save("requires_review", J.Optional(command.Data["action"]) == "revoke" ? "Revocación recibida tras reservar/enviar. Pausa BF Bot Manager y comprueba/cancela allí lo pendiente. No se confirma cancelación de la apuesta." : "Orden reservada o enviada anteriormente. No se reenvía. Comprueba su ejecución y liquidación en BF Bot Manager; no se enviará una segunda orden.");
        if (J.Text(command.Data["action"]) == "revoke") return await Save("revoked", "OK revocado antes del envío. Ninguna orden emitida.");
        if (J.Text(command.Data["action"]) != "authorize") throw new InvalidDataException("Acción desconocida.");
        LiveStrategyValidator.Validate(strategyPath);
        var fixtures = await provider.EnrichAsync(c.Scope, await client.FixturesAsync(c.Scope, ct), Now, ct);
        var reason = c.BlockReason(fixtures, Now);
        if (reason is not null) return await Save("blocked", reason);
        if (Now < c.Kickoff.AddMinutes(-5)) return await Save("waiting", "REAL · Esperando los cinco minutos previos. Máximo 1 €; sin progresión automática.");
        // Reserva duradera ANTES de hacer visible el CSV. Si el proceso falla,
        // la cuenta queda bloqueada para reconciliar; nunca se reintenta a ciegas.
        var current = await client.GetAsync(client.CommandPath, ct);
        if (current is null || current.Version != command.Version || J.Optional(current.Data["action"]) != "authorize") return await Save("blocked", "Cambió el OK antes de la reserva. No enviado.");
        ct.ThrowIfCancellationRequested();
        state["dispatchReserved"] = true; state["fingerprint"] = fingerprint; state["status"] = "reserved"; state["message"] = "Orden reservada. Envío aún sin confirmar.";
        version = await client.PatchAsync(client.StatePath, state, version, false, ct);
        Persist(new JsonObject { ["requestId"] = c.Id, ["fingerprint"] = fingerprint, ["status"] = "reserved" });
        current = await client.GetAsync(client.CommandPath, ct);
        if (current is null || current.Version != command.Version || J.Optional(current.Data["action"]) != "authorize") return await Save("requires_review", "OK cambiado tras reservar. No se publica el CSV; revisar antes de otra prueba.");
        LiveStrategyValidator.Validate(strategyPath);
        // Segunda consulta fresca de resultados y calendario tras la reserva.
        fixtures = await provider.EnrichAsync(c.Scope, await client.FixturesAsync(c.Scope, ct), Now, ct);
        reason = c.BlockReason(fixtures, Now);
        if (reason is not null) return await Save("requires_review", "No se publica el CSV: " + reason);
        current = await client.GetAsync(client.CommandPath, ct);
        if (current is null || current.Version != command.Version || J.Optional(current.Data["action"]) != "authorize") return await Save("requires_review", "Revocación o cambio de OK justo antes de publicar. CSV no enviado.");
        if (Now >= c.Kickoff.AddSeconds(-60)) return await Save("requires_review", "Ventana de envío cerrada tras la comprobación final. No enviado.");
        ct.ThrowIfCancellationRequested();
        var temp = OutboxPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) { stream.Write(Encoding.UTF8.GetBytes(c.Csv)); stream.Flush(true); } File.Move(temp, OutboxPath, false); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
        Persist(new JsonObject { ["requestId"] = c.Id, ["fingerprint"] = fingerprint, ["status"] = "exported", ["exportedAt"] = J.Iso(Now) });
        return await Save("exported", "CSV real publicado para BF Bot Manager: BACK empate, 1 €, mínimo 2,80. Enviado NO significa ejecutado. Prueba detenida hasta revisar aceptación, importe y liquidación.");
    }
}
