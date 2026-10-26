using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;

namespace ApuestaJornada.Core;

public record Document(JsonObject Data, string Version);
public interface IBridgeClient
{
    string CommandPath { get; }
    string StatePath { get; }
    Task<Document?> GetAsync(string path, CancellationToken ct);
    Task<string> PatchAsync(string path, JsonObject data, string? expected, bool create, CancellationToken ct);
    Task<List<Fixture>> FixturesAsync(string scope, CancellationToken ct);
}

public sealed class ApiException(int status, string message) : Exception($"HTTP {status}: {message}")
{ public int Status { get; } = status; }

public sealed class FirebaseClient : IBridgeClient, IDisposable
{
    public const string Project = "login-d2344";
    public const string ApiKey = "AIzaSyDeCVnwUNW-wiBHM_n5lp3D8b6qZuRlKT4"; // Configuración pública de la app.
    private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private string? token, refresh;
    private DateTimeOffset expires;
    public string Uid { get; private set; } = "";
    public bool UseLivePilot { get; set; }
    public bool UseLiveRound { get; set; }
    public string CommandPath => UseLiveRound ? $"PuenteJornadaRondaReal/{Uid}" : UseLivePilot ? $"PuenteJornadaReal/{Uid}" : $"PuenteJornada/{Uid}";
    public string StatePath => CommandPath + "/Estado/actual";

