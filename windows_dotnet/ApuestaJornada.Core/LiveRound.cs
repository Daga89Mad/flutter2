using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace ApuestaJornada.Core;

public sealed record RoundLeg(string MatchId, string Home, string Away, DateTimeOffset Kickoff, string MarketId, string EventId);
public sealed record LiveRoundCommand(string Id, string Scope, DateTimeOffset Approved, DateTimeOffset Expires,
    string Schedule, HashSet<string> Baseline, List<RoundLeg> Legs, string Fingerprint)
{
    public const string Provider = "EmpatesJornadaRonda128", Strategy = "Empates jornada max128 EUR";
    public static LiveRoundCommand Parse(JsonObject d)
    {
        var scope = J.Text(d["scope"]); var id = J.Text(d["requestId"]);
        var approved = J.Time(d["approvedAt"]); var expires = J.Time(d["expiresAt"]);
        if (J.Int(d["schema"]) != 1 || J.Text(d["mode"]) != "live-round-128-v1" ||
            !Regex.IsMatch(id, "^[a-f0-9]{32}$") || !Regex.IsMatch(scope, @"^LaLiga/\d{4}-\d{4}/([1-9]|[12]\d|3[0-8])$") ||
            J.Text(d["currency"]) != "EUR" || J.Int(d["budgetCents"]) != 25500 || J.Int(d["maxBets"]) != 8 || J.Int(d["maxStakeCents"]) != 12800 ||
            J.Number(d["minPrice"]) != 2.8 || J.Number(d["maxPrice"]) != 20 ||
            !J.Bool(d["excludeBigThree"]) || !J.Bool(d["marketConfirmed"]) || !J.Bool(d["fromNow"]))
            throw new InvalidDataException("Falta autorización REAL de hasta 8 órdenes, máximo por apuesta 128 € y acumulado 255 €.");
        var rows = JsonNode.Parse(J.Text(d["legs"])) as JsonArray ?? throw new InvalidDataException("Faltan partidos elegidos.");
        var legs = rows.Select(n =>
        {
            var r = n as JsonArray ?? throw new InvalidDataException("Partido inválido.");
            if (r.Count != 6) throw new InvalidDataException("Partido incompleto.");
            return new RoundLeg(J.Text(r[0]), J.Text(r[1]), J.Text(r[2]), J.Time(r[3]), J.Text(r[4]), J.Text(r[5]));
        }).ToList();
        if (legs.Count is < 1 or > 8 || legs.Select(l => l.MatchId).Distinct().Count() != legs.Count ||
            legs.Select(l => l.MarketId).Distinct().Count() != legs.Count || legs.Select(l => l.EventId).Distinct().Count() != legs.Count ||
            legs.Any(l => string.IsNullOrWhiteSpace(l.MatchId) || string.IsNullOrWhiteSpace(l.Home) || string.IsNullOrWhiteSpace(l.Away) ||
                ExcludedTeams.IsExcludedFixture(l.Home, l.Away) || !Regex.IsMatch(l.MarketId, @"^1\.\d{6,12}$") ||
                !Regex.IsMatch(l.EventId, @"^[1-9]\d{3,15}$") || l.Kickoff <= approved.AddSeconds(60)) ||
            legs.Zip(legs.Skip(1)).Any(p => p.Second.Kickoff - p.First.Kickoff < TimeSpan.FromMinutes(120)) ||
            expires != legs[^1].Kickoff.AddSeconds(-60) || expires - approved > TimeSpan.FromDays(4))
            throw new InvalidDataException("Revisa equipos, IDs, orden, solapamientos o caducidad de la prueba.");
        var years = scope.Split('/')[1].Split('-');
        if (int.Parse(years[1], CultureInfo.InvariantCulture) != int.Parse(years[0], CultureInfo.InvariantCulture) + 1)
            throw new InvalidDataException("Temporada inválida.");
        var baselineRows = d["baselineFinishedIds"] as JsonArray ?? throw new InvalidDataException("Falta punto de inicio.");
        var baseline = baselineRows.Select(J.Text).ToHashSet(StringComparer.Ordinal);
        if (baseline.Count != baselineRows.Count || baseline.Count > 9 || legs.Any(l => baseline.Contains(l.MatchId)))
            throw new InvalidDataException("Punto de inicio inválido.");
        var immutable = d.DeepClone().AsObject(); immutable.Remove("action"); immutable.Remove("updatedAt");
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(J.Canonical(immutable))));
        var command = new LiveRoundCommand(id, scope, approved, expires, J.Text(d["schedule"]), baseline, legs, hash);
        command.CheckSchedule(command.Expected());
        return command;
    }

    private List<Fixture> Expected() => (JsonNode.Parse(Schedule) as JsonArray ?? throw new InvalidDataException("Calendario inválido."))
        .Select(n => { var r = n as JsonArray ?? throw new InvalidDataException("Calendario inválido.");
            if (r.Count != 5) throw new InvalidDataException("Calendario incompleto.");
            return new Fixture(J.Text(r[0]), J.Text(r[1]), J.Text(r[2]), r[3] is null ? null : J.Time(r[3]), Unavailable: J.Bool(r[4])); }).ToList();

    public void CheckSchedule(IReadOnlyList<Fixture> fixtures)
    {
        var expected = Expected();
        if (expected.Count != 10 || expected.Select(f => f.Id).Distinct().Count() != 10 || fixtures.Count != 10 ||
            !fixtures.Select(f => f.ScheduleOnly()).OrderBy(f => f.Id, StringComparer.Ordinal)
                .SequenceEqual(expected.OrderBy(f => f.Id, StringComparer.Ordinal)) ||
            Baseline.Any(id => !expected.Any(f => f.Id == id)) ||
            Legs.Any(l => !expected.Any(f => f.Id == l.MatchId && f.Home == l.Home && f.Away == l.Away && f.Kickoff == l.Kickoff && !f.Unavailable)))
            throw new InvalidDataException("Cambió el calendario o no coincide con los partidos autorizados. Prueba detenida.");
    }

    public static string Csv(RoundLeg l, int cents)
    {
        if (!Enumerable.Range(0, 8).Any(i => cents == (100 << i))) throw new InvalidDataException("Importe fuera de la progresión hasta 128 €.");
        return
        "\"Provider\",\"EventId\",\"MarketId\",\"SelectionId\",\"MarketType\",\"Handicap\",\"BetType\",\"Size\",\"Price\",\"MinPrice\",\"MaxPrice\"\r\n" +
        $"\"{Provider}\",\"{l.EventId}\",\"{l.MarketId}\",\"58805\",\"MATCH_ODDS\",\"0\",\"BACK\",\"{(cents / 100m).ToString("0.00", CultureInfo.InvariantCulture)}\",\"2.80\",\"2.80\",\"20.00\"\r\n";
    }
}

