# coop-re7: online co-op for Resident Evil 7 (prototype, v0.7)

Play Resident Evil 7 with a friend over the internet. Each of you sees the other as a full-body **Ethan** who
walks, jogs, crouches, sidesteps and looks around where they do, over Steam (no port forwarding).

**What's shared today:** where each player is and what they're doing (movement, stance, looking, which chapter),
and **enemies** (early): each enemy is run by the game of the player nearest to it and follows along in the
other game, and damage and deaths are shared.
**Not shared yet:** items, doors and story. Each player plays their own copy of the world.

Made with [coop-anything](https://github.com/cranebeaker/coop-anything). MIT licensed.

## Install (both players)

1. Have **Resident Evil 7 biohazard on Steam**, fully updated.
2. Download this repo (**Code → Download ZIP**) and unzip it anywhere.
3. Double-click **Install.cmd**. It will:
   - find RE7 in your Steam libraries and **copy it** to `Documents\RE7-coop` (your normal install is not
     changed; the copy needs about 65 GB of free space);
   - download **REFramework** and its C# add-on from the official release and **check each file's SHA-256**;
   - install the co-op files, back up your saves, and put a **Start RE7 Co-op** shortcut on your desktop.
4. If the installer says **.NET 10 runtime not found**, install ".NET Runtime 10" (Windows x64) from
   https://dotnet.microsoft.com/download/dotnet/10.0 and run Install.cmd again.

Updating to a newer version: unzip the new version and run Install.cmd again. It reuses your co-op folder
when it finds one, keeps your friend's SteamID, and replaces only the mod files.

## Play

1. Start Steam, then **Start RE7 Co-op** (desktop shortcut). Load a save in **Chapter 1** (the start area
   outside the guest house); be roughly in the same spot.
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
| **Allow saving** | Off by default: nothing you do is saved. Turn on to save normally. Your save folder is backed up automatically (at every launch and when you turn this on; the last 20 backups are kept in `reframework\data\save_backups`). The co-op copy shares Steam Cloud saves with your normal RE7. |
| **Back up saves now** | An extra backup on demand. |
| **On-screen status** | The top-left status lines (connection, ping, chapter, saving). |
| **Nameplate over your friend** | Their Steam name above their Ethan. |
| **Friend's footsteps** | Hear your friend's footsteps where they walk (walk, jog and crouch sounds). |
| **Go to my friend's chapter** | Jump to the start of the chapter your friend is in. Saving is switched off first. |
| **Teleport to my friend** | Hop to them when you're within 40 m (same chapter). Further away, walk: RE7 only loads the area around you. |
| **Show all online friends** | List every online Steam friend; connecting invites them for when they start RE7 Co-op. |
| **Test with bot** | A fake player to try everything alone. **Follow me**: it walks the path you walked and waits near you. **Walk in a circle**: it cycles every stance and direction. **Stay here**: it stands still. |
| **Fast-forward this cutscene** / **every cutscene** (Testing) | Runs the game 8x while a cutscene plays (nothing is skipped, it's just quicker). For testing. |
| **Chapter switcher** (Testing) | Jump straight to any chapter. For testing; saving is switched off first. |
| **Rebuild Ethan** / **Reload last save** (Testing) | Fix a broken-looking ghost / reload your save (what Continue does). |

## Known limits

- Enemies (early, same chapter only): each enemy is run by one game (the nearest player's) and copied in the
  other; it changes hands when the other player gets clearly closer. The copy doesn't show what the enemy is
  holding, and your friend's shots don't make it flinch on your screen. Bosses and Jack go down on both screens
  but get back up as usual. Items, doors and story are separate. Handovers between two real games are untested.
- Tested on one PC against a simulated player; a real two-player session (and the invite / Accept step)
  hasn't been verified yet.
- coop-re7 is tested on RE7's current (ray-tracing) version. The older non-RT version (Steam beta
  `dx11_non-rt`) should work but hasn't been tried; the installer tells you if you're on it.
- The chapter jump is a hidden developer feature of RE7: after many jumps in one session it can break (black
  screen, outside the map). Restart the game if that happens.

## Troubleshooting

| What you see | Try |
|---|---|
| Your friend isn't in the list | They need RE7 Co-op running and to be your Steam friend; or tick **Show all online friends** |
| "Waiting for your friend" | They need to click **Accept** (or **Connect** on you) |
| "Friend's packets don't match" | You're on different coop-re7 versions; both install the same release |
| "Friend is in another chapter" | Click **Go to my friend's chapter** |
| Their label moves but no body | Wait a few seconds, or press **Rebuild Ethan** in the coop_dummy menu |

Logs for bug reports: `reframework\data\coopnet_status.txt` and `reframework\data\coop_dummy_log.txt` in
your co-op folder. `coopnet_status.txt` contains your SteamID and Steam name; remove them before posting
publicly.

## How it works

REFramework Lua scripts build the other player from Ethan's own full-body "shadow" model (RE7 renders it only
for the player's shadow) and animate it with his own animations. A C# plugin sends 30 small updates a second
over Steam's relay network (`ISteamNetworkingMessages`). Details and everything learned along the way are in
[docs/NOTES.md](docs/NOTES.md) and the coop-anything write-up `games/resident-evil-7`.