    public static async Task<JsonObject> ResponseAsync(HttpResponseMessage response, CancellationToken ct)
    {
        using (response)
        {
            var raw = await response.Content.ReadAsStringAsync(ct);
            JsonObject? data;
            try { data = JsonNode.Parse(raw) as JsonObject; }
            catch (System.Text.Json.JsonException) { data = null; }
            if (!response.IsSuccessStatusCode)
            {
                var message = data?["error"] is JsonObject e ? J.Optional(e["message"]) : null;
                message ??= "Solicitud rechazada. Comprueba conexión, cuenta y reglas de Firebase.";
                throw new ApiException((int)response.StatusCode, message[..Math.Min(message.Length, 240)]);
            }
            return data ?? throw new InvalidDataException("Respuesta del servidor no válida.");
        }
    }
    public async Task SignInAsync(string email, string password, CancellationToken ct)
    {
        var data = await ResponseAsync(await http.PostAsJsonAsync("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + ApiKey,
            new { email, password, returnSecureToken = true }, ct), ct);
        Uid = J.Text(data["localId"]); token = J.Text(data["idToken"]); refresh = J.Text(data["refreshToken"]);
        expires = DateTimeOffset.UtcNow.AddSeconds(int.Parse(J.Text(data["expiresIn"]), CultureInfo.InvariantCulture) - 90);
    }
    private async Task AuthorizeAsync(HttpRequestMessage request, CancellationToken ct)
    {
        if (token is null) throw new InvalidOperationException("Inicia sesión con la cuenta de la app.");
        if (DateTimeOffset.UtcNow >= expires)
        {
            var form = new FormUrlEncodedContent(new Dictionary<string, string> { ["grant_type"] = "refresh_token", ["refresh_token"] = refresh! });
            var d = await ResponseAsync(await http.PostAsync("https://securetoken.googleapis.com/v1/token?key=" + ApiKey, form, ct), ct);
            if (J.Text(d["user_id"]) != Uid) throw new InvalidDataException("Cambió el usuario de la sesión.");
            token = J.Text(d["id_token"]); refresh = J.Text(d["refresh_token"]);
            expires = DateTimeOffset.UtcNow.AddSeconds(int.Parse(J.Text(d["expires_in"]), CultureInfo.InvariantCulture) - 90);
        }
        request.Headers.Authorization = new("Bearer", token);
    }
    private static string Url(string path) => $"https://firestore.googleapis.com/v1/projects/{Project}/databases/(default)/documents/" + string.Join('/', path.Split('/').Select(Uri.EscapeDataString));
    public async Task<Document?> GetAsync(string path, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, Url(path));
        await AuthorizeAsync(request, ct);
        try
        {
            var d = await ResponseAsync(await http.SendAsync(request, ct), ct);
            return new(DecodeFields(J.Object(d["fields"] ?? new JsonObject())), J.Text(d["updateTime"]));
        }
        catch (ApiException e) when (e.Status == (int)HttpStatusCode.NotFound) { return null; }
    }
    public async Task<string> PatchAsync(string path, JsonObject data, string? expected, bool create, CancellationToken ct)
    {
        var query = expected is not null ? "?currentDocument.updateTime=" + Uri.EscapeDataString(expected) : create ? "?currentDocument.exists=false" : "";
        using var request = new HttpRequestMessage(HttpMethod.Patch, Url(path) + query) { Content = JsonContent.Create(new JsonObject { ["fields"] = EncodeFields(data) }) };
        await AuthorizeAsync(request, ct);
        var result = await ResponseAsync(await http.SendAsync(request, ct), ct);
        return J.Text(result["updateTime"]);
    }
    public async Task<List<Fixture>> FixturesAsync(string scope, CancellationToken ct)
    {
        var parts = scope.Split('/');
        var path = "LaLiga/Resultados/" + (parts[1] == "2025-2026" ? "" : $"Temporadas/{parts[1]}/") + $"Jornadas/{parts[2]}/Partidos";
        var fixtures = new List<Fixture>(); string? page = null;
        do
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, Url(path) + "?pageSize=100" + (page is null ? "" : "&pageToken=" + Uri.EscapeDataString(page)));
            await AuthorizeAsync(request, ct);
            var data = await ResponseAsync(await http.SendAsync(request, ct), ct);
            foreach (var node in data["documents"] as JsonArray ?? [])
            {
                var d = J.Object(node);
                fixtures.Add(Fixture.FromDocument(J.Text(d["name"]).Split('/')[^1], DecodeFields(J.Object(d["fields"]))));
            }
            if (fixtures.Count > 10) throw new InvalidDataException("La jornada contiene más de diez partidos.");
            page = J.Optional(data["nextPageToken"]);
        } while (!string.IsNullOrEmpty(page));
        return fixtures;
    }
    public static JsonObject EncodeFields(JsonObject data) => new(data.Select(p => KeyValuePair.Create<string, JsonNode?>(p.Key,
        p.Key is "lastSeenAt" or "leaseUntil" or "approvedAt" or "expiresAt" or "kickoff" ? new JsonObject { ["timestampValue"] = J.Text(p.Value) } : Encode(p.Value))));
    public static JsonNode Encode(JsonNode? n)
    {
        if (n is null) return new JsonObject { ["nullValue"] = null };
        if (n is JsonObject o) return new JsonObject { ["mapValue"] = new JsonObject { ["fields"] = new JsonObject(o.Select(p => KeyValuePair.Create<string, JsonNode?>(p.Key, Encode(p.Value)))) } };
        if (n is JsonArray a) return new JsonObject { ["arrayValue"] = new JsonObject { ["values"] = new JsonArray(a.Select(Encode).ToArray()) } };
        var v = (JsonValue)n;
        if (v.TryGetValue<bool>(out var boolean)) return new JsonObject { ["booleanValue"] = boolean };
        if (v.TryGetValue<string>(out var text)) return new JsonObject { ["stringValue"] = text };
        if (v.TryGetValue<int>(out var integer)) return new JsonObject { ["integerValue"] = integer.ToString(CultureInfo.InvariantCulture) };
        if (v.TryGetValue<long>(out var big)) return new JsonObject { ["integerValue"] = big.ToString(CultureInfo.InvariantCulture) };
        var number = v.GetValue<double>();
        if (!double.IsFinite(number)) throw new InvalidDataException("Número no finito.");
        return new JsonObject { ["doubleValue"] = number };
    }
    public static JsonObject DecodeFields(JsonObject fields) => new(fields.Select(p => KeyValuePair.Create(p.Key, Decode(J.Object(p.Value)))));
    public static JsonNode? Decode(JsonObject d)
    {
        if (d.ContainsKey("nullValue")) return null;
        foreach (var key in new[] { "stringValue", "booleanValue", "timestampValue", "doubleValue" }) if (d.ContainsKey(key)) return d[key]?.DeepClone();
        if (d.ContainsKey("integerValue")) return JsonValue.Create(long.Parse(J.Text(d["integerValue"]), CultureInfo.InvariantCulture));
        if (d["arrayValue"] is JsonObject a) return new JsonArray((a["values"] as JsonArray ?? []).Select(n => Decode(J.Object(n))).ToArray());
        if (d["mapValue"] is JsonObject m) return DecodeFields(J.Object(m["fields"] ?? new JsonObject()));
        throw new InvalidDataException("Campo Firestore no compatible.");
    }
    public void Dispose() { token = refresh = null; http.Dispose(); }
}

