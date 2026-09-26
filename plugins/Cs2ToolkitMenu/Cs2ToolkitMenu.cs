using System.Diagnostics;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Modules.Admin;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Menu;
using Microsoft.Extensions.Logging;

namespace Cs2ToolkitMenu;

[MinimumApiVersion(80)]
public sealed class Cs2ToolkitMenu : BasePlugin
{
    public override string ModuleName => "CS2 Server Toolkit Menu";
    public override string ModuleVersion => "1.0.0";
    public override string ModuleAuthor => "CS2 Server Toolkit";
    public override string ModuleDescription => "Admin-only in-game controls for CS2 Server Toolkit";

    private const string Permission = "@cs2toolkit/admin";
    private readonly SemaphoreSlim _actionGate = new(1, 1);

    [ConsoleCommand("css_toolkit", "Open the CS2 Server Toolkit admin menu")]
    [ConsoleCommand("css_admin", "Open the CS2 Server Toolkit admin menu")]
    public void OnMenuCommand(CCSPlayerController? player, CommandInfo command)
    {
        if (player is null || !player.IsValid) return;
        if (!IsAdmin(player))
        {
            player.PrintToChat("[CS2 Toolkit] You do not have menu access.");
            return;
        }
        OpenMain(player);
    }

    private static bool IsAdmin(CCSPlayerController player) =>
        player.IsValid && AdminManager.PlayerHasPermissions(player, Permission);

    private CenterHtmlMenu NewMenu(string title) => new(title, this);

    private void Open(CCSPlayerController player, CenterHtmlMenu menu)
    {
        if (IsAdmin(player)) MenuManager.OpenCenterHtmlMenu(this, player, menu);
    }

    private void Back(CenterHtmlMenu menu) => menu.AddMenuOption("Back", (player, _) => OpenMain(player));

    private void Action(CenterHtmlMenu menu, string label, string command, params string[] args) =>
        menu.AddMenuOption(label, (player, _) => RunAction(player, label, command, args));

    private void OpenMain(CCSPlayerController player)
    {
        var menu = NewMenu("CS2 Toolkit - Admin");
        menu.AddMenuOption("Maps and modes", (p, _) => OpenMaps(p));
        menu.AddMenuOption("Bots", (p, _) => OpenBots(p));
        menu.AddMenuOption("Voice", (p, _) => OpenVoice(p));
        menu.AddMenuOption("Weapons", (p, _) => OpenWeapons(p));
        menu.AddMenuOption("Fun", (p, _) => OpenFun(p));
        Open(player, menu);
    }

    private void OpenMaps(CCSPlayerController player)
    {
        var menu = NewMenu("Maps and modes");
        Action(menu, "Home: Competitive / Dust II", "default");
        menu.AddMenuOption("Competitive maps", (p, _) => OpenCompetitiveMaps(p));
        menu.AddMenuOption("Arms Race maps", (p, _) => OpenArmsRace(p));
        Action(menu, "Rush", "rush-map", "rush_001");
        menu.AddMenuOption("Mode presets", (p, _) => OpenModes(p));
        Back(menu);
        Open(player, menu);
    }

    private void OpenCompetitiveMaps(CCSPlayerController player)
    {
        var menu = NewMenu("Competitive maps");
        foreach (var map in new[] { "de_dust2", "de_mirage", "de_inferno", "de_nuke", "de_overpass", "de_vertigo", "de_ancient", "de_anubis", "de_cache", "de_train" })
            Action(menu, map, "change-map", map);
        menu.AddMenuOption("Back", (p, _) => OpenMaps(p));
        Open(player, menu);
    }

    private void OpenArmsRace(CCSPlayerController player)
    {
        var menu = NewMenu("Arms Race maps");
        Action(menu, "Pool Day", "armsrace-map", "ar_pool_day");
        Action(menu, "Shoots", "armsrace-map", "ar_shoots");
        Action(menu, "Baggage", "armsrace-map", "ar_baggage");
        menu.AddMenuOption("Back", (p, _) => OpenMaps(p));
        Open(player, menu);
    }

    private void OpenModes(CCSPlayerController player)
    {
        var menu = NewMenu("Game mode presets");
        Action(menu, "Competitive MR12", "mode", "comp_mr12");
        Action(menu, "Casual", "mode", "casual");
        Action(menu, "Wingman", "mode", "wingman");
        Action(menu, "Deathmatch", "mode", "deathmatch");
        Action(menu, "Retakes", "mode", "retakes");
        Action(menu, "Arms Race", "mode", "armsrace");
        Action(menu, "Rush", "rush-map", "rush_001");
        menu.AddMenuOption("Back", (p, _) => OpenMaps(p));
        Open(player, menu);
    }

    private void OpenBots(CCSPlayerController player)
    {
        var menu = NewMenu("Bot management");
        Action(menu, "Turn bots on", "bot-on");
        Action(menu, "Turn off and kick bots", "bot-off");
        Action(menu, "Add 1 bot", "bots-add", "1");
        Action(menu, "Add 3 bots", "bots-add", "3");
        Action(menu, "Add 5 bots", "bots-add", "5");
        Action(menu, "Set target: 0", "bot-quota", "0");
        Action(menu, "Set target: 5", "bot-quota", "5");
        Action(menu, "Set target: 10", "bot-quota", "10");
        menu.AddMenuOption("Difficulty", (p, _) => OpenBotDifficulty(p));
        Back(menu);
        Open(player, menu);
    }

