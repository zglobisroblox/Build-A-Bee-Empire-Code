# Build A Bee Empire

A bee-themed idle tycoon on Roblox for kids: roll bees from your Queen, fill your hive, carry honey jars to the Honey Market and grow a buzzing empire.

- Game: https://www.roblox.com/games/86089880482484
- Made by @corndoglover144, with Claude (Anthropic) writing the code through Roblox Studio.

## What is in here

- `src/`: every script in the game, laid out like Roblox Studio's Explorer.
  - `ServerScriptService/BeeEmpire`: the server. `Main` starts everything, and one service per job (saving, bees, honey, hives, upgrades, shop and passes, daily rewards, events...). The server decides everything; players' screens only ask.
  - `ReplicatedStorage/BeeEmpire`: shared by both sides. `GameConfig` holds every number in the game (prices, chances, speeds, sounds).
  - `StarterPlayer/StarterPlayerScripts/BeeEmpireClient`: the player's screen: `UIKit` (the whole look), the HUD, one Panel per window, `Effects`, `WorldFX`.
  - `ReplicatedFirst`: the loading screen.
  - `ServerStorage/BeeEmpireDev`: tools that never run in the game (the map builder, a pretend-player simulator, a sound measurer) and `NOTES`, the full building log.
- `toolkit/`: tools used to make the game outside Roblox: the Blender scripts that build every 3D model, the picture tools, the finished menu pictures, and the code exporter.

Script types follow the Rojo naming: `.server.luau` is a Script, `.client.luau` a LocalScript, `.luau` a ModuleScript.

## Updating this copy after the game changes

1. In Roblox Studio, download a copy of the place, open that copy, and use **File > Save As** with the type **Roblox XML Place Files (*.rbxlx)**, into the folder just outside this one.
2. Run the exporter in PowerShell, from this folder:

   ```
   .\toolkit\code-tools\export-scripts.ps1 -Place "..\<the file>.rbxlx" -Out ".\src"
   ```

3. In GitHub Desktop, write a short note about what changed, click **Commit**, then **Push**.

The `.rbxlx` file itself is not uploaded (see `.gitignore`): it is big, and the code is what matters here.
