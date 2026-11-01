# coop-re7: online co-op for Resident Evil 7 (prototype, v0.11)

Play Resident Evil 7 with a friend over the internet. Each of you sees the other as a full-body **Ethan** who
walks, jogs, crouches, sidesteps and looks around where they do, over Steam (no port forwarding).

> **Prototype.** Everything below was tested on one PC against a simulated player; a real two-player session
> hasn't been verified yet. [TWO-PLAYER-TEST.md](TWO-PLAYER-TEST.md) is a checklist for the first one.

## What's shared

| | |
|---|---|
| **Each other** | Position, movement, crouching, looking around, footsteps, which chapter you're in. |
| **Enemies** (early) | Each enemy is run by the game of the player nearest to it and follows along in the other game; it changes hands when the other player gets clearly closer. Damage and deaths count in both games. |
| **Doors** | A door unlocked or pushed open in one game unlocks or opens in the other. |
| **Supplies** | Ammo, healing, crafting materials and weapons picked up by one player disappear for the other. Keys, files and maps stay for both, so nobody gets stuck. |
| **Story** (early) | When one player reaches a story cutscene, the other's game plays it too; story progress is copied and only moves forward. |
| **Deaths** | With your friend connected, a fatal hit puts you **down** instead of a game over, until your friend stands next to you for 3 seconds. |
| **Saving** | Each player saves their own game; when one saves, the other is told, so you can both save at the same point. |
| Not shared | Item boxes. |

Made with [coop-anything](https://github.com/cranebeaker/coop-anything). MIT licensed.

## Install (both players)

1. Have **Resident Evil 7 biohazard on Steam**, fully updated.
2. Download the latest release zip from the **Releases** page and unzip it anywhere.
3. Double-click **Install.cmd**. It will:
   - find RE7 in your Steam libraries and **copy it** to `Documents\RE7-coop` (your normal install is not
     changed; the copy needs about 65 GB of free space);
   - download **REFramework** and its C# add-on from the official release and **check each file's SHA-256**;
   - install the co-op files, back up your saves, and put a **Start RE7 Co-op** shortcut on your desktop.
4. If the installer says **.NET 10 runtime not found**, install ".NET Runtime 10" (Windows x64) from
   https://dotnet.microsoft.com/download/dotnet/10.0 and run Install.cmd again.

Updating: unzip the new version and run Install.cmd again. It reuses your co-op folder, keeps your settings and
your friend, and replaces only the mod files. Both players need the same version.

## Play

1. Start Steam, then **Start RE7 Co-op** (desktop shortcut), and load a save.
2. Press **Insert**. A **RE7 Co-op** window opens next to the REFramework menu. Expand
   **Connect, saving and display**.
3. Under *Your Steam friends in RE7 Co-op*, click **Connect** next to your friend's name. (They appear there
   once they've started RE7 Co-op too.)
4. Your friend sees "*<your name>* invited you to co-op" at the top left of their screen. They press Insert and
   click **Accept**.
5. The top-left corner shows **Co-op: connected to <name> - <ping> ms**, and they appear as Ethan with their
   name over their head.

Your friend is remembered, so next time it reconnects by itself. Connecting by SteamID still works, under
**Connect with a SteamID instead**.

**Meeting up.** If your friend is in another chapter, click **Go to my friend's chapter**: you start at the
beginning of their chapter, then walk to each other. Nothing from the jump is saved (saving is switched off
first). **Teleport to my friend** works once you're within 40 m of them.

### Options (RE7 Co-op window)

| Option | What it does |
|---|---|
| **Allow saving** | Off by default: nothing you do is saved. Turn on to save normally. Your save folder is backed up automatically (at every launch and when you turn this on; the last 20 backups are kept in `reframework\data\save_backups`). The co-op copy shares Steam Cloud saves with your normal RE7. When one of you saves, the other sees "Your friend saved" so you can both save at the same point. |
| **Back up saves now** | An extra backup on demand. |
| **On-screen status** | The top-left status lines (connection, ping, chapter, saving, what your friend just did). |
| **Nameplate over your friend** | Their Steam name above their Ethan. |
| **Friend's footsteps** | Hear your friend's footsteps where they walk (walk, jog and crouch sounds). |
| **Share story (cutscenes and progress)** | On by default. When either of you reaches a story cutscene, the other's game plays it too (you're pulled into the scene wherever you are). Turn off if a shared scene goes wrong. |
| **Go to my friend's chapter** | Jump to the start of the chapter your friend is in. Saving is switched off first. |
| **Teleport to my friend** | Hop to them when you're within 40 m (same chapter). Further away, walk: RE7 only loads the area around you. |
| **Show all online friends** | List every online Steam friend; connecting invites them for when they start RE7 Co-op. |

