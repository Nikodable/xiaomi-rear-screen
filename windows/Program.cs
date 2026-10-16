using System.IO;
using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;

// Mini GUI Windows 11 : miroir en direct, enregistrement et photo de l'écran arrière
// (scrcpy + adb embarqués dans l'exécutable).

namespace EcranArriere;

static class Program
{
    [STAThread]
    static void Main()
    {
        try { Tools.Prepare(); }
        catch (Exception e)
        {
            MessageBox.Show(I18N.T("err.prepare", e.Message), I18N.T("app.name"));
            return;
        }
        var app = new Application();
        try { app.ThemeMode = ThemeMode.System; } catch { /* thème Fluent indisponible : look classique */ }
        app.Run(new MainWindow());
    }
}

// ───────────────────────── outils embarqués ─────────────────────────

static class Tools
{
    const string Version = "4.1";
    public static string Dir = "";
    public static string Adb => Path.Combine(Dir, "adb.exe");
    public static string Scrcpy => Path.Combine(Dir, "scrcpy.exe");
    public static string Server => Path.Combine(Dir, "scrcpy-server");

    /// Extrait scrcpy/adb (embarqués) dans %LOCALAPPDATA% au premier lancement.
    public static void Prepare()
    {
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                "EcranArriere", "tools-" + Version);
        if (!File.Exists(Path.Combine(root, "scrcpy.exe")))
        {
            var tmp = root + ".tmp";
            if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
            Directory.CreateDirectory(tmp);
            using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("scrcpy.zip")
                          ?? throw new InvalidOperationException("archive scrcpy absente");
            using var z = new ZipArchive(s);
            foreach (var e in z.Entries)
            {
                var slash = e.FullName.IndexOf('/');
                var rel = slash >= 0 ? e.FullName[(slash + 1)..] : e.FullName;
                if (rel.Length == 0) continue;
                e.ExtractToFile(Path.Combine(tmp, rel), true);
            }
            if (Directory.Exists(root)) Directory.Delete(root, true);
            Directory.Move(tmp, root);
        }
        Dir = root;
    }
}

static class Proc
{
    static ProcessStartInfo Psi(string exe, IEnumerable<string> args, bool redirect)
    {
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Tools.Dir,
        };
        if (redirect)
        {
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
        }
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.Environment["ADB"] = Tools.Adb;
        psi.Environment["SCRCPY_SERVER_PATH"] = Tools.Server;
        return psi;
    }

    /// Lance un outil, attend la fin. Retourne stdout brut et le texte stdout+stderr.
    public static (byte[] Data, string Text) Run(string exe, params string[] args)
    {
        try
        {
            using var p = Process.Start(Psi(exe, args, true))!;
            var ms = new MemoryStream();
            var outTask = p.StandardOutput.BaseStream.CopyToAsync(ms);
            var errTask = p.StandardError.ReadToEndAsync();
            p.WaitForExit();
            outTask.Wait();
            var err = errTask.Result;
            return (ms.ToArray(), Encoding.UTF8.GetString(ms.ToArray()) + err);
        }
        catch { return (Array.Empty<byte>(), ""); }
    }

    /// Démarre le serveur adb sans rediriger ses flux (sinon le démon garde les tubes ouverts et bloque la lecture).
    public static void StartAdbServer()
    {
        try
        {
            using var p = Process.Start(Psi(Tools.Adb, new[] { "start-server" }, false))!;
            p.WaitForExit(15000);
        }
        catch { }
    }

    public static Process? Spawn(IEnumerable<string> args)
    {
        try { return Process.Start(Psi(Tools.Scrcpy, args, false)); }
        catch { return null; }
    }

    // ── arrêt propre : fermeture de la fenêtre (miroir) ou Ctrl+C (sans fenêtre), pour finaliser le .mp4 ──
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FreeConsole();
    [DllImport("kernel32.dll")] static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
    [DllImport("kernel32.dll")] static extern bool GenerateConsoleCtrlEvent(uint ev, uint group);

    public static void Stop(Process? p)
    {
        if (p == null) return;
        try
        {
            if (p.HasExited) return;
            p.Refresh();
            if (p.MainWindowHandle != IntPtr.Zero) p.CloseMainWindow();
            else SendCtrlC(p.Id);
            if (!p.WaitForExit(6000)) p.Kill(true);
        }
        catch { }
    }

    static void SendCtrlC(int pid)
    {
        FreeConsole();
        if (!AttachConsole((uint)pid)) return;
        SetConsoleCtrlHandler(IntPtr.Zero, true);
        GenerateConsoleCtrlEvent(0, 0); // CTRL_C_EVENT
        Thread.Sleep(300);
        FreeConsole();
        SetConsoleCtrlHandler(IntPtr.Zero, false);
    }

    public static bool Running(Process? p)
    {
        try { return p != null && !p.HasExited; } catch { return false; }
    }
}

