using System.Diagnostics;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Modules.Admin;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Extensions;
using Microsoft.Extensions.Logging;

namespace Cs2ToolkitMenuV2;

// Beta: a separate, mouse-driven Panorama menu. The original css_admin plugin is untouched.
public sealed class Cs2ToolkitMenuV2 : BasePlugin
{
    public override string ModuleName => "CS2 Server Toolkit Menu V2 Beta";
    public override string ModuleVersion => "0.1.0";
    public override string ModuleAuthor => "CS2 Server Toolkit";
    public override string ModuleDescription => "Clickable admin menu using custom_hud_layout";

    private const string Permission = "@cs2toolkit/admin";
    private const string Layout = "panorama/layout/custom_game/cs2_toolkit_admin_v2.xml";
    private const int RowsPerPage = 8;
    private readonly SemaphoreSlim _actionGate = new(1, 1);
    private readonly Dictionary<ulong, MenuState> _open = new();
    private CCSCustomHudLayout? _layout;

    private enum Page { Home, Maps, Competitive, ArmsRace, Modes, Bots, Difficulty, Voice, Weapons, Fun, Gravity, Speed, Confirm }
    private sealed class MenuState
    {
        public Page Page { get; set; } = Page.Home;
        public int Offset { get; set; }
        public ActionSpec? Pending { get; set; }
        public Page ReturnPage { get; set; } = Page.Maps;
        public string Status { get; set; } = "Click an option. Close releases the mouse.";
    }
    private sealed record ActionSpec(string Label, string Command, string[] Args, bool Confirm = false);
    private sealed record Entry(string Label, Page? Destination = null, ActionSpec? Action = null);

    public override void Load(bool hotReload)
    {
        AddCommand("css_adminv2", "Open the CS2 Toolkit mouse menu beta", OnMenuCommand);
        AddCommand("css_toolkitv2", "Open the CS2 Toolkit mouse menu beta", OnMenuCommand);
        RegisterListener<Listeners.OnCustomHudClicked>(OnClicked);
        RegisterListener<Listeners.OnMapEnd>(OnMapEnd);
        RegisterListener<Listeners.OnClientPutInServer>(OnClientPutInServer);
        RegisterListener<Listeners.OnClientDisconnect>(OnClientDisconnect);
        RegisterEventHandler<EventRoundStart>(OnRoundStart);
        if (hotReload) SpawnLayout();
    }

    public override void Unload(bool hotReload)
    {
        foreach (var steamId in _open.Keys.ToArray())
        {
            var player = Utilities.GetPlayerFromSteamId64(steamId);
            if (player is { IsValid: true }) Hide(player);
        }
        _open.Clear();
        if (_layout is { IsValid: true }) _layout.Remove();
        _layout = null;
        RemoveListener<Listeners.OnCustomHudClicked>(OnClicked);
        RemoveListener<Listeners.OnMapEnd>(OnMapEnd);
        RemoveListener<Listeners.OnClientPutInServer>(OnClientPutInServer);
        RemoveListener<Listeners.OnClientDisconnect>(OnClientDisconnect);
        DeregisterEventHandler<EventRoundStart>(OnRoundStart);
        RemoveCommand("css_adminv2", OnMenuCommand);
        RemoveCommand("css_toolkitv2", OnMenuCommand);
    }

    private static bool IsAdmin(CCSPlayerController player) =>
        player.IsValid && AdminManager.PlayerHasPermissions(player, Permission);

    private void OnMenuCommand(CCSPlayerController? player, CommandInfo command)
    {
        if (player is null || !player.IsValid || player.IsBot) return;
        if (!IsAdmin(player))
        {
            player.PrintToChat("[CS2 Toolkit] Admin access required.");
            return;
        }
        if (_open.ContainsKey(player.SteamID))
        {
            Hide(player);
            return;
        }

        // CS2 1.41.8.x may clear per-slot text flags when a player joins. A fresh entity
        // on open makes labels reliable; restore any other admins who are using the menu.
        RebuildLayout();
        if (_layout is not { IsValid: true })
        {
            player.PrintToChat("[CS2 Toolkit] Menu unavailable. Check the plugin log.");
            return;
        }
        _open[player.SteamID] = new MenuState();
        Render(player);
        _layout.SetHasClassForPlayer(player, "v2_window", "shown", true);
        _layout.SetHasClassForPlayer(player, "v2_dim", "shown", true);
        _layout.SetInputCaptureEnabled(player, true);
    }

    private HookResult OnRoundStart(EventRoundStart @event, GameEventInfo info)
    {
        SpawnLayout();
        return HookResult.Continue;
    }

