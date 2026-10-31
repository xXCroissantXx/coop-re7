# Changelog

## v0.7 (2026-10-31)
- **Enemy movement** (early): each enemy is run by the game of the player nearest to it; the other game turns
  that enemy's own AI off and has it follow the running game (position and animation, 10 updates a second).
  When the other player gets clearly closer (3 m), the enemy is handed over, so enemies always chase a real
  player and their hits land on the right person. If the other game goes quiet, enemies come back after 3 s.
- **Fixed: your friend could disappear for good after they restarted their game** (their clock restarted and
  every update looked stale). Same fix for enemy updates.
- Fixed: your friend's Ethan could get stuck hidden, or visible but frozen without a nameplate, after a
  cutscene or a rebuild during loading.
- **Bot**: new "follow me" mode (walks your path, waits near you, copies your stance); "stay here" mode.
- **Testing**: fast-forward cutscenes (8x); record an enemy and replay it with its AI off; hand an enemy to
  the bot and back.

## v0.6 (2026-10-31)
- **Shared enemy damage and deaths** (first step of enemy sync). When you hurt an enemy, it loses the same
  health in your friend's game; when you kill it (or knock Jack down), it goes down there too. A regular
  enemy your friend killed in an area you haven't reached yet is already dead when you get there. Only
  between players in the same chapter.
- These events use Steam's guaranteed delivery, so a kill can't get lost.
- On screen: "Enemies: your friend took down ..." for a few seconds.
- Testing: the bot can hit or take down the enemy nearest to you.
- Not yet: enemies still move separately in each game, and hits don't make them flinch on the other screen.

## v0.5 (2026-10-31)
- **Footsteps**: you hear your friend's footsteps where they walk, using RE7's own walk, jog and crouch
  sounds. Switch off with **Friend's footsteps** in the RE7 Co-op window.
- **Installer**: warns when RE7 is on the older non-RT version (Steam beta `dx11_non-rt`), which is untested;
  its closing steps now describe the friend list.
- Checked: Steam names in Russian, Chinese, Japanese and Korean already show correctly on the nameplate and
  in the friend list.

## v0.4 (2026-10-31)
- **Pick your friend from a list**: the RE7 Co-op window lists your Steam friends who are running RE7 Co-op,
  each with a **Connect** button. No more copying SteamIDs (still possible under *Connect with a SteamID
  instead*).
- **Invites**: connecting to a friend shows them "*<name>* invited you to co-op" on screen; they click
  **Accept**. Uses Steam rich presence, so nothing else needs setting up.
- **Go to my friend's chapter**: jumps to the start of your friend's chapter (saving is switched off first).
  Chapter names are shown instead of numbers.
- **Teleport to my friend** now lands on ground your friend walked on, and only within 40 m (RE7 only loads
  the area around you, so long warps could land outside the map).
- The friend list warns when your friend runs a different coop-re7 version.
- Fixed: a script error while a chapter was loading. Testing: the bot can pretend to be in another chapter.

## v0.3 (2026-10-29)
- **One-click installer** (`Install.cmd`): finds RE7 in Steam, copies it to a co-op folder, downloads
  REFramework + C# add-on from the official release with SHA-256 checks, installs the mod, backs up saves,
  creates a desktop shortcut. Re-running it updates the mod and keeps your settings.
- **Allow saving** switch (off by default) with automatic save backups at every launch and on demand; the
  newest 20 are kept.
- **On-screen status** in the top-left: connection, friend's name, ping, "friend is in another chapter",
  version-mismatch warning, saving state.
- **Nameplate** with your friend's Steam name over their Ethan.
- **Teleport to my friend** button.
- **RE7 Co-op window**: a floating window (opens with the REFramework menu) with Connect, saving and display
  options, and a Testing section.
- **Chapter switcher** (Testing): jump to any chapter with RE7's own chapter jump. Saving is switched off first
  so a test jump is never saved. Starting together in the same chapter is the easiest way to meet up.
- Fixed: the ghost could separate from its position while crouching (the crouch idle clip jammed the
  animation, and a blend was mistaken for an error).
- Fixed: head look stopped working after Rebuild Ethan.
- Bot: follows you to new chapters and after loads or teleports.
- **Save protection fix:** with saving off, chapter jumps could still write your save files through internal
  save paths. These are now blocked too (verified: save files unchanged across a chapter jump). If you used
  an earlier test build's chapter switcher, restore your saves from the backup the installer made.
- The co-op ghost also works in sections played as other characters (e.g. the videotapes).
- The other player is hidden while you watch a cutscene, and while they watch one (shown as "Friend is
  watching a cutscene").
- Chapter switcher allows one jump at a time (rapid jumps could leave cutscenes invisible and you outside
  the map). Collision never pushes you during cutscenes or loads.
- The packet now carries the chapter and a round-trip echo, used for the ping (the format is unchanged in size,
  but v0.2 and v0.3 players won't understand each other's chapter and ping).

## v0.2 (2026-10-29)
- Ethan builds himself automatically. Walk, jog and crouch in four directions, idle, head look, smoothed turns
  and blends.
- Can't walk through the other player.
- Ghost rebuilds after save loads, deaths and area changes, and hides when the other player's data stops.
- In-game **Connect** panel (copy your SteamID, paste your friend's).

## v0.1 (2026-10-29)
- First prototype: the other player as a ghost body over Steam relay.