// ───────────────────────── modèle ─────────────────────────

record Phone(string Serial, string State, string Model)
{
    public string Name { get; set; } = "";
    public bool IsWifi => Serial.Contains(':');
    public string Title
    {
        get
        {
            var label = Name != "" ? Name : (Model != "" ? Model : Serial);
            var t = $"{label} ({(IsWifi ? "Wi-Fi" : "USB")})";
            if (State != "device") t += " – " + (State == "unauthorized" ? I18N.T("phone.unauthorized") : State);
            return t;
        }
    }
}

enum Role { Front, Rear, Main, Other }

record DisplayInfo(string Id, string Size, string? LocalId, Role Role)
{
    public string Name => Role switch
    {
        Role.Front => I18N.T("display.front"),
        Role.Rear => I18N.T("display.rear"),
        Role.Main => I18N.T("display.main"),
        _ => I18N.T("display.other", Id),
    };

    /// partie ASCII du nom de fichier
    public string Slug => Role switch
    {
        Role.Front => "avant",
        Role.Rear => "arriere",
        Role.Main => "principal",
        _ => "ecran" + Id,
    };
}

enum Quality { Light, Normal, Max }

static class Q
{
    public static string Title(Quality q) => q switch
    {
        Quality.Light => I18N.T("quality.light"),
        Quality.Normal => I18N.T("quality.normal"),
        _ => I18N.T("quality.max"),
    };
    public static string[] Args(Quality q) => q switch
    {
        Quality.Light => new[] { "--video-bit-rate=4M", "--max-fps=30" },
        Quality.Normal => new[] { "--video-bit-rate=8M", "--max-fps=60" },
        _ => new[] { "--video-bit-rate=20M", "--max-fps=120" },
    };
}

static class Adb
{
    public static List<Phone> Devices()
    {
        var list = new List<Phone>();
        foreach (var raw in Proc.Run(Tools.Adb, "devices", "-l").Text.Split('\n'))
        {
            var l = raw.Trim();
            if (l.Length == 0 || l.StartsWith('*') || l.StartsWith("List of")) continue;
            var parts = l.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2) continue;
            var model = parts.FirstOrDefault(p => p.StartsWith("model:"))?[6..] ?? "";
            list.Add(new Phone(parts[0], parts[1], model));
        }
        return list;
    }

    /// Nom commercial lu dans le téléphone (ex. « Xiaomi 18 Pro Max »), vide si introuvable.
    public static string MarketName(string serial)
    {
        foreach (var prop in new[] { "ro.product.marketname", "ro.product.odm.marketname", "ro.product.vendor.marketname" })
        {
            var t = Proc.Run(Tools.Adb, "-s", serial, "shell", "getprop", prop).Text.Trim();
            if (t.Length > 0 && !t.Contains("error:")) return t;
        }
        return "";
    }

    /// Écrans physiques du téléphone, nommés (avant / arrière / principal). Les écrans virtuels sont ignorés.
    public static List<DisplayInfo> Displays(string serial)
    {
        var listing = Proc.Run(Tools.Scrcpy, "-s", serial, "--list-displays").Text;
        var raw = Regex.Matches(listing, @"--display-id=(\d+)\s+\(([^)]*)\)")
                       .Select(m => (Id: m.Groups[1].Value, Size: m.Groups[2].Value)).ToList();
        if (raw.Count == 0) return new();

        var dump = Proc.Run(Tools.Adb, "-s", serial, "shell", "dumpsys", "display").Text;
        var local = new Dictionary<string, string>();
        foreach (Match m in Regex.Matches(dump, "displayId (\\d+),.*?uniqueId \"local:(\\d+)\""))
            local[m.Groups[1].Value] = m.Groups[2].Value;
        var known = local.Count > 0;

        var physical = raw.Where(d => !known || d.Id == "0" || local.ContainsKey(d.Id)).ToList();
        var rearTaken = false;
        var result = new List<DisplayInfo>();
        foreach (var d in physical)
        {
            var role = Role.Other;
            if (d.Id == "0") role = physical.Count > 1 ? Role.Front : Role.Main;
            else if (!rearTaken) { role = Role.Rear; rearTaken = true; }
            result.Add(new DisplayInfo(d.Id, d.Size, local.GetValueOrDefault(d.Id), role));
        }
        return result;
    }
}

