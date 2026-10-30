# RE7 co-op prototype v0.1: setup for both players

This is an **early prototype**. Each player sees the other as a "ghost": a full-body **Ethan** that walks,
jogs and sidesteps where the other player moves. Nothing else is shared yet: no enemies, items, doors or story.
It was tested in the **Chapter 1 start area** (outside the Baker guest house).

Both players do every step below.

## What you need
- Resident Evil 7 biohazard **on Steam**, fully updated (the current build, with ray tracing).
- Windows with the **.NET 10 runtime** (desktop or core). Check with `dotnet --list-runtimes`; you need a line with
  `Microsoft.NETCore.App 10.`. Get it from https://dotnet.microsoft.com/download/dotnet/10.0.
- Each player's **SteamID64**, a 17-digit number starting with 7656… Steam shows it under
  *Account details*, and the plugin also writes yours to `reframework/data/coopnet_status.txt` (`steamSelf=`).

## 1. Make a test copy of the game (recommended)
Copy `steamapps/common/RESIDENT EVIL 7 biohazard` (about 64 GB) to another folder and play from the copy.
Your real install stays untouched.
Create `steam_appid.txt` containing `418370` in the copy so it launches outside Steam's library.

**Back up your saves first.** They are in `Steam/userdata/<your id>/418370/remote/win64_save/`.
The copy and the real install share these save files through Steam Cloud. The included save guard blocks all
saving while the mod runs, but back up anyway.

## 2. Install REFramework (official downloads, check the hashes)
From https://github.com/praydog/REFramework-nightly/releases, release **nightly-01433**
(commit d4611aef1d63effd3a736bdf9404ea702428017d):

| File | SHA-256 |
|---|---|
| `REFramework.zip` | `b3ff4f497be6f108ef494c2c02156b61b8d04f3171378ecc0dc28c218ee296b3` |
| `csharp-api.zip` | `87a909fedbec028ccd7017cc1dfb671d9f4206f07520bcb114fc6ecd74e8629b` |

Check a hash in PowerShell with `Get-FileHash .\REFramework.zip -Algorithm SHA256`.

- From `REFramework.zip`, copy **only `dinput8.dll`** into the game copy's folder.
- Extract all of `csharp-api.zip` into the game copy's folder (it adds `reframework/plugins/...`).

## 3. Install the co-op files from this kit
Copy this kit's `reframework` folder into the game copy's folder (merge it). It contains:
- `reframework/autorun/coop_saveguard.lua`: blocks all game saving while the mod runs
- `reframework/autorun/coop_dummy.lua`: spawns and animates the ghost
- `reframework/autorun/coop_probe.lua`: small debug helper
- `reframework/plugins/source/CoopNet.cs`: networking over Steam
- `reframework/data/coopnet_config.json`: settings (see the next step)

## 4. Connect to each other (in game)
1. Start the game copy and load your save.
2. Press **Insert** and open **Script Generated UI → coop_dummy (ghost body test) → Connect**.
3. Click **Copy** next to *Your SteamID* and send it to the other player (Discord, Steam chat…).
4. Paste **their** SteamID into *Friend's SteamID* and click **Connect to friend**.

Both players do this. The status line changes to **Connected to your friend** once their data arrives.
Your friend's ID is saved, so next time it reconnects by itself. No port forwarding is needed: traffic goes
through Valve's relay. **Test with bot** switches to a fake player if you want to try things alone.

## 5. Play
1. Start Steam, then run `re7.exe` from the game copy.
2. Load a save in **Chapter 1** (the start area outside the guest house). Both players should be in the same area.
3. That's it. About 10 seconds after you can move, the other player appears as a full-body **Ethan** who walks,
   jogs, sidesteps and looks around where they do. Nothing needs clicking.

To check the connection, press **Insert** and open **Script Generated UI → coop_dummy (ghost body test)**. The
`CoopNet:` line shows `sent=`/`recv=`; both should climb on both PCs, and `relayStatus=100` means Steam's
relay is ready. **Rebuild Ethan** redoes the ghost if he ever looks wrong. Infected Mia and other models are
under **Other characters (debug)**.

## Known limits (v0.1)
- The ghost is built from Ethan's own shadow body. It's only tested in Chapter 1, and his head and face don't animate yet.
- Nothing else syncs: enemies, items, doors, story, damage. Each player plays their own world.
- Saving is blocked while the mod runs.
- The ghost's position is only meaningful while both players are in the same area.

## Troubleshooting
- `relayStatus` not 100: Steam's relay is still connecting. Wait a few seconds; check that Steam is online.
- `sent` climbs but `recv` stays 0: check that the *other* player put *your* SteamID in their config, and that both
  are running the mod.
- The ghost's label moves but the body doesn't: wait for the 3 s/0.15 s delay, or click **WALK** on the Walk clip.
- Reset scripts (Insert → ScriptRunner → Reset scripts) reloads the Lua parts. The C# plugin reloads itself
  when `CoopNet.cs` is saved.
