using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace ApuestaJornada.Core;

public static class J
{
    public static JsonObject Object(JsonNode? n) => n as JsonObject ?? throw new InvalidDataException("Objeto no válido.");
    public static string Text(JsonNode? n) => n?.GetValue<string>() ?? throw new InvalidDataException("Falta un texto requerido.");
    public static string? Optional(JsonNode? n) => n?.GetValue<string>();
    public static int Int(JsonNode? n) => int.TryParse(n?.ToJsonString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
        ? value : throw new InvalidDataException("Falta un entero requerido.");
    public static double Number(JsonNode? n) => double.TryParse(n?.ToJsonString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
        ? value : throw new InvalidDataException("Falta un número requerido.");
    public static bool Bool(JsonNode? n) => n?.GetValue<bool>() == true;
    public static DateTimeOffset Time(JsonNode? n) => Time(Text(n));
    public static DateTimeOffset Time(string s)
    {
        if (!Regex.IsMatch(s, @"(Z|[+-]\d{2}:?\d{2})$", RegexOptions.IgnoreCase) ||
            !DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out var value))
            throw new InvalidDataException("La fecha debe incluir zona horaria.");
        return value.ToUniversalTime();
    }
    public static string Iso(DateTimeOffset t) => t.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", CultureInfo.InvariantCulture);
    public static string Canonical(JsonNode? node) => Normalize(node)?.ToJsonString() ?? "null";
    private static JsonNode? Normalize(JsonNode? n) => n switch
    {
        JsonObject o => new JsonObject(o.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => KeyValuePair.Create(p.Key, Normalize(p.Value)))),
        JsonArray a => new JsonArray(a.Select(Normalize).ToArray()),
        _ => n?.DeepClone()
    };
    public static int? Score(JsonNode? n)
    {
        var s = n?.ToString();
        return int.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var i) && i >= 0 ? i : null;
    }
    public static readonly HashSet<string> Finals = ["ft", "match finished", "full time", "finalizado"];
    public static readonly HashSet<string> Unavailable = ["postponed", "cancelled", "canceled", "aplazado", "cancelado", "pst", "canc"];
}

public record Fixture(string Id, string Home, string Away, DateTimeOffset? Kickoff,
    bool Finished = false, int? HomeGoals = null, int? AwayGoals = null, bool Unavailable = false)
{
    public bool Final => Finished && HomeGoals.HasValue && AwayGoals.HasValue;
    public bool Draw => Final && HomeGoals == AwayGoals;
    public Fixture ScheduleOnly() => this with { Finished = false, HomeGoals = null, AwayGoals = null };
    public static Fixture FromDocument(string id, JsonObject d)
    {
        var status = J.Optional(d["Estado"])?.Trim().ToLowerInvariant() ?? "";
        return new(id, J.Optional(d["Local"]) ?? "", J.Optional(d["Visitante"]) ?? "",
            d["InicioUTC"] is null ? null : J.Time(d["InicioUTC"]),
            J.Bool(d["Finalizado"]) || J.Finals.Contains(status), J.Score(d["GolesLocal"]),
            J.Score(d["GolesVisitante"]), J.Unavailable.Contains(status));
    }
}

public record Bet(string MatchId, string Label, int Cents, double Odds, DateTimeOffset ApprovedAt)
{
    public JsonObject ToJson() => new() { ["mode"] = "simulation", ["matchId"] = MatchId, ["label"] = Label,
        ["cents"] = Cents, ["odds"] = Odds, ["approvedAt"] = J.Iso(ApprovedAt) };
    public static Bet Parse(JsonNode? node)
    {
        var d = J.Object(node);
        var b = new Bet(J.Text(d["matchId"]), J.Text(d["label"]), J.Int(d["cents"]),
            J.Number(d["odds"]), J.Time(d["approvedAt"]));
        if (J.Text(d["mode"]) != "simulation" || string.IsNullOrWhiteSpace(b.MatchId) ||
            !Enumerable.Range(0, 9).Any(i => b.Cents == 100 * (1 << i)) || !double.IsFinite(b.Odds) || b.Odds < 2.8)
            throw new InvalidDataException("Historial de ensayo no válido.");
        return b;
    }
    public static List<Bet> List(JsonNode? node) => node is JsonArray a ? a.Select(Parse).ToList() : throw new InvalidDataException("Historial no válido.");
}

public record Authorization(string Scope, List<Fixture> Schedule, HashSet<string> Selected, int Budget,
    double Odds, DateTimeOffset Approved, DateTimeOffset Expires)
{
    public static Authorization Parse(JsonNode? node)
    {
        var d = J.Object(node);
        var scope = J.Text(d["scope"]);
        if (J.Text(d["mode"]) != "round-simulation-v1" || !Regex.IsMatch(scope, @"^LaLiga/\d{4}-\d{4}/([1-9]|[12]\d|3[0-8])$"))
            throw new InvalidDataException("Solo se admite un ensayo de LaLiga válido.");
        var years = scope.Split('/')[1].Split('-');
        if (int.Parse(years[1], CultureInfo.InvariantCulture) != int.Parse(years[0], CultureInfo.InvariantCulture) + 1)
            throw new InvalidDataException("Temporada no válida.");
        var budget = J.Int(d["budgetCents"]);
        var odds = J.Number(d["rehearsalOdds"]);
        var rows = JsonNode.Parse(J.Text(d["schedule"])) as JsonArray ?? throw new InvalidDataException("Falta el calendario.");
        if (rows.Count != 10 || budget is < 100 or > 51100 || !double.IsFinite(odds) || odds < 2.8)
            throw new InvalidDataException("Calendario, cuota o presupuesto no válidos.");
        var schedule = rows.Select(n =>
        {
            if (n is not JsonArray row || row.Count != 5) throw new InvalidDataException("Calendario no válido.");
            return new Fixture(J.Text(row[0]), J.Text(row[1]), J.Text(row[2]), row[3] is null ? null : J.Time(row[3]), Unavailable: row[4]!.GetValue<bool>());
        }).OrderBy(m => m.Id, StringComparer.Ordinal).ToList();
        if (schedule.Select(m => m.Id).Distinct().Count() != 10 || schedule.Any(m => string.IsNullOrWhiteSpace(m.Id) || string.IsNullOrWhiteSpace(m.Home) || string.IsNullOrWhiteSpace(m.Away)))
            throw new InvalidDataException("Equipos o identificadores duplicados o vacíos.");
        var ids = (d["selectedIds"] as JsonArray ?? throw new InvalidDataException("Faltan las elecciones.")).Select(J.Text).ToList();
        var selected = ids.ToHashSet(StringComparer.Ordinal);
        if (ids.Count == 0 || ids.Count != selected.Count || selected.Any(id => schedule.All(m => m.Id != id)))
            throw new InvalidDataException("Selecciones no válidas.");
        var times = schedule.Where(m => selected.Contains(m.Id)).Select(m => m.Kickoff ?? throw new InvalidDataException("Falta un horario.")).Order().ToList();
        if (times.Zip(times.Skip(1)).Any(pair => pair.Second - pair.First < TimeSpan.FromMinutes(120)))
            throw new InvalidDataException("Las selecciones se solapan.");
        var approved = J.Time(d["approvedAt"]);
        var expires = J.Time(d["expiresAt"]);
        if (expires <= approved) throw new InvalidDataException("Caducidad no válida.");
        return new(scope, schedule, selected, budget, odds, approved, expires);
    }
}