**Testing** (for trying things alone):

| Option | What it does |
|---|---|
| **Test with bot** | A fake player. **Follow me**: it walks the path you walked and waits near you (and can revive you). **Walk in a circle**: it cycles every stance and direction. **Stay here**: it stands still. |
| **Bot: …** buttons | The bot "does" what a friend would: take down or hit the nearest enemy, open or unlock the nearest door, take the nearest supply, trigger the next story cutscene, pretend to be in another chapter. |
| **Take a fatal hit** | Go down on purpose (the bot revives you). |
| **Fast-forward this cutscene** / **every cutscene** | Runs the game 8x while a cutscene plays (nothing is skipped, it's just quicker). |
| **Chapter switcher** | Jump straight to any chapter. Only targets ending in `_Start` load into gameplay; saving is switched off first. |
| **Rebuild Ethan** / **Reload last save** | Fix a broken-looking friend / reload your save (what Continue does). |

## Known limits

- **Tested on one PC only**, against the bot. The invite / Accept step and everything between two real games
  is unverified.
- **Enemies:** an enemy copy doesn't show what the enemy is holding, and your friend's shots don't make it
  flinch on your screen. Bosses and Jack go down on both screens but get back up as usual.
- **Story:** if a cutscene ever hangs and you can't move, restart the game and load again (with saving off,
  nothing is lost). Turn off **Share story** if shared scenes cause trouble.
- **Deaths:** going down has no fall animation (you crouch). "Both down" and the 90-second limit are untested.
- **Saving together** hasn't been tried with a real save yet.
- **Item boxes** are separate per player.
- Tested on RE7's current (ray-tracing) version. The older non-RT version (Steam beta `dx11_non-rt`) should
  work but hasn't been tried; the installer tells you if you're on it.
- The chapter jump is a hidden developer feature of RE7: after many jumps in one session it can break (black
  screen, outside the map). Restart the game if that happens.

## Troubleshooting

| What you see | Try |
|---|---|
| Your friend isn't in the list | They need RE7 Co-op running and to be your Steam friend; or tick **Show all online friends** |
| "Waiting for your friend" | They need to click **Accept** (or **Connect** on you) |
| "Friend's packets don't match" | You're on different coop-re7 versions; both install the same release |
| "Friend is in another chapter" | Click **Go to my friend's chapter** |
| Their label moves but no body | Wait a few seconds, or press **Rebuild Ethan** (Testing) |
| Stuck after a cutscene, can't move | Restart the game and load again |
| Black screen or outside the map after chapter jumps | Restart the game |

Logs for bug reports, in your co-op folder's `reframework\data`: `coop_dummy_log.txt`,
`coop_enemies_log.txt`, `coop_world_log.txt`, `coop_story_log.txt`, `coop_revive_log.txt` and
`coopnet_status.txt`. `coopnet_status.txt` contains your SteamID and Steam name; remove them before posting
publicly.

## How it works

REFramework Lua scripts build the other player from Ethan's own full-body "shadow" model (RE7 renders it only
for the player's shadow) and animate it with his own animations. A C# plugin sends 30 small updates a second
over Steam's relay network (`ISteamNetworkingMessages`), plus guaranteed messages for things that happen once
(a kill, a door, a pickup, a cutscene) and 10-a-second enemy updates. The scripts:

| Script | Does |
|---|---|
| `coop_dummy.lua` | Your friend's Ethan, connecting, the RE7 Co-op window, on-screen status, footsteps |
| `coop_enemies.lua` | Shared enemy damage, deaths and movement (who runs each enemy) |
| `coop_world.lua` | Shared doors and supplies |
| `coop_story.lua` | Shared story cutscenes and progress; "your friend saved" |
| `coop_revive.lua` | Downed and revive |
| `coop_saveguard.lua` | Blocks saving unless you allow it |
| `CoopNet.cs` | The network plugin (Steam relay, bot, save backups) |

Details and everything learned along the way are in [docs/NOTES.md](docs/NOTES.md) and the coop-anything
write-up `games/resident-evil-7`.