    private void OnMapEnd()
    {
        _layout = null;
        _open.Clear();
    }

    private void OnClientPutInServer(int slot)
    {
        var player = Utilities.GetPlayerFromSlot(slot);
        if (player is not { IsValid: true } || _layout is not { IsValid: true }) return;
        _open.Remove(player.SteamID);
        _layout.SetHasClassForPlayer(player, "v2_window", "shown", false);
        _layout.SetHasClassForPlayer(player, "v2_dim", "shown", false);
        _layout.SetInputCaptureEnabled(player, false);
    }

    private void OnClientDisconnect(int slot)
    {
        var player = Utilities.GetPlayerFromSlot(slot);
        if (player is not null) _open.Remove(player.SteamID);
    }

    private void SpawnLayout()
    {
        if (_layout is { IsValid: true }) return;
        try
        {
            foreach (var old in Utilities.FindAllEntitiesByDesignerName<CCSCustomHudLayout>("custom_hud_layout"))
                if (old.IsValid && old.StrLayout == Layout) old.Remove();
            var layout = Utilities.CreateEntityByName<CCSCustomHudLayout>("custom_hud_layout");
            if (layout is null || !layout.IsValid) return;
            layout.StrLayout = Layout;
            layout.DispatchSpawn();
            _layout = layout;
        }
        catch (Exception exception)
        {
            Logger.LogError(exception, "Could not create the V2 admin layout");
        }
    }

    private void RebuildLayout()
    {
        if (_layout is { IsValid: true }) _layout.Remove();
        _layout = null;
        SpawnLayout();
        if (_layout is not { IsValid: true }) return;
        foreach (var steamId in _open.Keys.ToArray())
        {
            var player = Utilities.GetPlayerFromSteamId64(steamId);
            if (player is not { IsValid: true } || !IsAdmin(player))
            {
                _open.Remove(steamId);
                continue;
            }
            Render(player);
            _layout.SetHasClassForPlayer(player, "v2_window", "shown", true);
            _layout.SetHasClassForPlayer(player, "v2_dim", "shown", true);
            _layout.SetInputCaptureEnabled(player, true);
        }
    }

    private void Hide(CCSPlayerController player)
    {
        _open.Remove(player.SteamID);
        if (_layout is not { IsValid: true }) return;
        _layout.SetHasClassForPlayer(player, "v2_window", "shown", false);
        _layout.SetHasClassForPlayer(player, "v2_dim", "shown", false);
        _layout.SetInputCaptureEnabled(player, false);
    }

    private void OnClicked(CCSPlayerController player, CCSCustomHudLayout clickedLayout, string buttonId)
    {
        if (_layout is not { IsValid: true } || !clickedLayout.IsValid || clickedLayout.Index != _layout.Index ||
            !player.IsValid || !_open.TryGetValue(player.SteamID, out var state)) return;
        if (!IsAdmin(player)) { Hide(player); return; }
        try
        {
            switch (buttonId)
            {
                case "v2_close" or "v2_dim": Hide(player); return;
                case "v2_back": Back(state); break;
                case "v2_prev": state.Offset = Math.Max(0, state.Offset - RowsPerPage); break;
                case "v2_next":
                    if (state.Offset + RowsPerPage < Entries(state).Count) state.Offset += RowsPerPage;
                    break;
                default:
                    if (!buttonId.StartsWith("v2_row_", StringComparison.Ordinal) ||
                        !int.TryParse(buttonId[7..], out var row) || row < 0 || row >= RowsPerPage) return;
                    var entries = Entries(state);
                    var index = state.Offset + row;
                    if (index >= entries.Count) return;
                    Select(player, state, entries[index]);
                    break;
            }
            if (_open.ContainsKey(player.SteamID)) Render(player);
        }
        catch (Exception exception)
        {
            Logger.LogError(exception, "V2 menu click failed");
            Hide(player);
        }
    }

    private void Select(CCSPlayerController player, MenuState state, Entry entry)
    {
        if (entry.Destination is { } page)
        {
            state.Page = page;
            state.Offset = 0;
            state.Status = "Choose an option.";
            return;
        }
        if (entry.Action is not { } action) return;
        if (state.Page == Page.Confirm)
        {
            if (action.Command == "cancel") { Back(state); return; }
            if (state.Pending != action) return;
            state.Pending = null;
        }
        else if (action.Confirm)
        {
            state.Pending = action;
            state.ReturnPage = state.Page;
            state.Page = Page.Confirm;
            state.Offset = 0;
            state.Status = "This interrupts the current match. Confirm to continue.";
            return;
        }
        state.Status = $"Running: {action.Label}";
        RunAction(player.SteamID, action);
        if (action.Confirm) Hide(player);
    }