    private void OpenBotDifficulty(CCSPlayerController player)
    {
        var menu = NewMenu("Bot difficulty");
        Action(menu, "Easy", "bot-difficulty", "0");
        Action(menu, "Normal", "bot-difficulty", "1");
        Action(menu, "Hard", "bot-difficulty", "2");
        Action(menu, "Expert", "bot-difficulty", "3");
        menu.AddMenuOption("Back", (p, _) => OpenBots(p));
        Open(player, menu);
    }

    private void OpenVoice(CCSPlayerController player)
    {
        var menu = NewMenu("Live voice");
        Action(menu, "Team only", "voice-mode", "team");
        Action(menu, "Dead and living teammates", "voice-mode", "team-dead");
        Action(menu, "Dead players across teams", "voice-mode", "dead-all");
        Action(menu, "Both teams: T + CT", "voice-mode", "both-teams");
        Action(menu, "Everyone including spectators", "voice-mode", "all");
        Back(menu);
        Open(player, menu);
    }

    private void OpenWeapons(CCSPlayerController player)
    {
        var menu = NewMenu("Weapon restrictions");
        Action(menu, "Block AWP", "weapons-set", "weapon_awp");
        Action(menu, "Block AWP and Scout", "weapons-set", "weapon_awp,weapon_ssg08");
        Action(menu, "Clear restrictions", "weapons-clear");
        Back(menu);
        Open(player, menu);
    }

    private void OpenFun(CCSPlayerController player)
    {
        var menu = NewMenu("Fun");
        Action(menu, "Spawn 1 chicken", "fun-chickens", "1");
        Action(menu, "Spawn 5 chickens", "fun-chickens", "5");
        Action(menu, "Clear chickens", "fun-chickens-clear");
        menu.AddMenuOption("Gravity", (p, _) => OpenGravity(p));
        menu.AddMenuOption("Game speed", (p, _) => OpenSpeed(p));
        Back(menu);
        Open(player, menu);
    }

    private void OpenGravity(CCSPlayerController player)
    {
        var menu = NewMenu("Gravity");
        Action(menu, "Normal: 800", "fun-gravity", "800");
        Action(menu, "Low: 400", "fun-gravity", "400");
        Action(menu, "Moon: 200", "fun-gravity", "200");
        menu.AddMenuOption("Back", (p, _) => OpenFun(p));
        Open(player, menu);
    }

    private void OpenSpeed(CCSPlayerController player)
    {
        var menu = NewMenu("Game speed");
        Action(menu, "Normal: 1.0", "fun-speed", "1.0");
        Action(menu, "Fast: 1.5", "fun-speed", "1.5");
        Action(menu, "Slow: 0.5", "fun-speed", "0.5");
        menu.AddMenuOption("Back", (p, _) => OpenFun(p));
        Open(player, menu);
    }

    private void RunAction(CCSPlayerController player, string label, string command, string[] args)
    {
        if (!IsAdmin(player)) return;
        var steamId = player.SteamID;
        _ = Task.Run(async () =>
        {
            if (!await _actionGate.WaitAsync(0))
            {
                Reply(steamId, "Another toolkit action is running.");
                return;
            }
            try
            {
                var home = Environment.GetEnvironmentVariable("HOME") ?? "";
                var script = Path.Combine(home, "cs2-ds", "cs2-admin.sh");
                if (!File.Exists(script)) throw new FileNotFoundException("Toolkit admin script is missing", script);
                var start = new ProcessStartInfo(script)
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                start.ArgumentList.Add(command);
                foreach (var arg in args) start.ArgumentList.Add(arg);
                using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start toolkit action");
                var stdout = process.StandardOutput.ReadToEndAsync();
                var stderr = process.StandardError.ReadToEndAsync();
                await process.WaitForExitAsync();
                var output = await stdout;
                var error = await stderr;
                if (process.ExitCode == 0)
                {
                    Reply(steamId, $"{label}: done.");
                    Logger.LogInformation("Admin {SteamId} ran {Command}: {Output}", steamId, command, output.Trim());
                }
                else
                {
                    Reply(steamId, $"{label}: failed. Check server logs.");
                    Logger.LogWarning("Toolkit action {Command} failed: {Output} {Error}", command, output.Trim(), error.Trim());
                }
            }
            catch (Exception exception)
            {
                Reply(steamId, $"{label}: failed. Check server logs.");
                Logger.LogError(exception, "Toolkit action {Command} failed", command);
            }
            finally
            {
                _actionGate.Release();
            }
        });
    }

    private static void Reply(ulong steamId, string message) => Server.NextFrame(() =>
    {
        var player = Utilities.GetPlayerFromSteamId64(steamId);
        if (player is { IsValid: true }) player.PrintToChat($"[CS2 Toolkit] {message}");
    });
}
