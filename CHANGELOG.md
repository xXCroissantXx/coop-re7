# Changelog

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