    private static void Back(MenuState state)
    {
        if (state.Page == Page.Confirm)
        {
            state.Pending = null;
            state.Page = state.ReturnPage;
        }
        else state.Page = state.Page switch
        {
            Page.Competitive or Page.ArmsRace or Page.Modes => Page.Maps,
            Page.Difficulty => Page.Bots,
            Page.Gravity or Page.Speed => Page.Fun,
            _ => Page.Home,
        };
        state.Offset = 0;
        state.Status = "Choose an option.";
    }

    private void Render(CCSPlayerController player)
    {
        if (_layout is not { IsValid: true } || !_open.TryGetValue(player.SteamID, out var state)) return;
        var entries = Entries(state);
        if (state.Offset >= entries.Count) state.Offset = Math.Max(0, ((entries.Count - 1) / RowsPerPage) * RowsPerPage);
        SetText(player, "v2_title", state.Page == Page.Confirm ? "Confirm change" : Title(state.Page));
        SetText(player, "v2_status", state.Status);
        SetText(player, "v2_page", $"{state.Offset / RowsPerPage + 1} / {Math.Max(1, (entries.Count + RowsPerPage - 1) / RowsPerPage)}");
        for (var i = 0; i < RowsPerPage; i++)
        {
            var present = state.Offset + i < entries.Count;
            var id = $"v2_row_{i}";
            _layout.SetHasClassForPlayer(player, id, "hidden", !present);
            SetText(player, $"{id}_text", present ? entries[state.Offset + i].Label : "");
        }
        _layout.SetHasClassForPlayer(player, "v2_prev", "hidden", state.Offset == 0);
        _layout.SetHasClassForPlayer(player, "v2_next", "hidden", state.Offset + RowsPerPage >= entries.Count);
        _layout.SetHasClassForPlayer(player, "v2_back", "hidden", state.Page == Page.Home);
    }

    private void SetText(CCSPlayerController player, string id, string value) =>
        _layout!.SetDialogVariableStringForPlayer(player, id, "text", value);

    private static string Title(Page page) => page switch
    {
        Page.Home => "CS2 TOOLKIT · ADMIN BETA",
        Page.Maps => "MAPS & MODES", Page.Competitive => "COMPETITIVE MAPS",
        Page.ArmsRace => "ARMS RACE MAPS", Page.Modes => "MODE PRESETS",
        Page.Bots => "BOTS", Page.Difficulty => "BOT DIFFICULTY",
        Page.Voice => "LIVE VOICE", Page.Weapons => "WEAPONS",
        Page.Fun => "FUN", Page.Gravity => "GRAVITY", Page.Speed => "GAME SPEED",
        _ => "CONFIRM CHANGE",
    };

    private static Entry Go(string label, Page page) => new(label, Destination: page);
    private static Entry Do(string label, string command, bool confirm = false, params string[] args) =>
        new(label, Action: new ActionSpec(label, command, args, confirm));

