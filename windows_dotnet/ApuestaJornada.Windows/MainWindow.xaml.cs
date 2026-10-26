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
    private bool liveMode, roundMode, readOnlyRound;
    private string historyFile = "";
    private string strategyFile = "";
    public MainWindow()
    {
        InitializeComponent();
        HistoryPath.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "bfbotmanager.com", "Bf Bot Manager V3", "uk_bets_history.gz");
        var bundled = Path.Combine(AppContext.BaseDirectory, "EmpatesJornada_PruebaReal.gz");
        if (File.Exists(bundled)) StrategyPath.Text = bundled;
    }

    private void RoundModeChanged(object sender, RoutedEventArgs e)
    {
        var name = RoundMode.IsChecked == true ? "EmpatesJornada_Ronda15.gz" : "EmpatesJornada_PruebaReal.gz";
        var path = Path.Combine(AppContext.BaseDirectory, name);
        if (StrategyPath is not null && File.Exists(path)) StrategyPath.Text = path;
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        if (running is { IsCompleted: false }) return;
        var mail = Email.Text.Trim(); var password = Password.Password;
        if (mail.Length == 0 || password.Length == 0) { Status.Text = "Introduce el correo y la contraseña de la app."; return; }
        roundMode = RoundMode.IsChecked == true;
        readOnlyRound = ReadOnlyMode.IsChecked == true;
        historyFile = HistoryPath.Text.Trim();
        if (roundMode && LiveMode.IsChecked == true) { Status.Text = "Selecciona sólo un modo real: piloto o ronda."; return; }
        if (roundMode && !readOnlyRound && AutoSaveVerified.IsChecked != true) { Status.Text = "Comprueba primero el guardado del historial con BF Bot abierto. Puedes conectar en sólo lectura."; return; }
        liveMode = LiveMode.IsChecked == true;
        if (roundMode)
        {
            try { BfHistory.Read(historyFile); }
            catch (Exception error) { Status.Text = "No se puede leer el historial: " + error.Message; return; }
        }
        strategyFile = StrategyPath.Text.Trim();
        if (liveMode || (roundMode && !readOnlyRound))
        {
            try { LiveStrategyValidator.Validate(strategyFile, roundMode); }
            catch (Exception error) { Status.Text = "Revisa el archivo de estrategia: " + error.Message; return; }
            if (MessageBox.Show(roundMode ? "Ronda REAL: el OK del móvil permite hasta 4 apuestas de 1, 2, 4 y 8 €, con un total máximo de 15 €. Importa EmpatesJornada_Ronda15.gz, pausa la estrategia antigua y verifica el guardado automático del historial. No se progresa sin liquidación completa." : "Modo REAL: el próximo OK REAL del móvil podrá publicar una orden BACK al empate de 1 €. Comprueba que BF Bot Manager usa la cuenta en euros y la estrategia revisada. No se enviará una segunda orden sin reconciliación.", "Activar recepción de OK real", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
        }
        RoundMode.IsEnabled = ReadOnlyMode.IsEnabled = HistoryPath.IsEnabled = AutoSaveVerified.IsEnabled = LiveMode.IsEnabled = StrategyPath.IsEnabled = false;
        cancellation = new(); Connect.IsEnabled = Email.IsEnabled = Password.IsEnabled = false; Stop.IsEnabled = true;
        Password.Clear(); Status.Text = "Conectando…";
        running = RunAsync(mail, password, cancellation.Token); password = "";
        try { await running; }
        finally
        {
            cancellation.Dispose(); cancellation = null;
            RoundMode.IsEnabled = ReadOnlyMode.IsEnabled = HistoryPath.IsEnabled = AutoSaveVerified.IsEnabled = Connect.IsEnabled = Email.IsEnabled = Password.IsEnabled = LiveMode.IsEnabled = StrategyPath.IsEnabled = true; Stop.IsEnabled = false;
            if (closing) { canClose = true; Close(); }
        }
    }
    private async Task RunAsync(string mail, string secret, CancellationToken ct)
    {
        using var client = new FirebaseClient();
        using var provider = new SportsDbResults();
        client.UseLivePilot = liveMode; client.UseLiveRound = roundMode;
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
                var liveWorker = new LivePilotWorker(client, provider, agent, Path.Combine(folder, "bfbot-live"), strategyFile);
                var roundWorker = new LiveRoundWorker(client, provider, agent, Path.Combine(folder, "bfbot-round15"), strategyFile, historyFile, readOnlyRound, $"PuenteJornadaReal/{client.Uid}");
                Outbox.Text = "Ruta para la carga automática de tips en BF Bot Manager: " + (roundMode ? roundWorker.OutboxPath : liveWorker.OutboxPath);
                Status.Text = "Sesión iniciada. Esperando el OK del móvil…";
                while (!ct.IsCancellationRequested)
                {
                    try
                    {
                        // Persistencia y JSON fuera del hilo de la interfaz.
                        var state = await Task.Run(() => roundMode ? roundWorker.TickAsync(ct) : liveMode ? liveWorker.TickAsync(ct) : worker.TickAsync(ct), ct);
                        Status.Text = J.Text(state["message"]);
                        LastSeen.Text = "Última confirmación: " + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss");
                        if (roundMode)
                        {
                            Round.Text = $"RONDA REAL · máximo 15 € · Estado: {J.Optional(state["status"])}";
                            History.ItemsSource = (state["orders"] as JsonArray ?? []).Select(n => J.Object(n)).Select(o => new
                            { Match = J.Text(o["matchId"]), Amount = $"{J.Int(o["cents"]) / 100.0:0.00} €", Odds = J.Optional(o["status"]) }).ToList();
                        }
                        else if (liveMode)
                        {
                            Round.Text = "REAL · Una orden máxima de 1 €. Estado: " + J.Optional(state["status"]);
                            History.ItemsSource = null;
                        }
                        else
                        {
                            Round.Text = J.Optional(state["scope"]) is { Length: > 0 } scope ? $"{scope} · Simulado en este ensayo: {J.Int(state["spentCents"]) / 100.0:0.00} €" : "Sin jornada autorizada.";
                            History.ItemsSource = Bet.List(state["bets"]).Select(b => new { Match = b.Label, Amount = $"{b.Cents / 100.0:0.00} €", Odds = b.Odds.ToString("0.00") }).ToList();
                        }
                    }
                    catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
                    catch (Exception error)
                    {
                        Status.Text = "En espera. No se envían nuevas órdenes: " + Friendly(error);
                        LastSeen.Text = "Sin confirmar un estado nuevo; comprueba conexión y permisos.";
                    }
                    await Task.Delay(TimeSpan.FromSeconds(15), ct);
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { }
        catch (Exception error) { Status.Text = "No se pudo conectar: " + Friendly(error); return; }
        Status.Text = "PC detenido. El OK remoto sigue guardado. Detener este programa no cancela una orden ya importada por BF Bot Manager.";
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

