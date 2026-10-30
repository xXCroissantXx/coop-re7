# coop-re7: online co-op for Resident Evil 7 (prototype, v0.3)

Play Resident Evil 7 with a friend over the internet. Each of you sees the other as a full-body **Ethan** who
walks, jogs, crouches, sidesteps and looks around where they do, over Steam (no port forwarding).

**What's shared today:** where each player is and what they're doing (movement, stance, looking, which chapter).
**Not shared yet:** enemies, items, doors and story. Each player plays their own copy of the world.

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
3. Click **Copy** next to *Your SteamID* and send it to your friend. Paste **theirs** into *Friend's SteamID*
   and click **Connect to friend**. Both of you do this.
4. The top-left corner shows **Co-op: connected to <name> - <ping> ms** once their data arrives, and they appear
   as Ethan with their name over their head.

Your friend's ID is saved, so next time it reconnects by itself.

**Tip: start together.** Both open **Testing → Chapter switcher** in the RE7 Co-op window and jump to the
same chapter (for example **Chapter3**). You both start at exactly the same spot, and it loads much faster
than Continue. Nothing from a jump is saved (the switcher turns saving off first).

### Options (RE7 Co-op window)

| Option | What it does |
|---|---|
| **Allow saving** | Off by default: nothing you do is saved. Turn on to save normally. Your save folder is backed up automatically (at every launch and when you turn this on; the last 20 backups are kept in `reframework\data\save_backups`). The co-op copy shares Steam Cloud saves with your normal RE7. |
| **Back up saves now** | An extra backup on demand. |
| **On-screen status** | The top-left status lines (connection, ping, chapter, saving). |
| **Nameplate over your friend** | Their Steam name above their Ethan. |
| **Teleport to my friend** | Jump next to them if you got separated (same chapter only). |
| **Test with bot** | A fake player walks around you (walking, jogging, crouching, in every direction), to try everything alone. |
| **Chapter switcher** (Testing) | Jump straight to any chapter. For testing; saving is switched off first. |
| **Rebuild Ethan** / **Reload last save** (Testing) | Fix a broken-looking ghost / reload your save (what Continue does). |

## Known limits

- Only position, movement, stance, looking and chapter are shared. Enemies, items, doors and story are separate.
- You only see your friend while both of you are playing as Ethan (not in Mia's or other characters' sections).
- Tested on one PC against a simulated player; a real two-player session hasn't been verified yet.

## Troubleshooting

| What you see | Try |
|---|---|
| "Waiting for your friend" on both sides | Each of you must paste the *other* person's SteamID and click Connect |
| "Friend's packets don't match" | You're on different coop-re7 versions; both install the same release |
| "Friend is in another chapter" | Load into the same chapter |
| Their label moves but no body | Wait a few seconds, or press **Rebuild Ethan** in the coop_dummy menu |

Logs for bug reports: `reframework\data\coopnet_status.txt` and `reframework\data\coop_dummy_log.txt` in
your co-op folder. `coopnet_status.txt` contains your SteamID and Steam name; remove them before posting
publicly.

## How it works

REFramework Lua scripts build the other player from Ethan's own full-body "shadow" model (RE7 renders it only
for the player's shadow) and animate it with his own animations. A C# plugin sends 30 small updates a second
over Steam's relay network (`ISteamNetworkingMessages`). Details and everything learned along the way are in
[docs/NOTES.md](docs/NOTES.md) and the coop-anything write-up `games/resident-evil-7`.