    private static IReadOnlyList<Entry> Entries(MenuState state) => state.Page switch
    {
        Page.Home => [Go("Maps & modes", Page.Maps), Go("Bots", Page.Bots), Go("Voice", Page.Voice),
            Go("Weapons", Page.Weapons), Go("Fun", Page.Fun)],
        Page.Maps => [Do("Home · Competitive / Dust II", "default", true),
            Go("Competitive maps", Page.Competitive), Go("Arms Race maps", Page.ArmsRace),
            Do("Rush · rush_001", "rush-map", true, "rush_001"), Go("Mode presets", Page.Modes)],
        Page.Competitive => new[] { "de_dust2", "de_mirage", "de_inferno", "de_nuke", "de_overpass",
            "de_vertigo", "de_ancient", "de_anubis", "de_cache", "de_train" }
            .Select(map => Do(map, "change-map", true, map)).ToArray(),
        Page.ArmsRace => [Do("Pool Day", "armsrace-map", true, "ar_pool_day"),
            Do("Shoots", "armsrace-map", true, "ar_shoots"),
            Do("Baggage", "armsrace-map", true, "ar_baggage")],
        Page.Modes => [Do("Competitive MR12", "mode", true, "comp_mr12"),
            Do("Casual", "mode", true, "casual"), Do("Wingman", "mode", true, "wingman"),
            Do("Deathmatch", "mode", true, "deathmatch"), Do("Retakes", "mode", true, "retakes"),
            Do("Arms Race", "mode", true, "armsrace"), Do("Rush", "rush-map", true, "rush_001")],
        Page.Bots => [Do("Turn bots on", "bot-on"), Do("Turn off & kick all", "bot-off"),
            Do("Add 1 bot", "bots-add", false, "1"), Do("Add 3 bots", "bots-add", false, "3"),
            Do("Add 5 bots", "bots-add", false, "5"), Do("Target: 0", "bot-quota", false, "0"),
            Do("Target: 5", "bot-quota", false, "5"), Do("Target: 10", "bot-quota", false, "10"),
            Go("Difficulty", Page.Difficulty)],
        Page.Difficulty => [Do("Easy", "bot-difficulty", false, "0"),
            Do("Normal", "bot-difficulty", false, "1"), Do("Hard", "bot-difficulty", false, "2"),
            Do("Expert", "bot-difficulty", false, "3")],
        Page.Voice => [Do("Team only", "voice-mode", false, "team"),
            Do("Dead & living teammates", "voice-mode", false, "team-dead"),
            Do("Dead players across teams", "voice-mode", false, "dead-all"),
            Do("Both teams · T + CT", "voice-mode", false, "both-teams"),
            Do("Everyone + spectators", "voice-mode", false, "all")],
        Page.Weapons => [Do("Block AWP", "weapons-set", false, "weapon_awp"),
            Do("Block AWP & Scout", "weapons-set", false, "weapon_awp,weapon_ssg08"),
            Do("Clear restrictions", "weapons-clear")],
        Page.Fun => [Do("Spawn 1 chicken", "fun-chickens", false, "1"),
            Do("Spawn 5 chickens", "fun-chickens", false, "5"),
            Do("Clear chickens", "fun-chickens-clear"), Go("Gravity", Page.Gravity),
            Go("Game speed", Page.Speed)],
        Page.Gravity => [Do("Normal · 800", "fun-gravity", false, "800"),
            Do("Low · 400", "fun-gravity", false, "400"), Do("Moon · 200", "fun-gravity", false, "200")],
        Page.Speed => [Do("Normal · 1.0", "fun-speed", false, "1.0"),
            Do("Fast · 1.5", "fun-speed", false, "1.5"), Do("Slow · 0.5", "fun-speed", false, "0.5")],
        Page.Confirm => state.Pending is { } pending
            ? [new Entry($"Confirm: {pending.Label}", Action: pending), Do("Cancel", "cancel")]
            : [Do("Cancel", "cancel")],
        _ => [],
    };

    private void RunAction(ulong steamId, ActionSpec action)
    {
        _ = Task.Run(async () =>
        {
            if (!await _actionGate.WaitAsync(0))
            {
                Reply(steamId, "Another toolkit action is running.");
                return;
            }
            try
            {
                var script = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? "", "cs2-ds", "cs2-admin.sh");
                if (!File.Exists(script)) throw new FileNotFoundException("Toolkit admin script is missing", script);
                var start = new ProcessStartInfo(script)
                {
                    UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,
                };
                start.ArgumentList.Add(action.Command);
                foreach (var arg in action.Args) start.ArgumentList.Add(arg);
                using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start toolkit action");
                var stdout = process.StandardOutput.ReadToEndAsync();
                var stderr = process.StandardError.ReadToEndAsync();
                await process.WaitForExitAsync();
                var output = await stdout;
                var error = await stderr;
                if (process.ExitCode == 0)
                {
                    Logger.LogInformation("Admin {SteamId} ran {Command}: {Output}", steamId, action.Command, output.Trim());
                    Reply(steamId, $"{action.Label}: done.");
                }
                else
                {
                    Logger.LogWarning("Toolkit action {Command} failed: {Output} {Error}", action.Command, output.Trim(), error.Trim());
                    Reply(steamId, $"{action.Label}: failed. Check server logs.");
                }
            }
            catch (Exception exception)
            {
                Logger.LogError(exception, "Toolkit action {Command} failed", action.Command);
                Reply(steamId, $"{action.Label}: failed. Check server logs.");
            }
            finally { _actionGate.Release(); }
        });
    }

    private void Reply(ulong steamId, string message) => Server.NextFrame(() =>
    {
        var player = Utilities.GetPlayerFromSteamId64(steamId);
        if (player is not { IsValid: true }) return;
        player.PrintToChat($"[CS2 Toolkit] {message}");
        if (!_open.TryGetValue(steamId, out var state) || _layout is not { IsValid: true }) return;
        state.Status = message;
        SetText(player, "v2_status", state.Status);
    });
}