public sealed class LiveRoundWorker(IBridgeClient client, IResultsProvider provider, string agentId, string folder,
    string strategyPath, string historyPath, bool readOnly = true, string? legacyPilotPath = null, Func<DateTimeOffset>? clock = null)
{
    private DateTimeOffset Now => clock?.Invoke() ?? DateTimeOffset.UtcNow;
    public string OutboxPath => Path.Combine(folder, "EmpatesJornadaRonda128.csv");
    private string ReceiptPath => Path.Combine(folder, "round-receipt.json");
    private void Persist(JsonObject state)
    {
        Directory.CreateDirectory(folder); var tmp = ReceiptPath + ".tmp";
        using (var f = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        { f.Write(Encoding.UTF8.GetBytes(state.ToJsonString())); f.Flush(true); }
        File.Move(tmp, ReceiptPath, true);
    }
    private async Task CheckLegacy(List<BfBet> history, CancellationToken ct)
    {
        if (legacyPilotPath is null) return;
        var pilot = await client.GetAsync(legacyPilotPath, ct);
        var oldState = await client.GetAsync(legacyPilotPath + "/Estado/actual", ct);
        if (pilot is not null && (J.Optional(pilot.Data["action"]) == "authorize" || J.Bool(oldState?.Data["dispatchReserved"])))
        {
            var matching = history.Where(b => !b.Simulated && b.Currency == "EUR" && b.Type == "BACK" &&
                b.MarketId == J.Text(pilot.Data["marketId"]) && b.SelectionId == "58805" &&
                b.StrategyName == "Empates por jornada" && b.Tipster.Equals("empatesjornada", StringComparison.OrdinalIgnoreCase)).ToList();
            if (matching.Count != 1 || !matching[0].Terminal || matching[0].Matched != 1)
                throw new InvalidDataException("La primera prueba de 1 € sigue sin conciliar. No se activa la nueva ronda.");
        }
        var previousPath = "PuenteJornadaRondaReal/" + legacyPilotPath.Split('/')[^1];
        var previous = await client.GetAsync(previousPath, ct);
        if (previous is null) return;
        var previousState = await client.GetAsync(previousPath + "/Estado/actual", ct);
        if (previousState is null) throw new InvalidDataException("Existe un OK anterior de 15 € sin estado confirmado. Revisa esa prueba antes de la nueva.");
        if (J.Optional(previous.Data["action"]) != "revoke" && !J.Bool(previousState.Data["terminal"]))
            throw new InvalidDataException("Revoca primero los siguientes envíos de la ronda anterior de 15 €.");
        var previousOrders = previousState.Data["orders"] as JsonArray ?? throw new InvalidDataException("Falta el historial de reservas anterior.");
        if (J.Int(previousState.Data["reservedCount"]) != previousOrders.Count) throw new InvalidDataException("Reservas anteriores incoherentes.");
        foreach (var n in previousOrders)
        {
            var order = J.Object(n);
            var matching = history.Where(b => !b.Simulated && b.Currency == "EUR" && b.Type == "BACK" && b.SelectionId == "58805" &&
                b.MarketId == J.Text(order["marketId"]) && b.StrategyName == "Empates jornada 15 EUR" &&
                b.Tipster.Equals("EmpatesJornadaRonda", StringComparison.OrdinalIgnoreCase)).ToList();
            if (matching.Count != 1 || !matching[0].Terminal || matching[0].Matched != J.Int(order["cents"]) / 100m)
                throw new InvalidDataException("Hay órdenes de la ronda de 15 € sin liquidar o conciliar. No se amplía el riesgo.");
        }
    }

    public async Task<JsonObject> TickAsync(CancellationToken ct)
    {
        Directory.CreateDirectory(folder);
        var history = BfHistory.Read(historyPath); // Un archivo ausente, incompleto o ilegible bloquea cualquier envío.
        var command = await client.GetAsync(client.CommandPath, ct);
        var old = await client.GetAsync(client.StatePath, ct);
        var state = old?.Data.DeepClone().AsObject() ?? new JsonObject
        { ["mode"] = "live-round-128-v1", ["requestId"] = "", ["fingerprint"] = "", ["reservedCount"] = 0, ["orders"] = new JsonArray(), ["terminal"] = false };
        if (J.Optional(state["agentId"]) is string other && other != agentId && state["leaseUntil"] is not null && J.Time(state["leaseUntil"]) > Now)
            throw new InvalidOperationException("Otro PC controla esta prueba.");
        state["agentId"] = agentId; state["lastSeenAt"] = J.Iso(Now); state["leaseUntil"] = J.Iso(Now.AddSeconds(60));
        var version = old?.Version;
        async Task<JsonObject> Save(string status, string message, bool terminal = false)
        {
            state["status"] = status; state["message"] = message; state["terminal"] = J.Bool(state["terminal"]) || terminal;
            state["lastSeenAt"] = J.Iso(Now); state["leaseUntil"] = J.Iso(Now.AddSeconds(60));
            version = await client.PatchAsync(client.StatePath, state, version, version is null, ct);
            if (J.Int(state["reservedCount"]) > 0) Persist(state);
            return state;
        }
        if (old is null) await Save("checking", "Conectado: comprobando la autorización y el historial.");
        if (command is null) return await Save("idle", $"Historial leído: {history.Count} registros. Esperando OK de ronda REAL; máximo acumulado 255 € (128 € por apuesta).");
        var c = LiveRoundCommand.Parse(command.Data);
        if (J.Text(state["requestId"]) is { Length: > 0 } previous && previous != c.Id ||
            J.Text(state["fingerprint"]) is { Length: > 0 } fingerprint && fingerprint != c.Fingerprint)
            throw new InvalidDataException("La autorización cambió. No se inicia otra ronda.");
        state["requestId"] = c.Id; state["fingerprint"] = c.Fingerprint;
        var orders = state["orders"] as JsonArray ?? throw new InvalidDataException("Historial remoto inválido.");
        var reserved = J.Int(state["reservedCount"]);
        if (reserved != orders.Count || reserved < 0 || reserved > c.Legs.Count) throw new InvalidDataException("Reservas remotas incoherentes.");
        if (File.Exists(ReceiptPath))
        {
            var local = J.Object(JsonNode.Parse(File.ReadAllText(ReceiptPath)));
            if (J.Text(local["fingerprint"]) != c.Fingerprint || J.Int(local["reservedCount"]) > reserved ||
                (J.Bool(local["terminal"]) && !J.Bool(state["terminal"])))
                throw new InvalidDataException("El registro local impide reiniciar o retroceder la prueba.");
        }
        else if (File.Exists(OutboxPath) && reserved == 0) throw new InvalidDataException("Ya existe un CSV sin reserva conciliada. No se sobrescribe.");
        if (J.Bool(state["terminal"])) return await Save(J.Text(state["status"]), J.Text(state["message"]));
        if (J.Text(command.Data["action"]) == "revoke") return await Save("revoked", "Revocado: no se enviarán más órdenes. Revisa/cancela lo pendiente en BF Bot; la revocación no cancela apuestas en Betfair.", true);
        if (J.Text(command.Data["action"]) != "authorize") throw new InvalidDataException("Acción no válida.");
        if (Now < c.Approved) return await Save("stopped", "OK caducado o reloj incorrecto. No se reinicia la progresión.", true);
        var fixtures = await provider.EnrichAsync(c.Scope, await client.FixturesAsync(c.Scope, ct), Now, ct);
        c.CheckSchedule(fixtures);
        if (c.Baseline.Any(id => !fixtures.Any(f => f.Id == id && f.Final))) return await Save("stopped", "Un resultado anterior dejó de estar confirmado.", true);
        // Una liquidación completa debe ser idéntica en dos lecturas separadas al menos 15 segundos.
        var evidence = new List<string>(); var incomplete = false; var won = false; var spent = 0;
        for (var i = 0; i < reserved; i++)
        {
            var order = J.Object(orders[i]); var leg = c.Legs[i]; var cents = 100 << i;
            if (J.Text(order["marketId"]) != leg.MarketId || J.Int(order["cents"]) != cents || J.Text(order["matchId"]) != leg.MatchId)
                throw new InvalidDataException("La reserva no coincide con el OK.");
            spent += cents;
            var matching = history.Where(b => b.MarketId == leg.MarketId && b.SelectionId == "58805" && !b.Simulated &&
                b.Type == "BACK" && b.Currency == "EUR" && b.StrategyName == LiveRoundCommand.Strategy &&
                b.Tipster.Equals(LiveRoundCommand.Provider, StringComparison.OrdinalIgnoreCase)).ToList();
            if (matching.Count == 0) { incomplete = true; order["status"] = "unconfirmed"; continue; }
            if (matching.Count != 1) return await Save("review", "Varias apuestas coinciden con una orden. Revisión manual; no se duplica.", true);
            var b = matching[0];
            if (b.Placed < J.Time(order["reservedAt"]).AddSeconds(-1) || b.Placed >= leg.Kickoff.AddSeconds(-60) ||
                b.Matched != cents / 100m || b.Unmatched != 0 || b.AveragePrice < 2.8m || b.AveragePrice > 20 ||
                (i > 0 && J.Optional(J.Object(orders[0])["strategyId"]) is string strategyId && b.StrategyId != strategyId))
                return await Save("review", "Importe parcial, cuota, fecha o estrategia incoherentes. No se continúa.", true);
            order["betId"] = b.Id; order["strategyId"] = b.StrategyId; order["matchedCents"] = (int)(b.Matched * 100);
            order["odds"] = (double)b.AveragePrice; order["profitLossCents"] = (int)decimal.Round(b.ProfitLoss * 100);
            order["status"] = b.Status; order["settledAt"] = b.Settled is null ? null : J.Iso(b.Settled.Value);
            if (!b.Terminal) { incomplete = true; continue; }
            if (b.Settled < b.Placed || b.Settled > Now || b.ProfitLoss == 0 || b.ProfitLoss < -b.Matched)
                return await Save("review", "Liquidación nula o incoherente: revisar antes de continuar.", true);
            if (b.ProfitLoss > 0) won = true;
            else if (b.ProfitLoss != -b.Matched) return await Save("review", "Pérdida distinta al importe completo: revisión necesaria.", true);
            evidence.Add($"{b.Id}|{b.Status}|{b.Matched}|{b.AveragePrice}|{b.ProfitLoss}|{J.Iso(b.Settled!.Value)}");
        }
        state["spentCents"] = spent;
        if (won) return await Save("won", "Empate ganado confirmado en el historial de BF Bot. Prueba terminada.", true);
        if (fixtures.Any(f => !ExcludedTeams.IsExcludedFixture(f) && f.Draw && !c.Baseline.Contains(f.Id)))
            return await Save("stopped", "Nuevo empate final en la jornada. No se envían más apuestas.", true);
        if (incomplete) return await Save("awaiting_history", "Orden reservada: esperando aceptación o liquidación completa de BF Bot. No se reenvía ni aumenta el importe.");
        var signature = string.Join(';', evidence);
        if (reserved > 0 && (J.Optional(state["evidence"]) != signature || state["evidenceAt"] is null))
        { state["evidence"] = signature; state["evidenceAt"] = J.Iso(Now); return await Save("confirming", "Liquidación leída. Esperando una segunda lectura estable antes de continuar."); }
        if (reserved > 0 && Now - J.Time(state["evidenceAt"]) < TimeSpan.FromSeconds(15))
            return await Save("confirming", "Esperando confirmar la liquidación estable.");
        if (reserved >= c.Legs.Count || reserved == 8) return await Save("completed", "Terminados los partidos autorizados. No hay reinicio automático.", true);
        var next = c.Legs[reserved]; var nextCents = 100 << reserved;
        if (spent + nextCents > 25500 || nextCents > 12800) return await Save("stopped", "Límite total de 255 € o máximo por apuesta de 128 € alcanzado.", true);
        if (Now >= c.Expires || fixtures.Any(f => f.Id == next.MatchId && (f.Final || f.Unavailable)) || Now >= next.Kickoff.AddSeconds(-60))
            return await Save("stopped", "Se perdió la ventana del siguiente partido. No se salta ni se apuesta en directo.", true);
        if (readOnly) return await Save("read_only", "Sólo comprobación: historial conciliado; no se publican órdenes reales.");
        if (Now < next.Kickoff.AddMinutes(-5)) return await Save("waiting", $"Esperando a {next.Home} — {next.Away}. Próximo importe: {nextCents / 100} €. Máximo total 255 €.");
        var unresolved = fixtures.Any(f => !ExcludedTeams.IsExcludedFixture(f) && !f.Final && !f.Unavailable &&
            (f.Kickoff is null || f.Kickoff <= Now));
        if (unresolved) return await Save("waiting_results", "Hay un partido iniciado sin final confirmado. No se envía otra apuesta.");
        await CheckLegacy(history, ct);
        if (history.Any(b => !b.Simulated && (b.Tipster.Equals(LiveRoundCommand.Provider, StringComparison.OrdinalIgnoreCase) ||
            b.Tipster.Equals("EmpatesJornada", StringComparison.OrdinalIgnoreCase)) && !b.Terminal))
            return await Save("review", "Hay apuestas anteriores pendientes de conciliar.", true);
        LiveStrategyValidator.Validate(strategyPath, round: true);
        var current = await client.GetAsync(client.CommandPath, ct);
        if (current is null || current.Version != command.Version || J.Optional(current.Data["action"]) != "authorize")
            return await Save("revoked", "Cambió el OK antes de reservar. Ninguna orden nueva.", true);
        // Reserva remota permanente ANTES del CSV. Ausencia de respuesta nunca autoriza repetir.
        orders.Add(new JsonObject { ["matchId"] = next.MatchId, ["marketId"] = next.MarketId,
            ["cents"] = nextCents, ["reservedAt"] = J.Iso(Now), ["status"] = "reserved" });
        state["reservedCount"] = reserved + 1; state["spentCents"] = spent + nextCents;
        await Save("reserved", "Orden reservada; publicación todavía sin confirmar.");
        fixtures = await provider.EnrichAsync(c.Scope, await client.FixturesAsync(c.Scope, ct), Now, ct); c.CheckSchedule(fixtures);
        current = await client.GetAsync(client.CommandPath, ct);
        if (current is null || current.Version != command.Version || J.Optional(current.Data["action"]) != "authorize" ||
            Now >= next.Kickoff.AddSeconds(-60) || fixtures.Any(f => !ExcludedTeams.IsExcludedFixture(f) && f.Draw && !c.Baseline.Contains(f.Id)) ||
            fixtures.Any(f => !ExcludedTeams.IsExcludedFixture(f) && !f.Final && !f.Unavailable && (f.Kickoff is null || f.Kickoff <= Now)))
            return await Save("review", "Cambio tras reservar. CSV no publicado; revisar la reserva, no reintentar.", true);
        LiveStrategyValidator.Validate(strategyPath, round: true);
        var latestHistory = BfHistory.Read(historyPath);
        if (!history.OrderBy(b => b.Id, StringComparer.Ordinal).SequenceEqual(latestHistory.OrderBy(b => b.Id, StringComparer.Ordinal)))
            return await Save("review", "Cambió el historial tras reservar. No se publica ni se reintenta.", true);
        ct.ThrowIfCancellationRequested();
        var temp = OutboxPath + ".tmp";
        try
        {
            using (var f = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { f.Write(Encoding.UTF8.GetBytes(LiveRoundCommand.Csv(next, nextCents))); f.Flush(true); }
            File.Move(temp, OutboxPath, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
        J.Object(orders[^1])["status"] = "exported";
        return await Save("exported", $"CSV publicado: {nextCents / 100} € al empate. Esperando confirmación de BF Bot; publicado no equivale a ejecutado.");
    }
}
