using System.ComponentModel;
using System.IO;
using System.Net.Http;
using System.Text.Json.Nodes;
using System.Windows;
using ApuestaJornada.Core;

namespace ApuestaJornada.Windows;

public partial class MainWindow : Window
{
    private CancellationTokenSource? cancellation;
    private Task? running;
    private bool closing, canClose;
    public MainWindow() => InitializeComponent();

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        if (running is { IsCompleted: false }) return;
        var mail = Email.Text.Trim(); var password = Password.Password;
        if (mail.Length == 0 || password.Length == 0) { Status.Text = "Introduce el correo y la contraseña de la app."; return; }
        cancellation = new(); Connect.IsEnabled = Email.IsEnabled = Password.IsEnabled = false; Stop.IsEnabled = true;
        Password.Clear(); Status.Text = "Conectando…";
        running = RunAsync(mail, password, cancellation.Token); password = "";
        try { await running; }
        finally
        {
            cancellation.Dispose(); cancellation = null;
            Connect.IsEnabled = Email.IsEnabled = Password.IsEnabled = true; Stop.IsEnabled = false;
            if (closing) { canClose = true; Close(); }
        }
    }
    private async Task RunAsync(string mail, string secret, CancellationToken ct)
    {
        using var client = new FirebaseClient();
        using var provider = new SportsDbResults();
        try
        {
            await client.SignInAsync(mail, secret, ct); secret = "";
            var permission = await client.GetAsync($"AccesoApuestaJornada/{client.Uid}", ct);
            if (permission is null || !J.Bool(permission.Data["activo"])) throw new InvalidOperationException("Tu cuenta aún no tiene acceso a Apuesta a jornada. Abre la app actualizada y comprueba su permiso.");
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ApuestaJornada", client.Uid);
            Directory.CreateDirectory(folder);
            FileStream instance;
            try { instance = new FileStream(Path.Combine(folder, "bridge.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { throw new InvalidOperationException("Otro programa está usando esta cuenta en el PC. Cierra el programa Python u otra ventana de .NET."); }
            using (instance)
            {
                var agentFile = Path.Combine(folder, "dotnet-agent.txt");
                var agent = File.Exists(agentFile) ? File.ReadAllText(agentFile).Trim() : Guid.NewGuid().ToString("N");
                File.WriteAllText(agentFile, agent);
                var ledger = new Ledger(Path.Combine(folder, "dotnet-history"));
                var worker = new BridgeWorker(client, ledger, provider, agent);
                Status.Text = "Sesión iniciada. Esperando el OK del móvil…";
                while (!ct.IsCancellationRequested)
                {
                    try
                    {
                        // Persistencia y JSON fuera del hilo de la interfaz.
                        var state = await Task.Run(() => worker.TickAsync(ct), ct);
                        Status.Text = J.Text(state["message"]);
                        Round.Text = J.Optional(state["scope"]) is { Length: > 0 } scope ? $"{scope} · Simulado en este ensayo: {J.Int(state["spentCents"]) / 100.0:0.00} €" : "Sin jornada autorizada.";
                        LastSeen.Text = "Última confirmación: " + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss");
                        History.ItemsSource = Bet.List(state["bets"]).Select(b => new { Match = b.Label, Amount = $"{b.Cents / 100.0:0.00} €", Odds = b.Odds.ToString("0.00") }).ToList();
                    }
                    catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
                    catch (Exception error)
                    {
                        Status.Text = "En espera. No se registran nuevos ensayos: " + Friendly(error);
                        LastSeen.Text = "Sin confirmar un estado nuevo; comprueba conexión y permisos.";
                    }
                    await Task.Delay(TimeSpan.FromSeconds(15), ct);
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { }
        catch (Exception error) { Status.Text = "No se pudo conectar: " + Friendly(error); return; }
        Status.Text = "PC detenido. El OK remoto sigue guardado; revócalo desde el móvil si quieres cancelarlo.";
    }
    private static string Friendly(Exception error) => error switch
    {
        HttpRequestException => "No se pudo contactar con el servidor.",
        TaskCanceledException => "El servidor tardó demasiado en responder.",
        _ => error.Message
    };
    private void Stop_Click(object sender, RoutedEventArgs e)
    { cancellation?.Cancel(); Status.Text = "Deteniendo PC…"; Stop.IsEnabled = false; }
    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (canClose || running is null || running.IsCompleted) return;
        e.Cancel = true; closing = true; cancellation?.Cancel(); Stop.IsEnabled = false; Status.Text = "Cerrando conexiones…";
    }
}
