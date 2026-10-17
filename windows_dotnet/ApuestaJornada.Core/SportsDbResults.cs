using System.Net.Http.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace ApuestaJornada.Core;

public interface IResultsProvider
{ Task<List<Fixture>> EnrichAsync(string scope, List<Fixture> fixtures, DateTimeOffset now, CancellationToken ct); }

public sealed class SportsDbResults : IResultsProvider, IDisposable
{
    private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private readonly Dictionary<string, (DateTimeOffset At, JsonArray Events)> cache = [];
    private static string Key(string home, string away) => Normalize(home) + "\0" + Normalize(away);
    private static string Normalize(string s) => Regex.Replace(s.Trim().ToLowerInvariant(), @"\s+", " ");
    public async Task<List<Fixture>> EnrichAsync(string scope, List<Fixture> fixtures, DateTimeOffset now, CancellationToken ct)
    {
        JsonArray events;
        if (cache.TryGetValue(scope, out var cached) && now >= cached.At && now - cached.At < TimeSpan.FromSeconds(60)) events = cached.Events;
        else
        {
            var parts = scope.Split('/');
            var url = $"https://www.thesportsdb.com/api/v1/json/123/eventsround.php?id=4335&r={Uri.EscapeDataString(parts[2])}&s={Uri.EscapeDataString(parts[1])}";
            var data = await FirebaseClient.ResponseAsync(await http.GetAsync(url, ct), ct);
            events = data["events"] as JsonArray ?? throw new InvalidDataException("El proveedor no devolvió los partidos.");
            if (events.Count != 10) throw new InvalidDataException("El proveedor no confirmó los diez partidos. Se bloquean nuevos ensayos.");
            cache[scope] = (now, events);
        }
        return Match(fixtures, events);
    }
    public static List<Fixture> Match(List<Fixture> fixtures, JsonArray events)
    {
        if (fixtures.Count != 10 || events.Count != 10) throw new InvalidDataException("Calendario incompleto.");
        var actual = events.Select(J.Object).ToDictionary(e => Key(J.Text(e["strHomeTeam"]), J.Text(e["strAwayTeam"])));
        if (actual.Count != 10) throw new InvalidDataException("Equipos duplicados.");
        return fixtures.Select(m =>
        {
            if (!actual.TryGetValue(Key(m.Home, m.Away), out var e)) throw new InvalidDataException("Los equipos no coinciden con el proveedor.");
            var status = J.Optional(e["strStatus"])?.Trim().ToLowerInvariant() ?? "";
            var stamp = J.Optional(e["strTimestamp"]);
            if (string.IsNullOrEmpty(stamp))
            {
                var day = J.Optional(e["dateEvent"]); var hour = J.Optional(e["strTime"]);
                if (string.IsNullOrEmpty(day) || string.IsNullOrEmpty(hour)) throw new InvalidDataException("El proveedor no confirmó todos los horarios.");
                stamp = day + "T" + hour;
            }
            if (!Regex.IsMatch(stamp, @"(Z|[+-]\d{2}:?\d{2})$", RegexOptions.IgnoreCase)) stamp += "Z";
            return m with { Kickoff = J.Time(stamp), Finished = J.Finals.Contains(status), HomeGoals = J.Score(e["intHomeScore"]), AwayGoals = J.Score(e["intAwayScore"]), Unavailable = J.Unavailable.Contains(status) };
        }).ToList();
    }
    public void Dispose() => http.Dispose();
}
