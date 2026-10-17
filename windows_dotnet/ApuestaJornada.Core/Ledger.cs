using System.Text.Json.Nodes;

namespace ApuestaJornada.Core;

public sealed class Ledger
{
    private readonly string folder;
    public Ledger(string folder) { this.folder = folder; Directory.CreateDirectory(folder); }
    private string FileFor(string id) => System.Text.RegularExpressions.Regex.IsMatch(id, "^[a-f0-9]{32}$")
        ? Path.Combine(folder, id + ".json") : throw new InvalidDataException("Identificador no válido.");
    public JsonObject? Read(string id) => File.Exists(FileFor(id)) ? J.Object(JsonNode.Parse(File.ReadAllText(FileFor(id)))) : null;
    private void Save(string id, JsonObject data)
    {
        var path = FileFor(id);
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var f = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { var bytes = System.Text.Encoding.UTF8.GetBytes(data.ToJsonString()); f.Write(bytes); f.Flush(true); }
            File.Move(temp, path, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public static void Validate(IReadOnlyList<Bet> bets)
    {
        if (bets.Count > 9 || bets.Select(b => b.MatchId).Distinct().Count() != bets.Count || bets.Where((b, i) => b.Cents != 100 * (1 << i)).Any())
            throw new InvalidDataException("Progresión del historial no válida.");
        foreach (var bet in bets) Bet.Parse(bet.ToJson());
    }
    public void Initialize(string id, string fingerprint, IReadOnlyList<Bet> initial)
    {
        Validate(initial);
        var existing = Read(id);
        if (existing is not null)
        {
            if (J.Text(existing["fingerprint"]) != fingerprint) throw new InvalidDataException("Se modificó el OK existente. Requiere una nueva autorización.");
            return;
        }
        Save(id, new() { ["fingerprint"] = fingerprint, ["terminal"] = null, ["bets"] = Array(initial) });
    }
    public List<Bet> Bets(string id) { var bets = Bet.List(Read(id)!["bets"]); Validate(bets); return bets; }
    public string? Terminal(string id) => J.Optional(Read(id)?["terminal"]);
    public void Terminate(string id, string reason)
    { var data = Read(id) ?? throw new InvalidDataException("Falta la sesión."); data["terminal"] = reason; Save(id, data); }
    public bool Insert(string id, Bet bet)
    {
        var data = Read(id) ?? throw new InvalidDataException("Falta la sesión.");
        var bets = Bet.List(data["bets"]);
        if (bets.Any(b => b.MatchId == bet.MatchId)) return false;
        bets.Add(bet); Validate(bets); data["bets"] = Array(bets); Save(id, data); return true;
    }
    public static JsonArray Array(IEnumerable<Bet> bets) => new(bets.Select(b => (JsonNode)b.ToJson()).ToArray());
}
