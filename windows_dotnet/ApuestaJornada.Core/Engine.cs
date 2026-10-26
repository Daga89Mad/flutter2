namespace ApuestaJornada.Core;

public record Decision(string Status, string Message, Fixture? Match = null, int Cents = 100);

public static class Engine
{
    public static Decision Decide(Authorization auth, IReadOnlyList<Fixture> fixtures, IReadOnlyList<Bet> bets, DateTimeOffset now)
    {
        Decision Stop(string message) => new("stopped", message);
        Decision Wait(string message, int cents = 100) => new("waiting", message, Cents: cents);
        if (now < auth.Approved || now >= auth.Expires) return Stop("Autorización caducada o reloj incorrecto. Requiere otro OK.");
        if (!fixtures.Select(m => m.ScheduleOnly()).OrderBy(m => m.Id, StringComparer.Ordinal).SequenceEqual(auth.Schedule))
            return Stop("Cambió el calendario. Revisa la jornada y autoriza de nuevo.");
        if (auth.BaselineFinishedIds.Any(id => !fixtures.Any(m => m.Id == id && m.Final))) return Stop("Un resultado previo dejó de estar confirmado. Revisa y autoriza de nuevo.");
        if (bets.Any(b => auth.BaselineFinishedIds.Contains(b.MatchId) || (auth.FromNow && b.ApprovedAt < auth.Approved))) return Stop("El historial incluye partidos anteriores al nuevo OK.");
        if (fixtures.Any(m => !ExcludedTeams.IsExcludedFixture(m) && m.Draw && !auth.BaselineFinishedIds.Contains(m.Id))) return Stop("Jornada detenida: ya hay un empate final.");
        var byId = fixtures.ToDictionary(m => m.Id);
        var seen = new HashSet<string>();
        int cents = 100, spent = 0;
        foreach (var b in bets)
        {
            if (!byId.TryGetValue(b.MatchId, out var match) || !seen.Add(b.MatchId) || b.Cents != cents || b.ApprovedAt > now || !double.IsFinite(b.Odds) || b.Odds < 2.8)
                return Stop("El historial no coincide con la progresión autorizada.");
            spent += cents;
            if (!match.Final) return Wait("Esperando resultado final del ensayo anterior.");
            cents *= 2;
        }
        if (cents > 25600) return Stop("Alcanzado el límite de 256 €. La próxima jornada empieza en 1 €.");
        var remaining = fixtures.Where(m => !ExcludedTeams.IsExcludedFixture(m) && !auth.BaselineFinishedIds.Contains(m.Id) && !m.Final && !m.Unavailable).OrderBy(m => m.Kickoff).ThenBy(m => m.Id, StringComparer.Ordinal).ToList();
        if (remaining.Count == 0) return Stop("Jornada terminada.");
        if (remaining.Any(m => m.Kickoff is null)) return Wait("Faltan horarios fiables.");
        if (remaining.Any(m => m.Kickoff <= now)) return Wait("Hay encuentros iniciados sin resultado final confirmado.");
        if (auth.PreviousSpentCents + spent + cents > auth.Budget) return Stop("Presupuesto acumulado de la jornada alcanzado.");
        var end = remaining[0].Kickoff!.Value.AddMinutes(120);
        var chosen = remaining.Where(m => m.Kickoff < end && auth.Selected.Contains(m.Id)).ToList();
        if (chosen.Count != 1) return Wait("Esperando el siguiente partido elegido.");
        var next = chosen[0];
        if (next.Kickoff - now > TimeSpan.FromMinutes(5)) return Wait($"Esperando los cinco minutos previos a {next.Home} — {next.Away}.", cents);
        return new("ready", "Preparada para simular. Ninguna orden real.", next, cents);
    }
}
