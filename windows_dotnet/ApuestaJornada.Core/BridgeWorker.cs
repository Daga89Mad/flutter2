using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace ApuestaJornada.Core;

public sealed class BridgeWorker(IBridgeClient client, Ledger ledger, IResultsProvider provider, string agentId, Func<DateTimeOffset>? clock = null)
{
    private DateTimeOffset Now => clock?.Invoke() ?? DateTimeOffset.UtcNow;
    public async Task<JsonObject> TickAsync(CancellationToken ct)
    {
        try { return await RunAsync(ct); }
        catch (Exception e) when (!(e is OperationCanceledException && ct.IsCancellationRequested))
        {
            try
            {
                var old = await client.GetAsync(client.StatePath, ct);
                if (old is not null && J.Optional(old.Data["agentId"]) == agentId)
                {
                    old.Data["status"] = "blocked";
                    old.Data["message"] = "En espera: " + e.Message;
                    await client.PatchAsync(client.StatePath, old.Data, old.Version, false, ct);
                }
            }
            catch (Exception) { /* Sin red: no registrar otro ensayo. El móvil detecta señal caducada. */ }
            throw;
        }
    }
    private async Task<(JsonObject? Previous, string Version)> ClaimAsync(CancellationToken ct)
    {
        var previous = await client.GetAsync(client.StatePath, ct);
        var data = previous?.Data.DeepClone().AsObject() ?? new JsonObject();
        var now = Now;
        if (J.Optional(data["agentId"]) is string agent && agent != agentId && data["leaseUntil"] is not null && J.Time(data["leaseUntil"]) > now)
            throw new InvalidOperationException("Otro PC tiene el ensayo activo. Ciérralo y espera un minuto.");
        data["mode"] = "simulation"; data["agentId"] = agentId;
        data["lastSeenAt"] = J.Iso(now); data["leaseUntil"] = J.Iso(now.AddSeconds(60));
        var version = await client.PatchAsync(client.StatePath, data, previous?.Version, previous is null, ct);
        return (previous?.Data, version);
    }
    private async Task<JsonObject> RunAsync(CancellationToken ct)
    {
        var command = await client.GetAsync(client.CommandPath, ct);
        var (previous, version) = await ClaimAsync(ct);
        var state = new JsonObject { ["mode"] = "simulation", ["agentId"] = agentId,
            ["lastSeenAt"] = J.Iso(Now), ["leaseUntil"] = J.Iso(Now.AddSeconds(60)),
            ["requestId"] = "", ["scope"] = "", ["status"] = "idle", ["message"] = "Conectado. Esperando el OK del móvil.",
            ["bets"] = new JsonArray(), ["results"] = new JsonObject(), ["spentCents"] = 0 };
        var bets = new List<Bet>();
        if (command is not null)
        {
            var c = command.Data;
            var schema = J.Int(c["schema"]);
            if (schema is not (1 or 2) || J.Text(c["mode"]) != "simulation") throw new InvalidDataException("Solo se admiten ensayos de la app.");
            var id = J.Text(c["requestId"]);
            if (!Regex.IsMatch(id, "^[a-f0-9]{32}$")) throw new InvalidDataException("Identificador de autorización no válido.");
            var auth = Authorization.Parse(c["authorization"]);
            if ((schema == 2) != auth.FromNow) throw new InvalidDataException("La versión del OK no coincide con el protocolo.");
            if (J.Text(c["scope"]) != auth.Scope) throw new InvalidDataException("La jornada no coincide con el OK.");
            state["requestId"] = id; state["scope"] = auth.Scope;
            var same = previous is not null && J.Optional(previous["requestId"]) == id;
            if (same) state["results"] = previous!["results"]?.DeepClone() ?? new JsonObject();
            var immutable = new JsonObject { ["scope"] = c["scope"]?.DeepClone(), ["authorization"] = c["authorization"]?.DeepClone(), ["initialBets"] = c["initialBets"]?.DeepClone() };
            var fingerprint = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(J.Canonical(immutable))));
            var initial = Bet.List(c["initialBets"]);
            if (auth.FromNow && initial.Count != 0) throw new InvalidDataException("Un nuevo ensayo empieza sin apuestas previas; el gasto anterior se conserva por separado.");
            var remote = same && previous!["bets"] is JsonArray ? Bet.List(previous["bets"]) : initial;
            Ledger.Validate(remote);
            if (remote.Count < initial.Count || !remote.Take(initial.Count).SequenceEqual(initial)) throw new InvalidDataException("El historial remoto no conserva el historial autorizado.");
            ledger.Initialize(id, fingerprint, remote);
            bets = ledger.Bets(id);
            if (!bets.Take(Math.Min(bets.Count, remote.Count)).SequenceEqual(remote.Take(Math.Min(bets.Count, remote.Count))))
                throw new InvalidDataException("Los historiales local y remoto no coinciden.");
            foreach (var missing in remote.Skip(bets.Count)) if (!ledger.Insert(id, missing)) throw new InvalidDataException("Historial remoto duplicado.");
            bets = ledger.Bets(id);
            if (same && J.Optional(previous!["status"]) is "stopped" or "revoked") ledger.Terminate(id, J.Optional(previous["message"]) ?? "Ensayo detenido.");
            var action = J.Text(c["action"]);
            if (action is not ("authorize" or "revoke")) throw new InvalidDataException("Acción desconocida.");
            if (action == "revoke") ledger.Terminate(id, "Autorización revocada desde el móvil.");
            var terminal = ledger.Terminal(id);
            if (terminal is not null)
            { state["status"] = action == "revoke" ? "revoked" : "stopped"; state["message"] = terminal; }
            else
            {
                var fixtures = await provider.EnrichAsync(auth.Scope, await client.FixturesAsync(auth.Scope, ct), Now, ct);
                state["results"] = new JsonObject(fixtures.Select(m => KeyValuePair.Create<string, JsonNode?>(m.Id,
                    new JsonObject { ["finished"] = m.Final, ["homeGoals"] = m.HomeGoals, ["awayGoals"] = m.AwayGoals })));
                var plan = Engine.Decide(auth, fixtures, bets, Now);
                if (plan.Status == "ready")
                {
                    // Renovar primero; la lectura final del OK queda junto al registro.
                    var renewed = await ClaimAsync(ct); version = renewed.Version;
                    var current = await client.GetAsync(client.CommandPath, ct);
                    if (current is null || current.Version != command.Version || J.Optional(current.Data["action"]) != "authorize")
                        plan = new("waiting", "Cambió la autorización. Se revisará antes de continuar.");
                    else
                    {
                        plan = Engine.Decide(auth, fixtures, bets, Now);
                        ct.ThrowIfCancellationRequested();
                        if (plan.Status == "ready")
                        {
                            var match = plan.Match!;
                            var bet = new Bet(match.Id, $"{match.Home} — {match.Away}", plan.Cents, auth.Odds, Now);
                            if (!ledger.Insert(id, bet)) throw new InvalidDataException("Ensayo ya registrado; se bloquea el reintento.");
                            bets = ledger.Bets(id);
                            plan = new("waiting", $"Ensayo registrado: {bet.Label} · {bet.Cents / 100.0:0.00} €. Esperando resultado final.");
                        }
                    }
                }
                if (plan.Status == "stopped") ledger.Terminate(id, plan.Message);
                state["status"] = plan.Status; state["message"] = plan.Message;
            }
            if (auth.FromNow) state["message"] = $"Desde ahora · {auth.BaselineFinishedIds.Count} partidos anteriores fuera del ensayo · {auth.PreviousSpentCents / 100.0:0.00} € simulados previamente. " + J.Text(state["message"]);
        }
        state["bets"] = Ledger.Array(bets); state["spentCents"] = bets.Sum(b => b.Cents);
        state["lastSeenAt"] = J.Iso(Now); state["leaseUntil"] = J.Iso(Now.AddSeconds(60));
        await client.PatchAsync(client.StatePath, state, version, false, ct);
        return state;
    }
}