// ───────────────────────── fenêtre ─────────────────────────

class MainWindow : Window
{
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins m);
    [StructLayout(LayoutKind.Sequential)] struct Margins { public int L, R, T, B; }

    static readonly string OutDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "EcranArriere");

    readonly bool dark = IsDarkTheme();
    TextBlock status = new();
    ComboBox devicePopup = new(), displayPopup = new(), qualityPopup = new(), langPopup = new();
    Button mirrorBtn = new(), recBtn = new(), photoBtn = new();
    CheckBox viewCheck = new();
    TextBlock timerLabel = new();

    List<Phone> devices = new();
    List<DisplayInfo> displays = new();
    List<List<DisplayInfo>> targets = new();   // une entrée par ligne du menu « Écran »
    readonly Dictionary<string, string> phoneNames = new();
    string? displaysSerial, pendingSelect;
    bool refreshing, suppress, showWhileRecording = true;
    List<Process> mirrors = new(), records = new();
    DateTime recStart;
    List<string> recFiles = new();

    static bool IsDarkTheme()
    {
        try { return (int)(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) ?? 1) == 0; }
        catch { return false; }
    }

    Phone? SelectedPhone => devicePopup.SelectedIndex >= 0 && devicePopup.SelectedIndex < devices.Count ? devices[devicePopup.SelectedIndex] : null;
    List<DisplayInfo> SelectedTargets =>
        displayPopup.SelectedIndex >= 0 && displayPopup.SelectedIndex < targets.Count
            ? targets[displayPopup.SelectedIndex]
            : new() { new DisplayInfo("1", "", null, Role.Rear) };
    Quality SelectedQuality => (Quality)Math.Max(0, qualityPopup.SelectedIndex);
    static bool Any(List<Process> ps) => ps.Any(Proc.Running);

    public MainWindow()
    {
        Title = I18N.T("app.name");
        Width = 420;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        Foreground = new SolidColorBrush(dark ? Colors.White : Color.FromRgb(0x1B, 0x1B, 0x1B));
        Background = new SolidColorBrush(dark ? Color.FromRgb(0x20, 0x20, 0x20) : Color.FromRgb(0xF3, 0xF3, 0xF3));
        BuildUi();

        Loaded += (_, _) =>
        {
            Task.Run(Proc.StartAdbServer).ContinueWith(_ => Dispatcher.Invoke(Refresh));
            var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            t.Tick += (_, _) => Tick();
            t.Start();
            var r = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            r.Tick += (_, _) => Refresh();
            r.Start();
        };
        Closing += (_, _) => { mirrors.ForEach(Proc.Stop); records.ForEach(Proc.Stop); };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        // Windows 11 : barre de titre sombre/claire + fond Mica sous toute la fenêtre
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            int d = dark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, 20, ref d, 4);          // DWMWA_USE_IMMERSIVE_DARK_MODE
            int mica = 2;
            if (DwmSetWindowAttribute(hwnd, 38, ref mica, 4) == 0)   // DWMWA_SYSTEMBACKDROP_TYPE = Mica
            {
                var m = new Margins { L = -1, R = -1, T = -1, B = -1 };
                DwmExtendFrameIntoClientArea(hwnd, ref m);
                HwndSource.FromHwnd(hwnd)!.CompositionTarget.BackgroundColor = Colors.Transparent;
                Background = Brushes.Transparent;
            }
        }
        catch { /* repli : fond uni */ }
    }

    // ── construction de l'interface ──

    StackPanel Stack(params UIElement[] items)
    {
        var s = new StackPanel();
        for (int i = 0; i < items.Length; i++)
        {
            if (items[i] is FrameworkElement fe && i < items.Length - 1) fe.Margin = new Thickness(0, 0, 0, 10);
            s.Children.Add(items[i]);
        }
        return s;
    }

    Border Card(params UIElement[] items) => new()
    {
        CornerRadius = new CornerRadius(12),
        Padding = new Thickness(14),
        Margin = new Thickness(0, 0, 0, 12),
        Background = new SolidColorBrush(dark ? Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0xAA, 0xFF, 0xFF, 0xFF)),
        BorderBrush = new SolidColorBrush(dark ? Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x25, 0x00, 0x00, 0x00)),
        BorderThickness = new Thickness(1),
        Child = Stack(items),
    };

    Grid Row(string label, FrameworkElement control, FrameworkElement? extra = null)
    {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var l = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Opacity = 0.65 };
        Grid.SetColumn(control, 1);
        g.Children.Add(l);
        g.Children.Add(control);
        if (extra != null) { Grid.SetColumn(extra, 2); extra.Margin = new Thickness(8, 0, 0, 0); g.Children.Add(extra); }
        return g;
    }

    Button Btn(string text, RoutedEventHandler click)
    {
        var b = new Button { Content = text, Height = 36, Padding = new Thickness(10, 0, 10, 0) };
        b.Click += click;
        return b;
    }

    UIElement TwoCols(Button a, Button b)
    {
        a.Margin = new Thickness(0, 0, 4, 0);
        b.Margin = new Thickness(4, 0, 0, 0);
        return new UniformGrid { Columns = 2, Children = { a, b } };
    }

    static void StyleAccent(Button b, Color c)
    {
        b.Height = 38;
        b.Background = new SolidColorBrush(c);
        b.BorderBrush = new SolidColorBrush(c);
        b.Foreground = Brushes.White;
    }

    void BuildUi()
    {
        status = new TextBlock { Text = I18N.T("status.searching"), TextWrapping = TextWrapping.Wrap, MinHeight = 34 };
        devicePopup = new ComboBox { Height = 32 };
        displayPopup = new ComboBox { Height = 32 };
        qualityPopup = new ComboBox { Height = 32 };
        langPopup = new ComboBox { Width = 120, Height = 28, HorizontalAlignment = HorizontalAlignment.Right, ToolTip = I18N.T("lang.label") };
        timerLabel = new TextBlock { HorizontalAlignment = HorizontalAlignment.Center, FontFamily = new FontFamily("Consolas"), FontSize = 15, Visibility = Visibility.Collapsed };
        viewCheck = new CheckBox { Content = I18N.T("rec.viewCheck"), IsChecked = showWhileRecording };
        viewCheck.Click += (_, _) => showWhileRecording = viewCheck.IsChecked == true;

        foreach (var q in Enum.GetValues<Quality>()) qualityPopup.Items.Add(Q.Title(q));
        qualityPopup.SelectedIndex = (int)Quality.Normal;
        devicePopup.SelectionChanged += (_, _) => { if (!suppress) { displaysSerial = null; Refresh(); } };

        foreach (var (code, native) in I18N.Langs) langPopup.Items.Add(native);
        langPopup.SelectedIndex = Array.FindIndex(I18N.Langs, l => l.Code == I18N.Current);
        langPopup.SelectionChanged += (_, _) => OnLangChanged();

        var refreshBtn = Btn("↻", (_, _) => { displaysSerial = null; Refresh(); });
        refreshBtn.Width = 40; refreshBtn.Height = 32; refreshBtn.ToolTip = I18N.T("tip.refresh");

        mirrorBtn = Btn(I18N.T("mirror.start"), (_, _) => ToggleMirror()); StyleAccent(mirrorBtn, Color.FromRgb(0x5B, 0x6C, 0xFF));
        recBtn = Btn(I18N.T("rec.start"), (_, _) => ToggleRecord()); StyleAccent(recBtn, Color.FromRgb(0xE5, 0x39, 0x35));
        photoBtn = Btn(I18N.T("btn.photo"), (_, _) => TakePhoto());
        var folder = Btn(I18N.T("btn.folder"), (_, _) => OpenFolder());
        var wifi = Btn(I18N.T("btn.wifi"), (_, _) => SwitchToWifi());
        wifi.ToolTip = I18N.T("tip.wifi");
        var manual = Btn(I18N.T("btn.manual"), (_, _) => ManualConnect());

        var title = new TextBlock { Text = I18N.T("app.name"), FontSize = 20, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) };
        var titleRow = new Grid { Margin = new Thickness(0, 0, 0, 12) };
        titleRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        titleRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(langPopup, 1);
        titleRow.Children.Add(title);
        titleRow.Children.Add(langPopup);

        var cardA = Card(status, Row(I18N.T("label.phone"), devicePopup, refreshBtn), Row(I18N.T("label.display"), displayPopup), Row(I18N.T("label.quality"), qualityPopup));
        var cardB = Card(mirrorBtn, recBtn, viewCheck, timerLabel, TwoCols(photoBtn, folder));
        var cardC = Card(TwoCols(wifi, manual));

        var root = new StackPanel { Margin = new Thickness(16, 12, 16, 4) };
        root.Children.Add(titleRow);
        root.Children.Add(cardA);
        root.Children.Add(cardB);
        root.Children.Add(cardC);
        Content = root;
    }

    void OnLangChanged()
    {
        if (suppress || langPopup.SelectedIndex < 0) return;
        var phone = SelectedPhone?.Serial;
        var q = qualityPopup.SelectedIndex;
        var prev = SelectedTargets.Select(d => d.Id).ToList();
        I18N.Set(I18N.Langs[langPopup.SelectedIndex].Code);
        Title = I18N.T("app.name");
        suppress = true;
        BuildUi();
        qualityPopup.SelectedIndex = q;
        FillDevices(phone);
        FillDisplays(prev);
        suppress = false;
        UpdateStatus();
    }

    // ── détection du téléphone ──

    async void Refresh()
    {
        if (refreshing) return;
        refreshing = true;
        try
        {
            var wanted = pendingSelect ?? SelectedPhone?.Serial;
            var knownSerial = displaysSerial;
            var knownDisplays = displays.ToList();
            var knownNames = new Dictionary<string, string>(phoneNames);

            var r = await Task.Run(() =>
            {
                var list = Adb.Devices();
                var names = new Dictionary<string, string>(knownNames);
                foreach (var p in list.Where(p => p.State == "device"))
                {
                    if (!names.ContainsKey(p.Serial)) names[p.Serial] = Adb.MarketName(p.Serial);
                    p.Name = names[p.Serial];
                }
                var chosen = list.FirstOrDefault(p => p.Serial == wanted)
                             ?? list.FirstOrDefault(p => p.State == "device") ?? list.FirstOrDefault();
                var found = knownDisplays;
                var serial = knownSerial;
                if (chosen is { State: "device" } && (chosen.Serial != knownSerial || knownDisplays.Count == 0))
                {
                    found = Adb.Displays(chosen.Serial);
                    serial = found.Count == 0 ? null : chosen.Serial;
                }
                else if (chosen?.State != "device") { found = new(); serial = null; }
                return (list, names, chosen, found, serial);
            });

            foreach (var kv in r.names) phoneNames[kv.Key] = kv.Value;
            Apply(r.list, r.chosen, r.found, r.serial);
        }
        catch { /* on réessaiera au prochain tour */ }
        finally { refreshing = false; }
    }

    void Apply(List<Phone> list, Phone? chosen, List<DisplayInfo> found, string? serial)
    {
        suppress = true;
        var phoneChanged = !list.Select(p => p.Title + p.Serial).SequenceEqual(devices.Select(p => p.Title + p.Serial));
        devices = list;
        if (phoneChanged || devicePopup.Items.Count == 0) FillDevices(chosen?.Serial);
        else if (chosen != null)
        {
            var i = devices.FindIndex(p => p.Serial == chosen.Serial);
            if (i >= 0) devicePopup.SelectedIndex = i;
        }
        if (chosen?.Serial == pendingSelect) pendingSelect = null;

        displaysSerial = serial;
        var displaysChanged = !found.Select(d => d.Id).SequenceEqual(displays.Select(d => d.Id)) || displayPopup.Items.Count == 0;
        displays = found;
        if (displaysChanged) FillDisplays(null);
        suppress = false;
        UpdateStatus();
    }

    void FillDevices(string? select)
    {
        devicePopup.Items.Clear();
        foreach (var p in devices) devicePopup.Items.Add(p.Title);
        var i = select == null ? -1 : devices.FindIndex(p => p.Serial == select);
        if (i >= 0) devicePopup.SelectedIndex = i;
    }

    /// Remplit le menu « Écran » : chaque écran nommé, + « Les deux écrans » s'il y en a au moins deux.
    void FillDisplays(List<string>? previous)
    {
        displayPopup.Items.Clear();
        targets = new();
        if (displays.Count == 0)
        {
            var d = new DisplayInfo("1", "", null, Role.Rear);
            targets.Add(new() { d });
            displayPopup.Items.Add(d.Name);
            displayPopup.SelectedIndex = 0;
            return;
        }
        foreach (var d in displays)
        {
            targets.Add(new() { d });
            displayPopup.Items.Add($"{d.Name} ({d.Size})");
        }
        if (displays.Count >= 2)
        {
            targets.Add(displays.ToList());
            displayPopup.Items.Add(I18N.T("display.both"));
        }
        // sélection : celle d'avant (changement de langue), sinon l'écran arrière
        var i = previous == null ? -1 : targets.FindIndex(t => t.Select(d => d.Id).SequenceEqual(previous));
        if (i < 0) i = targets.FindIndex(t => t.Count == 1 && t[0].Role == Role.Rear);
        displayPopup.SelectedIndex = Math.Max(0, i);
    }

    void UpdateStatus()
    {
        var c = SelectedPhone;
        if (c == null) { status.Text = I18N.T("status.noPhone"); return; }
        status.Text = c.State switch
        {
            "device" => displays.Count == 0 ? I18N.T("status.noDisplays") : I18N.T("status.connected"),
            "unauthorized" => I18N.T("status.unauthorized"),
            "offline" => I18N.T("status.offline"),
            _ => I18N.T("status.state", c.State),
        };
    }

    // ── miroir / enregistrement ──

    Phone? ReadyPhone()
    {
        var p = SelectedPhone;
        if (p == null || p.State != "device")
        {
            MessageBox.Show(status.Text, I18N.T("alert.noPhone"), MessageBoxButton.OK, MessageBoxImage.Information);
            return null;
        }
        return p;
    }

    /// Fenêtres côte à côte quand on montre plusieurs écrans : taille réduite + position, sans toucher à la qualité vidéo.
    static List<(int X, int W, int H)?> WindowLayout(List<DisplayInfo> ts)
    {
        if (ts.Count < 2) return ts.Select(_ => ((int, int, int)?)null).ToList();
        var x = 20;
        var res = new List<(int X, int W, int H)?>();
        foreach (var d in ts)
        {
            var dims = d.Size.Split('x');
            double W = 976, H = 596;
            if (dims.Length == 2 && double.TryParse(dims[0], out var w0) && double.TryParse(dims[1], out var h0)) { W = w0; H = h0; }
            var k = Math.Min(1.0, Math.Min(560 / W, 720 / H));
            var slot = (X: x, W: (int)(W * k), H: (int)(H * k));
            x += slot.W + 24;
            res.Add(slot);
        }
        return res;
    }

    List<string> Args(Phone p, DisplayInfo d, (int X, int W, int H)? slot)
    {
        var a = new List<string> { "-s", p.Serial, $"--display-id={d.Id}", "--no-audio", $"--window-title={d.Name}" };
        a.AddRange(Q.Args(SelectedQuality));
        if (slot is { } s) a.AddRange(new[] { $"--window-x={s.X}", "--window-y=60", $"--window-width={s.W}", $"--window-height={s.H}" });
        return a;
    }

    int launchGen;   // annule les lancements en attente quand on arrête

    /// Lance les instances scrcpy l'une après l'autre (≈2,5 s d'écart) : deux démarrages simultanés
    /// se disputent le même port de liaison adb et la première échoue.
    async void LaunchStaggered(List<List<string>> argsList, Action<Process> onStart)
    {
        var gen = ++launchGen;
        for (int i = 0; i < argsList.Count; i++)
        {
            if (i > 0) await Task.Delay(2500);
            if (gen != launchGen) return;
            var proc = Proc.Spawn(argsList[i]);
            if (proc != null) onStart(proc);
        }
    }

    void ToggleMirror()
    {
        if (Any(mirrors)) { launchGen++; var ps = mirrors.ToList(); Task.Run(() => ps.ForEach(Proc.Stop)); return; }
        if (Any(records))
        {
            MessageBox.Show(I18N.T("rec.inProgress"), I18N.T("app.name"));
            return;
        }
        var p = ReadyPhone();
        if (p == null) return;
        var ts = SelectedTargets;
        var slots = WindowLayout(ts);
        mirrors = new();
        LaunchStaggered(ts.Select((d, i) => Args(p, d, slots[i])).ToList(), proc => mirrors.Add(proc));
    }

    void ToggleRecord()
    {
        if (Any(records))
        {
            launchGen++;
            var ps = records.ToList();
            Task.Run(() => ps.ForEach(Proc.Stop));
            status.Text = I18N.T("rec.saved", string.Join(", ", recFiles.Select(Path.GetFileName)));
            return;
        }
        var p = ReadyPhone();
        if (p == null) return;
        launchGen++;
        mirrors.ForEach(Proc.Stop);
        Directory.CreateDirectory(OutDir);
        var ts = SelectedTargets;
        var slots = WindowLayout(ts);
        var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        recFiles = new();
        var jobs = new List<List<string>>();
        for (int i = 0; i < ts.Count; i++)
        {
            var file = Path.Combine(OutDir, $"ecran_{ts[i].Slug}_{stamp}.mp4");
            recFiles.Add(file);
            var a = Args(p, ts[i], slots[i]);
            a.Add("--record=" + file);
            if (!showWhileRecording) a.Add("--no-playback");
            jobs.Add(a);
        }
        records = new();
        recStart = DateTime.Now;
        LaunchStaggered(jobs, proc => records.Add(proc));
    }

    // ── photo ──

    async void TakePhoto()
    {
        var p = ReadyPhone();
        if (p == null) return;
        var ts = SelectedTargets;
        var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        status.Text = I18N.T("photo.capturing");
        var msg = await Task.Run(() =>
        {
            Directory.CreateDirectory(OutDir);
            var saved = new List<string>();
            foreach (var d in ts)
            {
                var args = new List<string> { "-s", p.Serial, "exec-out", "screencap", "-p" };
                if (d.Id != "0")
                {
                    if (d.LocalId == null) return I18N.T("photo.noId", d.Id);
                    args.AddRange(new[] { "-d", d.LocalId });
                }
                var data = Proc.Run(Tools.Adb, args.ToArray()).Data;
                if (data.Length < 8 || data[0] != 0x89 || data[1] != 0x50 || data[2] != 0x4E || data[3] != 0x47)
                    return I18N.T("photo.noImage");
                var file = Path.Combine(OutDir, $"ecran_{d.Slug}_{stamp}.png");
                try { File.WriteAllBytes(file, data); saved.Add(file); }
                catch { return I18N.T("photo.writeFail"); }
            }
            if (saved.Count > 0)
                Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{saved[0]}\"") { UseShellExecute = true });
            return I18N.T("photo.done", string.Join(", ", saved.Select(Path.GetFileName)));
        });
        status.Text = msg;
    }

    void OpenFolder()
    {
        Directory.CreateDirectory(OutDir);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{OutDir}\"") { UseShellExecute = true });
    }

    // ── Wi-Fi ──

    async void SwitchToWifi()
    {
        var p = ReadyPhone();
        if (p == null) return;
        if (p.IsWifi) { status.Text = I18N.T("wifi.already"); return; }
        status.Text = I18N.T("wifi.activating");
        var (ok, text, ip) = await Task.Run(() =>
        {
            var ipOut = Proc.Run(Tools.Adb, "-s", p.Serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0").Text;
            var m = Regex.Match(ipOut, @"inet (\d+\.\d+\.\d+\.\d+)");
            if (!m.Success) return (false, I18N.T("wifi.noWifi"), "");
            var ip = m.Groups[1].Value;
            Proc.Run(Tools.Adb, "-s", p.Serial, "tcpip", "5555");
            Thread.Sleep(2000);
            var r = Proc.Run(Tools.Adb, "connect", $"{ip}:5555").Text;
            return (r.Contains("connected"), I18N.T("wifi.failed", r.Trim()), ip);
        });
        if (ok)
        {
            pendingSelect = $"{ip}:5555";
            displaysSerial = null;
            status.Text = I18N.T("wifi.ok", ip);
            Refresh();
        }
        else status.Text = text;
    }

    async void ManualConnect()
    {
        var dlg = new ConnectDialog(dark) { Owner = this };
        if (dlg.ShowDialog() != true) return;
        var (pa, pc, ca) = (dlg.PairAddr, dlg.Code, dlg.ConnAddr);
        if (ca.Length == 0) { status.Text = I18N.T("manual.noAddr"); return; }
        status.Text = I18N.T("manual.connecting");
        var (ok, text) = await Task.Run(() =>
        {
            if (pa.Length > 0 && pc.Length > 0)
            {
                var pr = Proc.Run(Tools.Adb, "pair", pa, pc).Text;
                if (!pr.Contains("Successfully")) return (false, I18N.T("manual.pairFailed", pr.Trim()));
            }
            var r = Proc.Run(Tools.Adb, "connect", ca).Text;
            return (r.Contains("connected"), I18N.T("manual.failed", r.Trim()));
        });
        if (ok)
        {
            pendingSelect = ca;
            displaysSerial = null;
            status.Text = I18N.T("manual.ok");
            Refresh();
        }
        else status.Text = text;
    }

    // ── minuteur ──

    void Tick()
    {
        mirrorBtn.Content = Any(mirrors) ? I18N.T("mirror.stop") : I18N.T("mirror.start");
        if (Any(records))
        {
            recBtn.Content = I18N.T("rec.stop");
            var s = (int)(DateTime.Now - recStart).TotalSeconds;
            timerLabel.Text = $"● REC {s / 60:00}:{s % 60:00}";
            timerLabel.Visibility = Visibility.Visible;
        }
        else
        {
            recBtn.Content = I18N.T("rec.start");
            timerLabel.Visibility = Visibility.Collapsed;
        }
    }
}

