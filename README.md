# ChainFinder

<img width="850" height="618" alt="Arkine_2026 10 16_153055" src="https://github.com/user-attachments/assets/4493eba4-c90c-40ef-89cf-6d85021abcd9" />


An Ashita v4 addon that shows **skillchains** while you are in the game's own menus.

- **Self** (`/sc self`): hover a weapon skill and see every chain you can make with your own weapon skills (levels 1-4, 2-5 steps).
- **Party** (`/sc party`): the hovered skill plus up to 5 other weapon types.
- **Find** (`/sc find`): chains between weapon types you choose, optionally using blue magic (Chain Affinity) and pet Ready moves, with a pet drop-down.
- **Blue Chains**: in the spell menu as BLU - Chain Affinity chains, plus a BURST list coloured by element (learned and equipped spells highlighted).
- **Pet Chains**: in Pet Commands > Ready - chains between your pet's Ready moves, optionally with weapon skills.
- `/sc settings` opens a window with every setup command as a button.

Every window has Level (1-4 / any) and Steps (2-5) filters. Each skill is listed on its own line, and only chains of exactly the chosen number of steps are shown.

## Install

1. Make sure no older copy of the addon is loaded (`/addon unload chainfinder`).
2. Clone (or download and unzip) this repository into your Ashita addons folder, **in a folder named `chainfinder`**:
   ```
   cd <Ashita>\addons
   git clone https://github.com/Adamantking/chainfinder.git chainfinder
   ```
3. In game: `/addon load chainfinder`  (add it to your default script to load it on startup).

> Everything here is tested to the best of my ability, changes/fixes will be made as necessary.
> Claude was used heavily in the creation of this addon.

## Commands

`/sc help` prints every command. The main ones: `/sc self`, `/sc party`, `/sc find`, `/sc blu`, `/sc settings`, `/sc level`, `/sc steps`, `/sc pet <name|auto>`, `/sc ready`, `/sc bluset`.

## Data

`wsdata.lua` holds weapon skill and blue magic properties, `petdata.lua` the Ready moves of each pet (all CatsEyeXI jug pets). Missing a pet or skill? Add it to those files and send a pull request.

## Credits and licence

- Skillchain property data originates from Ivaar's Skillchains addon; pet and jug data from BG-Wiki and FFXIclopedia.
- Reading the highlighted menu entry directly from the game follows the approach of [tirem/XIUI](https://github.com/tirem/XIUI) (GPL-3.0), so this addon is released under the **GNU GPL v3** - see `LICENSE`.
- Look and feel inspired by YunaGearOpt.

Copyright (C) 2026 Adamantking
