Date: 2026-10-14

# Toolkit - Read me

Written by Claude. Michal asked on 2026-10-14 to keep everything needed "to make more games the same quality". These are the tools Claude made while building Build A Bee Empire. They used to live in a folder that is deleted together with the chat, so they are kept here now.

Start with [[Playbook - Make a new Roblox game]].

## What is in here

- **blender/**: the Python scripts that build every 3D model in Blender (chunky toy style).
  - `toykit.py` is the shared kit: rounded blocks, painting, camera, light, rendering. Every other script uses it. Start a new game's models from this file.
  - `bees.py`, `hives.py`, `props.py`, `garden.py`, `rollarea.py`, `shop.py`, `rewards.py`, `halloween.py`, `halloween_gear.py`, `walkspeed.py`, `uiicons.py`: the Bee Empire models and menu pictures. Good examples to copy from.
  - `thumbnails.py`: the three game thumbnails and the icon (whole scenes with a beekeeper kid).
  - How to run them: [[How-to - Make 3D models in Blender]].
- **icon-tools/**: picture tools for Windows PowerShell (no Python needed).
  - `finish-blender-icons.ps1`: turns Blender's renders (`blender/out/icon-*.png`) into finished 512 x 512 menu pictures with the dark ink outline, in `ui-icons/`.
  - `make-fx.ps1`: draws the white glow pictures (rays, glow, twinkle) used by the reveal screens.
  - `serve.ps1`: shows the pictures on a tiny local web address so Roblox Studio can upload them. It stops by itself after 15 minutes, or when `http://localhost:8617/quit` is opened.
  - `asset-ids.txt`: every picture's Roblox number, so nothing is uploaded twice.
  - `IconRenderer.cs`, `render-icons.ps1`, `models.txt`: the very first picture maker (before Blender). Only the outline part is still used.
- **ui-icons/**: every finished menu picture of Bee Empire (coin, jar, gear, calendar, backpack, shop, bees, hives, passes, glow pictures). Some (coin, gear, music, speaker, calendar, backpack, lock, glow pictures) fit almost any game.
- **reference-notes-ant-game/**: Claude's notes from watching Michal play Build An Ant Empire: its layout, menus, colours and sizes. Ideas only: never copy another game's pictures, models or names.

## Where the game's code is

The code is not copied here. It lives inside the Bee Empire place on Roblox (placeId 86089880482484), which Roblox keeps saved. For a new game, open both places in Roblox Studio: Claude can read every script of Bee Empire through the Studio connection and reuse what fits. What each script does: [[How-to - Build the game's code]].

The place also holds `ServerStorage.BeeEmpireDev.NOTES`, the full building log, and backups of every change.

Related: [[Notebook - Start here]], [[Playbook - Make a new Roblox game]], [[How-to - Make a menu picture]], [[How-to - Make a thumbnail]]