// ───────────────────────── connexion manuelle ─────────────────────────

class ConnectDialog : Window
{
    readonly TextBox pair = new(), code = new(), conn = new();
    public string PairAddr => pair.Text.Trim();
    public string Code => code.Text.Trim();
    public string ConnAddr => conn.Text.Trim();

    public ConnectDialog(bool dark)
    {
        Title = I18N.T("manual.title");
        Width = 400;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(dark ? Color.FromRgb(0x20, 0x20, 0x20) : Color.FromRgb(0xF3, 0xF3, 0xF3));
        Foreground = new SolidColorBrush(dark ? Colors.White : Color.FromRgb(0x1B, 0x1B, 0x1B));
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");

        var s = new StackPanel { Margin = new Thickness(18) };
        s.Children.Add(new TextBlock
        {
            Text = I18N.T("manual.info"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        });
        void Field(string label, TextBox box, string hint)
        {
            s.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 0, 0, 3), Opacity = 0.7 });
            box.ToolTip = hint; box.Height = 30; box.Margin = new Thickness(0, 0, 0, 10);
            box.VerticalContentAlignment = VerticalAlignment.Center;
            s.Children.Add(box);
        }
        Field(I18N.T("manual.pairAddr"), pair, I18N.T("manual.eg", "192.168.1.20:37123"));
        Field(I18N.T("manual.code"), code, I18N.T("manual.codeHint"));
        Field(I18N.T("manual.connAddr"), conn, I18N.T("manual.eg", "192.168.1.20:41234"));

        var ok = new Button { Content = I18N.T("manual.connect"), MinWidth = 100, Height = 32, IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var cancel = new Button { Content = I18N.T("manual.cancel"), MinWidth = 100, Height = 32, IsCancel = true };
        ok.Click += (_, _) => DialogResult = true;
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        row.Children.Add(ok); row.Children.Add(cancel);
        s.Children.Add(row);
        Content = s;
    }
}
