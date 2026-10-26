using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace ApuestaJornada.Core;

/// <summary>
/// Equipos vetados en la estrategia de LaLiga. Compara nombres completos
/// normalizados, no prefijos: "Barcelona Atlètic" y "Real Madrid Castilla"
/// siguen siendo equipos distintos y no deben confundirse con los principales.
/// </summary>
public static class ExcludedTeams
{
    private static readonly HashSet<string> Names = new HashSet<string>(StringComparer.Ordinal)
    {
        "real madrid", "real madrid cf", "real madrid c f", "real madrid club de futbol",
        "fc barcelona", "f c barcelona", "barcelona", "barca", "barca fc", "barcelona fc",
        "club atletico de madrid", "club atletico madrid", "atletico de madrid",
        "atletico madrid", "atletico de madrid sad", "atletico madrid sad"
    };

    public static bool IsExcluded(string? teamName) =>
        !string.IsNullOrWhiteSpace(teamName) && Names.Contains(Normalize(teamName));

    public static bool IsExcludedFixture(Fixture fixture) =>
        IsExcludedFixture(fixture.Home, fixture.Away);

    public static bool IsExcludedFixture(string home, string away) =>
        IsExcluded(home) || IsExcluded(away);

    private static string Normalize(string name)
    {
        string decomposed = name.Trim().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        bool pendingSpace = false;
        foreach (char c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark)
                continue;
            if (char.IsLetterOrDigit(c))
            {
                if (pendingSpace && sb.Length > 0) sb.Append(' ');
                sb.Append(char.ToLowerInvariant(c));
                pendingSpace = false;
            }
            else
            {
                pendingSpace = true;
            }
        }
        return sb.ToString();
    }
}
