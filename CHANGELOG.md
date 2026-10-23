# Changelog

## 2.0.0
- Mini mode: a "-" button in the header corner (next to X) shrinks the window to just the chain list plus a "+" button to restore it.
- Font scale 25-150% (slider, bottom right). Only text is scaled; window size and spacing are untouched.
- Puppetmaster automaton skills (frame-based) in the Pet Chains window, Find drop-down and "Pet moves" toggle.
  New: `/sc pets`, `/sc frame <harlequin|valoredge|sharpshot|stormwaker>`. Properties unverified in game.
- "Automaton" toggle (next to BLU spells / Pet moves) in Self, Find and Settings; uses the frame chosen with the Frame buttons.
- New "Aurora" look (aurora.lua): ink-dark glass panels, teal-to-violet gradient titles and glowing header rule, pill toggles. Remove the `require('aurora')(theme)` line for the classic gold theme.
- BLU chains: "WS First" toggle - chains start with a weapon skill and end with the spell.
- Nothing here has been tested in game.

## 1.9.1
- Pet Chains window (Ready menu), Weapon skills toggle.
- Only chains of exactly the chosen number of steps; each skill on its own line.
- Find: pet drop-down (all pets); learned / equipped blue spells highlighted.
- Fixed: Ready 2-step chains hidden when "Pet moves" was on; inconsistent gold highlighting.
- Added Bouncing Bertha and Dirty Sanchez.
