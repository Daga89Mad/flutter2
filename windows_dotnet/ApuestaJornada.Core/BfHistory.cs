using System.Globalization;
using System.IO.Compression;
using System.Xml;
using System.Xml.Linq;

namespace ApuestaJornada.Core;

public sealed record BfBet(string MarketId, string SelectionId, string StrategyId, string StrategyName,
    string Tipster, string Id, string Type, string Currency, bool Simulated, string Status,
    decimal Matched, decimal Unmatched, decimal AveragePrice, decimal ProfitLoss,
    DateTimeOffset Placed, DateTimeOffset? Settled)
{
    public bool Terminal => Status == "SETTLED" && Settled is not null && Unmatched == 0;
}

// Sólo lectura: nunca deserializa objetos CLR ni modifica los datos de BF Bot.
public static class BfHistory
{
    public static List<BfBet> Read(string path)
    {
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (file.Length > 16_000_000) throw new InvalidDataException("Historial comprimido demasiado grande.");
        using var gzip = new GZipStream(file, CompressionMode.Decompress);
        using var memory = new MemoryStream();
        var buffer = new byte[8192]; int count;
        while ((count = gzip.Read(buffer)) > 0)
        {
            memory.Write(buffer, 0, count);
            if (memory.Length > 32_000_000) throw new InvalidDataException("Historial descomprimido demasiado grande.");
        }
        memory.Position = 0;
        using var reader = XmlReader.Create(memory, new XmlReaderSettings
        { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 32_000_000 });
        var root = XDocument.Load(reader).Root;
        if (root?.Name != "ArrayOfBetHistoryItem") throw new InvalidDataException("Formato de historial BF Bot desconocido.");
        var bets = new List<BfBet>();
        foreach (var e in root.Elements())
        {
            if (e.Name != "BetHistoryItem") throw new InvalidDataException("Registro de historial desconocido.");
            string S(string k) => e.Elements(k).Count() == 1 ? e.Element(k)!.Value : throw new InvalidDataException("Falta/duplica " + k);
            decimal N(string k) => decimal.TryParse(S(k), NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out var d) ? d : throw new InvalidDataException("Importe no válido: " + k);
            var simulated = S("SimulatedBet") switch { "true" => true, "false" => false, _ => throw new InvalidDataException("SimulatedBet inválido.") };
            var settledText = e.Element("SettledDate")?.Value;
            var settled = string.IsNullOrWhiteSpace(settledText) || settledText.StartsWith("0001-") ? (DateTimeOffset?)null : J.Time(settledText);
            var bet = new BfBet(S("MarketId"), S("SelectionId"), S("StrategyID"), S("StrategyName"),
                S("Tipster"), S("BetId"), S("BetType"), S("Currency"), simulated, S("Status"),
                N("Matched"), N("Unmatched"), N("AvgPrice"), N("ProfitLoss"), J.Time(S("PlacedDate")), settled);
            if (bet.Matched < 0 || bet.Unmatched < 0 || string.IsNullOrWhiteSpace(bet.Id)) throw new InvalidDataException("Registro de apuesta incoherente.");
            bets.Add(bet);
        }
        if (bets.Select(b => b.Id).Distinct().Count() != bets.Count) throw new InvalidDataException("BetId duplicado en historial.");
        return bets;
    }
}
