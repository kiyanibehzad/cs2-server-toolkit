# In-game admin menu V2 beta

This is a separate mouse-driven menu based on CS2's `custom_hud_layout` and
CounterStrikeSharp 1.0.375. The existing `!admin` / `!toolkit` menu remains
installed and unchanged. The beta opens with `!adminv2`, `!toolkitv2`, or
`css_adminv2` in the client console. An optional client binding is
`bind F6 css_adminv2`. After opening, all menu choices are mouse clicks; no
`!1` / `!2` messages are needed. Click Close or run the command again to
release the cursor.

The menu uses the same `@cs2toolkit/admin` access list and the existing
`~/cs2-ds/cs2-admin.sh` operations. Map and mode changes require a second
confirmation. It does not expose maintenance, credentials, bans, or arbitrary
RCON commands.

## Test on one client

1. Install the existing optional in-game menu first, so Metamod,
   CounterStrikeSharp, and your admin SteamID are configured.
2. On the **Windows PC where CS2 is installed**, enable Counter-Strike Workshop
   Tools in CS2 Settings, then let Steam download them and quit the game.
3. In PowerShell, from this repository, run:

   ```powershell
   .\plugins\Cs2ToolkitMenuV2\hud\build.ps1 -Cs2 'C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive' -InstallLocal
   ```

   Adjust `-Cs2` if Steam uses another library. The script compiles the XML
   and CSS, checks both outputs, and copies them to this client's game files.
   Restart CS2 after each layout change because Panorama caches layouts.
4. On the Linux server, from the toolkit repository, run:

   ```bash
   ./scripts/cs2-ingame-menu-v2.sh install-local-test
   ```

   It installs only `Cs2ToolkitMenuV2` and restarts the active CS2 service.
   `status` checks the plugin; `remove` removes the beta plugin. The original
   menu remains available throughout.
5. Join as an authorized admin and enter `!adminv2` once. Use the mouse to
   navigate. If the layout is absent or blank, enter `css_adminv2` in the
   client console to release input, then verify the compiled client resources.

The server plugin alone cannot render a menu. CS2 loads the XML/CSS layout
from the **player's client**. The local test copies compiled resources onto
one PC. To roll the beta out to other players, publish the compiled addon
`cs2_toolkit_admin_v2` to the CS2 Workshop and deliver its Workshop ID through
MultiAddonManager. That distribution step is deliberately separate from the
one-client test. The menu is still a beta until it has been tested inside CS2.

## Build the server plugin

The committed `dist/` files were built from this source with .NET 10:

```bash
dotnet build plugins/Cs2ToolkitMenuV2/Cs2ToolkitMenuV2.csproj -c Release
```

CounterStrikeSharp is referenced at version 1.0.375. The package is excluded
from the runtime artifact because the server supplies the API.
