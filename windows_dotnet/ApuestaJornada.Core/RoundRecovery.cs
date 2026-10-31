using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace ApuestaJornada.Core;

public sealed partial class LiveRoundWorker
{
    private static string RecoverySignature(JsonArray orders) => "recovery:" +
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(J.Canonical(orders))));

    private static void ValidateSettledLoss(JsonObject order, int index)
    {
        var cents = 100 << index;
        var odds = J.Number(order["odds"]);
        if (!double.IsFinite(odds) || J.Int(order["cents"]) != cents || J.Int(order["matchedCents"]) != cents ||
            J.Int(order["profitLossCents"]) != -cents || J.Text(order["status"]) != "SETTLED" ||
            string.IsNullOrWhiteSpace(J.Text(order["betId"])) || string.IsNullOrWhiteSpace(J.Text(order["strategyId"])) ||
            odds < 2.8 || odds > 20 ||
            J.Time(order["settledAt"]) < J.Time(order["reservedAt"]))
            throw new InvalidDataException("La recuperación exige pérdidas completas liquidadas, sin reiniciar importes.");
    }

    private static bool SameSettledLoss(BfBet b, JsonObject order, RoundLeg leg, int index) =>
        b.Terminal && !b.Simulated && b.Type == "BACK" && b.Currency == "EUR" &&
        b.MarketId == leg.MarketId && b.SelectionId == "58805" && b.StrategyName == LiveRoundCommand.Strategy &&
        b.Tipster.Equals(LiveRoundCommand.Provider, StringComparison.OrdinalIgnoreCase) &&
        b.Id == J.Text(order["betId"]) && b.StrategyId == J.Text(order["strategyId"]) &&
        b.Matched == (100 << index) / 100m && b.Unmatched == 0 && b.ProfitLoss == -b.Matched &&
        (double)b.AveragePrice == J.Number(order["odds"]) && b.Settled == J.Time(order["settledAt"]);

    private static void ValidateClosedRecovery(LiveRoundCommand previous, JsonObject state)
    {
        var count = J.Int(state["reservedCount"]);
        var orders = state["orders"] as JsonArray ?? throw new InvalidDataException("Faltan las reservas anteriores.");
        if (!J.Bool(state["terminal"]) || J.Text(state["status"]) != "review_reconciled" ||
            J.Text(state["requestId"]) != previous.Id || J.Text(state["fingerprint"]) != previous.Fingerprint ||
            count is < 1 or > 7 || count != orders.Count || count > previous.Legs.Count ||
            J.Int(state["spentCents"]) != 100 * ((1 << count) - 1) ||
            J.Text(state["evidence"]) != RecoverySignature(orders))
            throw new InvalidDataException("La ronda anterior todavía no tiene una conciliación completa y estable.");
        for (var i = 0; i < count; i++)
        {
            var order = J.Object(orders[i]); ValidateSettledLoss(order, i);
            if (J.Text(order["matchId"]) != previous.Legs[i].MatchId || J.Text(order["marketId"]) != previous.Legs[i].MarketId)
                throw new InvalidDataException("Las pérdidas conservadas no coinciden con el OK anterior.");
        }
    }

    private void KeepAudit(string name, byte[] content)
    {
        var audit = Path.Combine(folder, "recovery-audit"); Directory.CreateDirectory(audit);
        var hash = Convert.ToHexString(SHA256.HashData(content));
        var path = Path.Combine(audit, name + "-" + hash + ".backup");
        if (File.Exists(path))
        {
            if (!File.ReadAllBytes(path).SequenceEqual(content)) throw new InvalidDataException("La copia de auditoría cambió.");
            return;
        }
        using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read, 4096, FileOptions.WriteThrough);
        file.Write(content); file.Flush(true);
    }

    // Sólo conciliación. Este método nunca reserva órdenes ni publica un CSV.
    // La interfaz lo llama dos veces con al menos 15 segundos entre lecturas.
    public async Task<JsonObject> ReconcileReviewAsync(CancellationToken ct)
    {
        if (!readOnly) throw new InvalidOperationException("Conecta en Sólo comprobar historial para conciliar la revisión.");
        var command = await client.GetAsync(client.CommandPath, ct) ?? throw new InvalidDataException("Falta el OK de la ronda.");
        var snapshot = await client.GetAsync(client.StatePath, ct) ?? throw new InvalidDataException("Falta el estado de la ronda.");
        var c = LiveRoundCommand.Parse(command.Data); var state = snapshot.Data.DeepClone().AsObject();
        if (J.Optional(state["agentId"]) is string other && other != agentId && state["leaseUntil"] is not null && J.Time(state["leaseUntil"]) > Now)
            throw new InvalidOperationException("Otro PC controla esta ronda.");
        var count = J.Int(state["reservedCount"]);
        var orders = state["orders"] as JsonArray ?? throw new InvalidDataException("Faltan las reservas.");
        if (!J.Bool(state["terminal"]) || J.Text(state["status"]) != "review" || count is < 1 or > 7 ||
            count != orders.Count || count > c.Legs.Count || J.Text(state["requestId"]) != c.Id ||
            J.Text(state["fingerprint"]) != c.Fingerprint || J.Int(state["spentCents"]) != 100 * ((1 << count) - 1))
            throw new InvalidDataException("Sólo puede conciliarse una revisión con reservas conocidas y sin ampliar el gasto.");
        if (!File.Exists(ReceiptPath)) throw new InvalidDataException("Falta el recibo local; no se reconstruye ni se reinicia la ronda.");
        var receiptBytes = File.ReadAllBytes(ReceiptPath);
        var receipt = J.Object(JsonNode.Parse(receiptBytes));
        if (J.Text(receipt["requestId"]) != c.Id || J.Text(receipt["fingerprint"]) != c.Fingerprint ||
            J.Int(receipt["reservedCount"]) != count || !J.Bool(receipt["terminal"]) ||
            J.Canonical(receipt["orders"]) != J.Canonical(orders))
            throw new InvalidDataException("El recibo local y las reservas remotas no coinciden.");
        var history = BfHistory.Read(historyPath);
        if (history.Any(b => !b.Simulated && !b.Terminal))
            throw new InvalidDataException("Hay apuestas reales pendientes. No se cierra ni se recupera la ronda.");
        if (c.CarriedCount > 0) await VerifyRecoveryLinkAsync(c, state, ct);
        var reconciled = new JsonArray();
        string? strategy = null;
        for (var i = 0; i < count; i++)
        {
            var leg = c.Legs[i]; var order = J.Object(orders[i]).DeepClone().AsObject(); var cents = 100 << i;
            if (J.Int(order["cents"]) != cents || J.Text(order["matchId"]) != leg.MatchId || J.Text(order["marketId"]) != leg.MarketId)
                throw new InvalidDataException("La reserva no coincide con la autorización.");
            var matching = history.Where(b => !b.Simulated && b.Type == "BACK" && b.Currency == "EUR" && b.SelectionId == "58805" &&
                b.MarketId == leg.MarketId && b.StrategyName == LiveRoundCommand.Strategy &&
                b.Tipster.Equals(LiveRoundCommand.Provider, StringComparison.OrdinalIgnoreCase)).ToList();
            if (i < c.CarriedCount && matching.Count == 0)
            {
                ValidateSettledLoss(order, i); strategy ??= J.Text(order["strategyId"]); reconciled.Add(order); continue;
            }
            if (matching.Count != 1) throw new InvalidDataException("Falta una apuesta o hay varios BetId para la misma reserva. Revisión manual.");
            var b = matching[0];
            if (!b.Terminal || b.Matched != cents / 100m || b.Unmatched != 0 || b.ProfitLoss != -b.Matched ||
                b.AveragePrice < 2.8m || b.AveragePrice > 20 || b.Placed < J.Time(order["reservedAt"]).AddSeconds(-1) ||
                b.Placed >= leg.Kickoff.AddSeconds(-60) || b.Settled < b.Placed || b.Settled > Now ||
                (J.Optional(order["betId"]) is string id && id != b.Id) || (strategy is not null && strategy != b.StrategyId))
                throw new InvalidDataException($"BetId {b.Id}: no consta una pérdida completa y coherente. No se recupera.");
            strategy = b.StrategyId;
            order["betId"] = b.Id; order["strategyId"] = b.StrategyId; order["matchedCents"] = cents;
            order["odds"] = (double)b.AveragePrice; order["profitLossCents"] = -cents;
            order["status"] = "SETTLED"; order["settledAt"] = J.Iso(b.Settled!.Value); reconciled.Add(order);
        }
        var fixtures = await provider.EnrichAsync(c.Scope, await client.FixturesAsync(c.Scope, ct), Now, ct); c.CheckSchedule(fixtures);
        if (fixtures.Any(f => !ExcludedTeams.IsExcludedFixture(f) && f.Draw && !c.Baseline.Contains(f.Id)))
            throw new InvalidDataException("Hay un nuevo empate final en la jornada. Se conserva la ronda detenida; no se propone otra apuesta.");
        var signature = RecoverySignature(reconciled);
        var stable = J.Optional(state["evidence"]) == signature && state["evidenceAt"] is not null && Now - J.Time(state["evidenceAt"]) >= TimeSpan.FromSeconds(15);
        if (J.Optional(state["evidence"]) != signature || state["evidenceAt"] is null)
        { state["evidence"] = signature; state["evidenceAt"] = J.Iso(Now); }
        KeepAudit(c.Id + "-receipt", receiptBytes);
        state["orders"] = reconciled; state["status"] = stable ? "review_reconciled" : "review";
        state["message"] = stable
            ? $"Revisión conciliada: pérdida conservada {J.Int(state["spentCents"]) / 100m} €. Sin envíos. Revisa los partidos futuros y confirma un nuevo OK en el móvil; próximo importe {1 << count} €."
            : "Primera lectura completa de pérdidas. Esperando una segunda lectura estable; no se envían órdenes.";
        state["agentId"] = agentId; state["lastSeenAt"] = J.Iso(Now); state["leaseUntil"] = J.Iso(Now.AddSeconds(60));
        var current = await client.GetAsync(client.CommandPath, ct);
        if (current?.Version != command.Version) throw new InvalidDataException("Cambió la autorización durante la conciliación.");
        await client.PatchAsync(client.StatePath, state, snapshot.Version, false, ct); Persist(state); return state;
    }

    private async Task<(LiveRoundCommand Previous, JsonObject State)> RecoveryArchiveAsync(LiveRoundCommand c, CancellationToken ct)
    {
        var archive = await client.GetAsync(client.CommandPath + "/Archivo/" + c.ResumeFromRequestId, ct)
            ?? throw new InvalidDataException("Falta el archivo permanente de la recuperación.");
        var previous = LiveRoundCommand.Parse(J.Object(archive.Data["authorization"]));
        var state = J.Object(archive.Data["state"]); ValidateClosedRecovery(previous, state);
        if (previous.Id != c.ResumeFromRequestId || previous.Fingerprint != c.ResumeFromFingerprint || previous.Scope != c.Scope ||
            c.Approved <= previous.Approved || J.Int(state["reservedCount"]) != c.CarriedCount ||
            J.Int(state["spentCents"]) != c.CarriedSpentCents || !previous.Legs.Take(c.CarriedCount).SequenceEqual(c.Legs.Take(c.CarriedCount)))
            throw new InvalidDataException("El nuevo OK no conserva íntegros la ronda, el gasto y los partidos ya ejecutados.");
        return (previous, state);
    }

    private async Task VerifyRecoveryLinkAsync(LiveRoundCommand c, JsonObject state, CancellationToken ct)
    {
        var archive = await RecoveryArchiveAsync(c, ct);
        var orders = state["orders"] as JsonArray ?? throw new InvalidDataException("Faltan las reservas conservadas.");
        if (orders.Count < c.CarriedCount || J.Canonical(new JsonArray(orders.Take(c.CarriedCount).Select(n => n!.DeepClone()).ToArray())) != J.Canonical(archive.State["orders"]))
            throw new InvalidDataException("Las reservas conservadas cambiaron tras la recuperación.");
    }

    private async Task<JsonObject> AdoptRecoveryAsync(LiveRoundCommand c, JsonObject state, CancellationToken ct)
    {
        var archive = await RecoveryArchiveAsync(c, ct);
        if (J.Text(state["requestId"]) != archive.Previous.Id || J.Text(state["fingerprint"]) != archive.Previous.Fingerprint ||
            J.Canonical(state["orders"]) != J.Canonical(archive.State["orders"]))
            throw new InvalidDataException("El estado actual no coincide con el archivo de la ronda conciliada.");
        ValidateClosedRecovery(archive.Previous, state);
        var history = BfHistory.Read(historyPath);
        if (history.Any(b => !b.Simulated && !b.Terminal)) throw new InvalidDataException("Hay apuestas reales pendientes. No se recupera.");
        if (!File.Exists(ReceiptPath)) throw new InvalidDataException("Falta el recibo local de la ronda anterior.");
        var receiptBytes = File.ReadAllBytes(ReceiptPath); var receipt = J.Object(JsonNode.Parse(receiptBytes));
        if (J.Text(receipt["requestId"]) != archive.Previous.Id || J.Text(receipt["fingerprint"]) != archive.Previous.Fingerprint ||
            J.Canonical(receipt["orders"]) != J.Canonical(state["orders"]) || J.Text(receipt["status"]) != "review_reconciled")
            throw new InvalidDataException("El recibo local no confirma el cierre anterior.");
        KeepAudit(archive.Previous.Id + "-receipt", receiptBytes);
        if (File.Exists(OutboxPath))
        {
            var bytes = File.ReadAllBytes(OutboxPath);
            if (Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF') != LiveRoundCommand.Csv(archive.Previous.Legs[c.CarriedCount - 1], 100 << (c.CarriedCount - 1)))
                throw new InvalidDataException("El CSV anterior no coincide con la última reserva. No se reemplaza.");
            KeepAudit(archive.Previous.Id + "-csv", bytes); File.Delete(OutboxPath);
        }
        return new JsonObject { ["mode"] = "live-round-128-v1", ["requestId"] = c.Id, ["fingerprint"] = c.Fingerprint,
            ["reservedCount"] = c.CarriedCount, ["spentCents"] = c.CarriedSpentCents,
            ["orders"] = state["orders"]!.DeepClone(), ["terminal"] = false, ["agentId"] = agentId,
            ["lastSeenAt"] = J.Iso(Now), ["leaseUntil"] = J.Iso(Now.AddSeconds(60)) };
    }
}
