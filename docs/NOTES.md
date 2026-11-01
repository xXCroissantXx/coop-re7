# RE7 co-op: working notes

Following the cranebeaker/coop-anything playbook (AGENTS.md). Private data lives in `local/` (git-ignored).

## Goal (from owner, 2026-10-29)
- Online co-op, separate PCs, **2 players**, Steam relay.
- Path 2 (build from zero): no existing RE7 co-op mod.

## Phase 0: triage (2026-10-29)
- Hub DIRECTORY.md: no RE7 entry. No `games/resident-evil-7*` folder. Issue/PR search for "resident evil 7": nothing relevant.
- Web search: no RE7 co-op mod found (only RE1, RE2 remake, RE4 mods).
- Nearest prior art on the same engine (RE Engine + REFramework):
  - RE4 (2023) Multiplayer Mod (claybtv), nexusmods residentevil42023/mods/6539: partial, hosted relay
  - RE2 (2019) Local Couch Co-op / RE2 Party Mode: local only
  - The hub notes that the RE2/RE4 REFramework tooling may carry over to RE8/RE9 and, by extension, RE7.

## Game identity
- Store: Steam, appid 418370, buildid 22773795 (current RT/DX12 build)
- re7.exe SHA-256: D550260029B51A580E206B9A12A4EB7F4A1B4DD230BBA5DEFCCA81DA40597321
- Install size: 63.8 GB (single re_chunk_000.pak + zero-byte patch paks, dlc/)
- Engine: RE Engine

## Workspace (Phase 2)
- Test copy: `local/re7-test/` (owner's real install and saves are untouched)
- REFramework: nightly-01433 (d4611ae), `REFramework.zip` (monolithic build; supports RE7 RT build)
  - SHA-256 b3ff4f497be6f108ef494c2c02156b61b8d04f3171378ecc0dc28c218ee296b3, which matches the GitHub release digest
  - Only `dinput8.dll` installed (upstream advice for non-VR use)
  - Source: https://github.com/praydog/REFramework-nightly/releases

- Test copy verified identical to the source (19 files, 68,493,874,789 bytes, same exe hash). `dinput8.dll` and `steam_appid.txt` (418370) were added to the test copy only.
- Saves: `Steam\userdata\<id>\418370\remote\win64_save\` (data000.bin, data00-1.bin, data00-3.bin), synced with Steam Cloud. Nothing existed locally before the first launch; the files appeared at launch (most likely pulled from the cloud). The test copy shares these slots with the real install.
  - Backup: `local/save-backups/2026-10-29_1448_first-launch/` (hash-verified). Take a new backup before any session that loads or saves.
- First launch (2026-10-29 14:48), test copy, to the title screen only: **REFramework loads OK.** Detected game "re7", TDB version 70, D3D12 hooked, Lua ScriptRunner initialized, hooks finished.
  - Harmless log errors: "Failed to get type info: unknown exception" (once) and Streamline `sl.dlss_g.dll` missing (no DLSS frame generation in RE7).
  - REFramework uses its own IntegrityCheckBypass against RE7's single-player tamper check. This is not multiplayer anti-cheat, since RE7 has no multiplayer.
  - Overlay: press Insert in game.

## Phase 3: understand (started 2026-10-29)
Scripts are in `scripts/` and get copied into `local/re7-test/reframework/autorun/`. Dumps are in `local/dumps/` (derived from game data, never commit).

### Type dump (`scripts/coop_dump.lua`, title screen)
- TDB 70, 43,288 types, 162 live `app.*` managed singletons at the title screen.
- REFramework Lua gotcha: `RETypeDefinition:get_types_inheriting_from_this()` returns **all descendants**, not just direct children. Calling it on `System.Object` once lists the whole TDB. Walking it recursively is quadratic and stalls the game.
- There's no `sdk.get_tdb` or `sdk.get_managed_singletons` in this build's Lua API.

### Systems that matter for co-op
| System | Type | Notes |
|---|---|---|
| Player object | `app.ObjectManager.PlayerObj` (via.GameObject @0x88) | also `OnChageActivePlayerHandler` (sic) fires when the active player changes |
| Player components | `app.PlayerMovement`, `PlayerStatus`, `PlayerDamageController`, `PlayerGun`, `PlayerMelee`, `PlayerItem`, `PlayerCamera`, `PlayerMotionController`, `PlayerHands` | all `app.PlayerBase` / `DoomsBehavior` |
| Playable characters | `app.PlayerID` enum: Pl0000–Pl7000, Pl3100, Pl3400, Pl9000–Pl9200, Pl9999 | the game already swaps the player body (Ethan/Mia/…), so it could be reused for the 2nd player's character |
| Enemies | `app.EnemyGeneratorManager`, `app.EnemyGenerator`, `app.EnemyStatus`, `app.EnemySave` | |
| Jack stalking AI | `app.AI.MansionAI`, `AINavigationManager`, `AIWorldBlackBoard` | needs a "which player to chase" target decision |
| Damage | `app.Collision.DamageManager`, `AttackManager` | |
| Story progress | `app.GameFlowFsmManager`, `app.GameManager.ChapterNo` | |
| Doors / interact | `app.Door`, `app.DoorPush`, `app.InteractManager` | |
| Inventory | `app.InventoryManager`, `app.InventorySystem`, `SaveDataManager.getPlayerInventorySaveData(PlayerID)` | inventory is per PlayerID |
| Save | `app.SaveDataManager` | see below |

### Save guard (`scripts/coop_saveguard.lua`)
- Pre-hooks with SKIP_ORIGINAL on every save **request** entry point of `app.SaveDataManager`: `saveFileAutoRequest`, `saveFileMenuRequest`, `saveFileSystemDataRequest`, `saveFileExpansionDataRequest`, `saveFileBirthdayDataRequest`, `saveFileUniqueDataRequest`. Requests are blocked so nothing is queued and the game never waits on a save that won't happen.
- Verified 2026-10-29 14:55: 6/6 hooked, and the save files were byte-identical before and after that launch.
- **Incident (before the guard existed):** at 14:49:29, about 80 s into the first unguarded launch and still at the title screen, all three save files were rewritten (data000.bin grew from 78,140 to 87,788 bytes). Possible causes: the game writing system data on first boot, or a Steam Cloud download finishing. Unconfirmed. Both states are backed up:
  - `local/save-backups/2026-10-29_1448_first-launch/` = the state at 14:48:39
  - `local/save-backups/2026-10-29_1449_after-first-title/` = the state at 14:49:29 (current)
- Before RE7 ever ran on this PC, nothing was stored locally, so the authoritative copy of the owner's progress is in Steam Cloud.
- **Verified in game 2026-10-29 15:03:** the owner clicked Continue, and the guard logged `blocked saveFileAutoRequest` (the load-in autosave). The game kept running, and all three save files were byte-identical to the 14:49 backup afterwards.

### Player probe (`scripts/coop_probe.lua`)
- Writes the chapter, title/loading state, player name, position and rotation every 2 s, plus the component list once.
- At the title screen: `_CurrentChapter`=3 (Title), no player.
- In game (owner's Continue save, 15:03): `PlayerObj` = **`Pl0000_Chapter1`**, `_CurrentChapter`=4 (Chapter1), loadingState 5. Position updates as the player moves (-49.741, 4.862, 121.864 → -48.958, 4.887, 120.726), so Lua can read the transform live.
- 89 components are on the player GameObject (full list in the probe output). Notable ones for co-op:
  - movement/physics: `app.PlayerMovement`, `app.MovementController`, `via.physics.CharacterController`, `app.Havok.RigidBodyCharacter`
  - animation: `via.motion.Motion`, `via.motion.MotionFsm`, `app.PlayerMotionController`, `app.MotionManager`
  - combat: `app.PlayerGun`, `app.PlayerMelee`, `app.Collision.CalculateDamage`, `app.PlayerDamageController`, `app.PlayerStatus`
  - inventory/equipment: `app.Inventory`, `app.EquipManager`, `app.PlayerWeaponChange`
  - AI visibility: `app.AI.AIVisionBeacon`, which is how enemies see the player. A remote player needs one too, so enemies can target them.
  - `app.Pl2000` sits on Ethan's object (purpose unknown, to investigate) and `app.DisableSave` (a per-object save toggle).

### Ghost body (`scripts/coop_ghost.lua`), milestone 1
- Design: a bare GameObject with only a via.render.Mesh. It has no player components (no input, camera, collision, AIVisionBeacon, or save), and its transform is driven from recorded samples. For now it replays the local player's own path 3 s behind, standing in for remote packets.
- 2026-10-29 15:05, loaded with ScriptRunner > Reset scripts while in game (Chapter 1):
  - `via.GameObject.create(System.String)` created the GameObject.
  - `createComponent(System.Type)` added via.render.Mesh.
  - The player mesh copied with `getMesh -> setMesh` and `get_Material -> set_Material`, both OK.
  - The ghost transform tracks the delayed samples (positions match while the player stands still). No Lua errors.
  - "Present failed: 87a0001" in the REFramework log is DXGI_STATUS_OCCLUDED (the game window was covered or alt-tabbed). Harmless.
- **Attempt 1 (15:05): owner saw nothing.**
- **Attempt 2 (15:10):** created with `create(name, player.get_Folder())` (folder "Chapter1"), enabled all 256 parts plus DrawDefault, DrawSelf and shadow cast, and placed 2 m in front of the camera. All draw flags match the player (ReadyToDraw, MaterialReady and so on are true; the ghost was 2.1 m from the player). **Owner still saw nothing.**
  - Player mesh: `Character/Player/pl0000/pl0001/pl0001.mesh`, SkinningMesh=true, HasJoint=true. In first person some parts are off (parts mask starts `1011000111001…`).
  - Conclusion: it isn't a draw flag. The likely cause is that a skinned mesh without posed joints or a ComputeSkinning component collapses.
- **Attempt 3 (15:12):** added `via.render.ComputeSkinning` (ok) and called `copyJointsLocalMatrix(player.Transform)` every frame (no errors). Both transforms have 158 joints. **Owner saw nothing in any direction**, so the camera-direction mistake is ruled out.
- **Bisect test (`scripts/coop_bisect.lua`):** clones the nearest static prop onto 4 new GameObjects 2.5 m N/S/E/W of the player.
  - Run 1 (15:15): picked `Props/sm1751_Weeds01A` (weeds, 1.2 m away). All 4 copies reported ReadyToDraw=true and MaterialReady=true; the owner saw nothing. This is inconclusive: extra weeds outdoors are easy to miss.
  - Run 2 (15:16): picked `Props/sm1645_LargeBush02A` (4.8 m away), with `draw.world_text` labels at each object. **The owner saw the labels, with empty space at every one**, including the Ethan ghost. All reported ReadyToDraw and MaterialReady = true.
- **Conclusion:** in RE7 (TDB 70, RT build), a GameObject built at runtime with `via.GameObject.create(name, folder)` + `createComponent(via.render.Mesh)` + `setMesh`/`set_Material` from a live mesh **does not render**, even a static prop, although every readable flag says it should. The problem is the construction method, not Ethan's first-person mesh.
  - Untested theories: the render instance is only built at component start-up, before the mesh is assigned (so the mesh would have to be set before the object goes active, which `create` doesn't allow); or a shared MeshResourceHolder can't back a second render instance.
  - `draw.world_text` works and is useful for marking positions on screen.
- Both test scripts have been removed from the test copy's autorun (still in `scripts/`). Saves are still byte-identical to the 14:49 backup.

### Prefab scan (`scripts/coop_prefab.lua`, 15:20)
- Reflective walk from 2,711 app.* scene components plus the item, enemy and game managers: 33,757 objects in 0.20 s, 76 distinct loaded prefabs (list in `reframework/data/coop_prefabs.txt`).
- Item test: `Prefab/Props_Dynamic/sm2414_MailMia01A/Item/sm2414_MailMia01A_Item.pfb` was ready at once, and `instantiate(via.vec3)` returned a GameObject (its label showed), but the root only has `via.Transform` + `app.Item` with no mesh, and the owner saw nothing. Inconclusive: the item's model probably comes from child objects that app.Item sets up.
- `draw.world_text` color is **ABGR** (0xFFFFFF00 shows as cyan, not yellow).
- **Key find:** `Prefab/System/VrDummyPlayer.pfb` (`app.vr.VrManager.DummyPlayerPrefab`, instance kept in `VrManager._DummyPlayer`, gated by `IsDummyPlayerEventActive`). This is the stand-in body VR mode uses for events, i.e. Ethan as a separate visible object. It's the best ghost base so far.
- Other loaded prefabs worth knowing: `Prefab/Character/Em5550/Em5550PlArmSet.pfb`, `Prefab/TimeLine/Character/Player/{Damage,Dead,LArmCut}/*Container.pfb`, `@Hikako/Prefab/Master/HiKaKoMaster.pfb`.

### VR dummy body (`scripts/coop_dummy.lua`): FIRST VISIBLE RESULT
- `VrManager.DummyPlayerPrefab` → `set_Standby(true)` → ready → `instantiate(via.vec3)` gives "VrDummyPlayer" with components via.Transform, app.MotionManager, via.motion.Motion, via.motion.MotionFsm, app.MotionDelegateTagManager, via.render.Mesh (`pl0001.mesh`, ready), app.SequenceController, app.MotionManager.MotionManagerHelper, app.EventActionController. It has no child objects.
- It spawns with **go.Draw=false** (VR mode only shows it during events, through `updateDummyPlayer()` / `IsDummyPlayerEventActive`). After `set_DrawSelf(true)`, `set_UpdateSelf(true)`, mesh enabled and all 256 parts on, it reports Draw=true.
- **2026-10-29 15:23, the owner sees "an untextured shirt" at the label.** This is the first runtime-spawned object that actually renders. A prefab instance renders where hand-built GameObjects did not.
- 15:24: the dummy mesh had **0 materials (mdf=nil)**. The player mesh has 2: `pl0000_body`, `pl0000_VR` (mdf `Character/Player/pl0000/pl0001/pl0001.mdf2`). After `set_Material(player's)` it reported MaterialReady=true and ReadyToDraw=true, but **the owner still sees only an untextured shirt**. `copyJointsLocalMatrix` raised no error.
- Working theory: `pl0001.mesh` is Ethan's *first-person* body (torso/shirt for shadows and looking down), not a full third-person character. RE7 famously never shows Ethan's face, so there may be no full Ethan model at all. The untextured look may also need the render instance rebuilt after a material swap (for example toggling mesh Enabled off and on); untested.
- **Consequence:** the VR dummy prefab is a working *container* (prefab-spawned, renders once DrawSelf is on, has Motion/MotionFsm), but the second player needs a different full-body mesh and mdf2: a character the game ships complete (Mia, Zoe, Clancy, Chris in DLC, or an NPC). Plan: swap the dummy's mesh to that model via `sdk.create_resource("via.render.MeshResource", path)` → holder → `setMesh`, plus the matching mdf2. This needs real asset paths, from loaded prefabs or meshes in a chapter where that character appears, or from a community RE7 file list.

- 15:26 model search:
  - **`sdk.create_resource` returns an object even for nonexistent paths.** Every guessed `Character/Player/plXXXX/...mesh` and `.mdf2` "existed", so it's useless as an existence check.
  - Skinned character meshes actually loaded in the Chapter 1 start area:
    - Ethan: `Character/Player/pl0000/{pl0001,pl0002,pl0023,pl0050}/…` and `pl0000/pl0000/{pl0010,pl0020,pl0080}.mesh`
    - em2000 family: `Character/Enemy/em2000/{em2000,em2050,em2071_*_sim}`. `app.Em2000.Action.Chapter1Battle2Dead` suggests this is **Mia** (the chapter 1 guest-house fight).
    - em3000 family: `Character/Enemy/em3000/{em3000,em3050}`, a chapter 1 enemy, probably Jack.
    - `Character/Enemy/em5500/em5550/em5550.mesh`: the molded arm set (`Em5550PlArmSet.pfb`).
  - Auto-swapping in em5550 (first in the list): the owner saw the shirt, then nothing. An arm rig on Ethan's skeleton plus the copied pose collapses.
- Now: a model picker in the REFramework menu (`coop_dummy (ghost body test)`) with one button per loaded model, a pose-copy checkbox, dummy Motion on/off, and "move it next to me". Every click is logged.

- 15:32 picker clicks by the owner: #2 `em2000.mesh` applied OK but shows nothing (its scene instance has no mdf2, so there's no material). #4 `em3050.mesh` → "Invoke threw an exception" (twice). Not tried yet: #3 `em2050` and #5 `em3000`, both with mdf2.
- Prior art: alphaZomega's EMV Engine (github.com/alphazolam/EMV-Engine), Enemy Spawner.lua. It spawns with `prefab:add_ref()`, `set_Standby(true)`, then `instantiate(via.vec3, via.Quaternion, via.Folder)` into a folder from a custom .scn. It deactivates and reactivates that folder to fix infinite loading, and sets `set_DefaultStandby(true)` on prefab refs. Nothing RE7-specific. Its README warns that hand-built GameObjects with many components don't spawn well and recommends prefabs, which matches our results.

- **15:35 CRASH** (game closed): after Reset scripts and pose copy off, picker #2 `em2000.mesh` → "Invoke threw an exception" → access violation c0000005 in re7.exe in the same second. REFramework wrote `local/re7-test/reframework_crash.dmp`.
  - Saves verified byte-identical to the 14:49 backup afterwards, and the guard was active.
  - Likely cause (my bug): the picker kept MeshResourceHolder/MeshMaterialResourceHolder objects from scene meshes **without `add_ref`**, so setMesh received a freed holder. This also explains the em3050 exceptions.
  - Fixed in `scripts/coop_dummy.lua`: it now calls `add_ref` on the stored holders and skips meshes without an mdf2 (em2000 is skipped). **Not yet retested.**

- 15:36 relaunch: the crash fix held (no crashes since). The owner first loaded a videotape section as `Pl2000` (Chapter0; materials `pl2000_cloth`/`pl2000_jacket`; em2070/em2050/em2300 loaded there), then returned to Ethan Chapter 1.
- **15:39: `em2050.mesh` on the VR dummy shows Mia's head.** This is the first recognisable character part. RE Engine characters are split into several meshes (head, body, hair sims), so em2050 is Mia's head and `em2000.mesh` is very likely her body. em2000's material has no file path, but a live MeshMaterialResourceHolder exists, so filter on the holder object, not the path.
- Picker labels were cut off at the start ("Character/Enemy/em2000/..."), so they now show only the file name.
- Now: "Assemble full character of X" finds the source mesh's root GameObject in the scene, collects every mesh under it (skipping `_sim`), and spawns one VR dummy per mesh with that holder and material, all glued to the main dummy's position.

- **15:42 MILESTONE: a full second character renders.** "Assemble full character" from the Em3000 entry found source owner `Em3000Head` and root `Em3000`, with 2 meshes: `Character/Enemy/em3000/em3000/em3000.mesh` (body, on `Em3000`) and `Character/Enemy/em3000/em3050/em3050.mesh` (head, on `Em3000Head`). Each went onto its own VR-dummy instance at a shared origin. **The owner sees a full Mia.** Saves were still byte-identical afterwards.
  - Correction: **Em3000 = Mia** (Chapter 1 scene instance). Earlier guesses were wrong ("em2000 = Mia from Chapter1Battle2" and "em3000 = probably Jack"). The em2000 family's identity is unconfirmed, though the owner described em2050 as "her head" too.
  - Working recipe for a ghost body:
    1. `VrManager.DummyPlayerPrefab` → `instantiate(via.vec3)`, once per mesh part.
    2. Wait about 90 frames, then `set_DrawSelf(true)` and `set_UpdateSelf(true)`.
    3. `setMesh(holder)` and `set_Material(holder)`, using `add_ref`'d holders taken from the live scene character.
    4. Toggle mesh Enabled off and on, and enable all parts.
  - Limits so far: the pose is whatever the dummy's Ethan Motion produces on Mia's mesh (probably a bind or odd pose). It only works where the source character is loaded in the scene. The parts are glued together by position only.

- Owner feedback on the first full Mia: (a) Ethan's first-person shirt from the anchor dummy overlapped her; (b) **the head showed the infected (molded) variant while the body was normal.**
  - Cause (b): the script enabled *all* parts on every mesh. RE Engine meshes keep variants as toggleable parts, so all-on overlays the infected head.
  - Fixes, installed but untested:
    - Copy each scene mesh's `getPartsEnable` mask onto the dummy (logged as `source parts[n]=…`), with an "all parts" checkbox for comparison.
    - Hide the anchor dummy (DrawSelf false) once parts exist.
    - Follow mode: record the player's position and rotation for 10 s and drive the anchor plus all parts from the sample 3 s back. The gap is written to `coop_follow_state.txt`.
    - Pose copy now defaults to off.

- **15:45 MILESTONE 1 reached: the assembled character follows the player's recorded path 3 s behind** (owner confirmed). Position and rotation are driven from recorded samples, so the transport-independent part of the ghost works.
- Face still infected. This run was assembled from a *different* scene character, **`Em2100`** (body `em2000.mesh` on `Em2100`, head `em2050.mesh` on `Em2100Head`). The 15:42 run used `Em3000` (em3000 + em3050). So the scene holds two Mia instances, probably normal and molded/fight. **Both sources have all 256 parts on**, so the variants are not parts; the parts-mask theory is wrong for this.
- New theory: the look is driven by **material variables** set at runtime on the live character (our material instance gets the mdf2 defaults). Installed, untested: copy every material variable (`getMaterialVariableNum/Name/Type`, `get/setMaterialFloat(4)`) from the scene mesh about 30 frames after showing, and log the var types and any names matching infect/mold/black/dirt/blood/damage/wet/blend/rate/mask. The type ids (0/1 = float, 2/4 = float4) are guesses, so the log will confirm.

- 15:48 owner correction: **Em3000 = Jack** (em3000 body + em3050 head), so the 15:42 "full Mia" identification was wrong. **Em2100 = infected Mia** (em2000 + em2050). With the Jack assembly, **the head lay on the ground**: head GameObjects are parented to a neck joint, so their origin isn't at the feet. Mia's face is still infected after the material-var copy, but that log was lost (each Reset scripts overwrote it).
- Fixes, installed but untested:
  - Logs now persist per load (`coop_dummy_log_HHMMSS.txt`).
  - Each piece keeps its position and rotation offset relative to the source root (in root space) and is placed at anchor + rotated offset.
  - A one-time "rot check" logs whether `Quaternion.new(w, x, y, z)` argument order is right.
- Open question: is a *normal* Mia head loaded anywhere in Chapter 1? Em2100 may simply be molded Mia (the fight version), in which case the normal look needs another source.

- 15:49 log (Jack, Em3000):
  - Both pieces have **offset 0,0,0 from root**: the head isn't placed by position, it is *skinned to the body's skeleton* (the child transform borrows the parent's joints). Our head dummy wasn't parented, so its joints collapsed to the floor.
  - **The head parts mask in the scene is `1101001111…`** (parts 2, 4 and 5 off), and there's an `em3050_destroy` material. So damage/infection variants **are** part toggles on head meshes. Mia's earlier all-1 mask was logged before mask copying existed, so it needs a retest with the mask copy.
  - Material var types are confirmed: **1 = float, 4 = float4**. The copy works (85 vars on em3000, 120 on em3050). Interesting vars: `Death_Rate`, `Burn_*`, `BloodMask_Rate_0..3`, `HitMark_Rate`, `RecordSys_rtt_Mask_Pram`.
  - Rotation readback matched, so `Quaternion.new(w, x, y, z)` order is correct.
  - Owner: "only the label follows, not the model". Cause unknown. The per-frame update errors were swallowed by pcall, so they're now logged once per piece, and part positions are written to `coop_follow_state.txt`.
- Installed, untested: non-root pieces get `set_Parent(body piece)`, plus the source's `SameJointsConstraint` and `ParentJoint`; only the root piece is positioned per frame.

- **15:51: whole character renders and follows.** Infected Mia (Em2100): body em2000 at the root; head em2050 with `SameJointsConstraint=true`, ParentJoint empty, now parented to the body dummy. The owner confirmed she follows. The face is infected because **the source Em2100 head itself has all 256 parts on**: this scene instance *is* molded Mia (the fight version). A normal Mia isn't loaded at the Chapter 1 start area. Our code reproduces the source faithfully.
  - Cosmetic: after `set_Parent`, the head transform reported world (−142.9, 9.8, 198.6) because old world coords became local. It rendered correctly via the joint constraint anyway. The local position and rotation are now zeroed after parenting (installed, not retested).
- For a normal-looking second player: assemble from a scene where a normal character is loaded (for example normal Mia earlier in the guest house) and carry the holders across, or find that character's mesh and mdf2 and load them anywhere (needs a working existence check; create_resource always succeeds).

### Animation (installed, untested)
- via.motion.Motion API (from the dump): `get/set_MotionBankAsset`, `get/set_JointMap`, `setupMotionBank()`, `getActiveMotionBankCount/getActiveMotionBank(n)` → MotionBank(`get_BankID`, `get_Name`), `getMotionCount(bankId)`, `getMotionInfoByIndex(bankId, i, MotionInfo)` → MotionInfo(`get_MotionID`, `get_MotionName`, `get_MotionEndFrame`), `getLayer(n)` → via.motion.TreeLayer. TreeLayer wasn't in the dump; its methods get dumped at runtime to `coop_treelayer_api.txt`.
- Approach: when the body piece is shown, disable the VR dummy's `MotionFsm`, `app.MotionManager`, `app.SequenceController` and `app.EventActionController`. Give it the scene character's `MotionBankAsset` and `JointMap`, then `setupMotionBank()`. This gives Mia's own clips on Mia's skeleton, so no retargeting. All clips are listed to `coop_motions.txt`.
- Menu: clip buttons (names matching walk/idle/wait/run/move/stand/loop), each with WALK and IDLE assignment, plus "Auto" (walk above 0.4 m/s of ghost movement, idle below), played with `TreeLayer.changeMotion(bank, id, 0, 10 interp, …)`.

- 15:54 first animation run:
  - Mia's bank is `Animation/Enemy/em2000/em2000_em2100.motbank`, joint map `Animation/Enemy/em2000/em2000_JointMap.jmap`.
  - TreeLayer.changeMotion overloads: `(MotionJointCoordTable)`, `(UInt32 bank, UInt32 id, Single frame)`, `(MotionJointCoordTable, Single, InterpolationMode, InterpolationCurve)`, and `(UInt32 bank, UInt32 id, Single startFrame, Single interpFrame, InterpolationMode, InterpolationCurve)`.
  - **0 clips**: I listed them from the scene Em2100, which is inactive and has no active banks. The fix lists from our own Motion after `set_MotionBankAsset` + `setupMotionBank`, polling once a second for up to 20 s while the bank loads. Installed, untested.

- 15:56: **clips list from our own Motion**: 2 active banks after about 1 s.
  - Bank 0 `em2000_c01e00`: 11 chapter-1 event clips `c01e00_*`.
  - Bank 1 `em2000_Gimmick_ch01`: `[1/0] em2000_Gimmick_ch01_01_Walk` (532 frames), `[1/10] em2000_Gimmick_ch01_00_Idle_A` (1 frame), `[1/11] em2000_Battle1_Em-CrawlStand_Loop` (110 frames).
  - But **no clip was ever played** (no `play` lines): WALK/IDLE only assigned, and Auto never played (an error was swallowed, now logged).
  - Owner: "model doesn't follow, just the label". The body *transform* matched the anchor. Likely cause: with the dummy's MotionFsm off and the new bank set but nothing playing, the skeleton stops updating, so the skinned mesh stays put. Fix: WALK/IDLE now play immediately, and a 1 s post-play check logs layer0 bank/motion/frame/speed.

- 15:59: every play attempt logged **`play: no layer 0`**. With the VR dummy's MotionFsm disabled, our Motion has no TreeLayers (the FSM normally creates them). Fix, installed but untested: if getLayer(0) is nil, call `setLayerCount(1)`; if that still yields nothing, `sdk.create_instance("via.motion.TreeLayer")` + `setLayer(0, layer)`. The layer count before and after is logged.

- 16:01:
  - `setLayerCount(1)` on a Motion with 0 layers did **not** create a layer.
  - `sdk.create_instance("via.motion.TreeLayer")` + `setLayer(0, tl)` did give a layer, and `changeMotion(1, 0, 0, 10, 2, 0)` returned OK, setting bank=1 motion=0.
  - But 1 s later **frame=0.0, end=0.0**: the clip never bound or advanced. Hypotheses: the hand-made layer isn't wired into the update, and/or swapping the bank reset the FSM-made layers.
  - Next run (installed): log layers, banks, dynamic banks and joints before the swap, after set_MotionBankAsset, after setupMotionBank, and at verify. **Keep the dummy's MotionFsm running** until verify sees end>0, then disable it.
- 16:02 stage counts:
  - **Before any change, the VR dummy's Motion has layers=0, banks=0, joints not constructed.** It was never animated, so I hadn't destroyed existing layers.
  - After the bank swap and a hand-made layer: 159 joints constructed (Mia's skeleton), 2 active banks, layer0 = bank 1 / motion 0, but **end frame 0**.
- **EMV Engine recipe** (`EMV Engine/init.lua`, `create_gameobj` and the animation code):
  - `TreeLayer` = `sdk.create_instance("via.motion.TreeLayer")` then **`:call(".ctor")`**, then `setLayerCount(1)` and `setLayer(0, layer)`.
  - Before playing: **`layer:set_Resource(nil)`**, then `changeMotion(UInt32 bank, UInt32 id, 0.0, 20.0, 2, 0)`.
  - Clips are added as `DynamicMotionBank`: create, `.ctor`, `set_MotionList(holder)`, `set_OverwriteBankID(true)`, `set_BankID(id)`, then `setDynamicMotionBankCount(n+1)` and `setDynamicMotionBank(n, db)`.
  - My layer was missing `.ctor` and `set_Resource(nil)`. Both have been added, plus an automatic dynamic-bank fallback and a retry if verify still sees end=0. Installed, untested.
- **16:05 MILESTONE: the ghost animates.** Owner confirmed "She walks". Log: `TreeLayer .ctor` returned OK, setLayer(0), `set_Resource(nil)`, `changeMotion(1, 0, 0, 10, 2, 0)`, and 1 s later **frame 56.2 / end 532** (bound and advancing). The DynamicMotionBank fallback wasn't needed. After that the dummy's MotionFsm, app.MotionManager, SequenceController and EventActionController were disabled.
  - Working animation recipe for a prefab-spawned body:
    1. `set_MotionBankAsset(scene char's bank)`, `set_JointMap(…)`, `setupMotionBank()`. Active banks appear about 1 s later.
    2. Constructed TreeLayer (`create_instance` + `.ctor`), then `setLayerCount(1)` and `setLayer(0)`.
    3. `set_Resource(nil)`, then `changeMotion(bank, id, 0, interp, 2, 0)`.
  - In the Chapter 1 start area Mia's loaded clips are limited to `Gimmick_ch01_01_Walk` (532 f), `Gimmick_ch01_00_Idle_A` (1 f, a static pose), `Battle1_Em-CrawlStand_Loop`, and 11 cutscene clips. Other areas or banks will have more (run, turn, etc.).
- Superseded alternatives (kept for reference):
  - Add Mia's motlist as a **DynamicMotionBank** (`setDynamicMotionBankCount`/`setDynamicMotionBank`) on the untouched dummy Motion.
  - Drive joints directly each frame from MotionInfo sampling (`getAnimationTransform(jointHash, frame, …)`): heavier, but independent of layers.

### Ghost status (2026-10-29 16:05)
- DONE: a visible second character (assembled Mia), driven by recorded position and rotation samples (3 s replay), playing her own walk clip.
- TODO for the ghost:
  1. Auto walk/idle by speed is wired but untested. Idle_A is a 1-frame pose, which is fine. Sync the walk playback speed to movement speed.
  2. Load the body anywhere, not just where Em2100 is loaded: keep references (add_ref'd holders and bank) across area loads, or find mesh, mdf2 and motbank paths that load on demand.
  3. A normal-looking character (not molded Mia).
- NEXT BIG STEP: networking. Replace the local replay buffer with packets from the other PC (Steam relay via a native REFramework plugin, since Lua has no sockets), sending position, rotation, the current clip id and the frame.

### Next approach: real prefabs
Spawn through `via.Prefab` (`sdk.create_resource("via.Prefab", path)` → holder → `instantiate(position)`), the way the game spawns things itself.
1. Find prefab paths that are already loaded: scan spawner components in the scene (for example `app.EnemyGenerator`, the item managers) for `via.Prefab` fields and log `get_Path`.
2. Test first with a small item prefab (does instantiation render?). Then try a character prefab: an NPC or enemy body, or a second player prefab with its logic components disabled.
- Fallback if hand-built GameObjects never render: instantiate a real prefab (`via.Prefab` resource → `instantiate`), the way the game spawns characters. That needs prefab paths, for example from the player's or an NPC's spawner data.
- The engine API used is dumped to `reframework/data/coop_ghost_api.txt`.

### Next in Phase 3
1. Spawn a second, inert copy of a player body (a "ghost" with no input, camera or AI beacon) and drive its transform and motion from recorded data. This proves the second player can be shown at all.
2. Find the motion-layer API to play walk/run/aim animations on the ghost (via.motion.Motion layers).
3. Map enemy targeting (AIVisionBeacon, MansionAI target selection), so enemies can choose either player.
4. Map story flags (GameFlowFsmManager) and doors, which decide what the host must replicate.

## Networking (started 2026-10-29)
### Prior art
- RE4 remake "Multiplayer Mod" (claybtv, Nexus 6539): closed-source beta that syncs enemies, story events, doors, switches and alarms. Reported problems: lag spikes and enemy sync bugs. No repository.
- RE2 remake "Local Couch Co-op" (formerly HUNK'y Friend, Shopcreeper01): REFramework-based, **local only**, no netcode. Player 2 spawns on controller 2 (Start+Back). No public source found.
- Neither has netcode to reuse. EMV Engine (spawning and animation) was the useful reference.
- Nexus pages return 403 to automated fetching, so info came from search results and news coverage.

### Toolchain
- No C++ compiler on this PC (no VS, cmake or clang). It has the .NET SDK 10.0.300-preview and .NET runtimes 9.0 and 10.0.5.
- **REFramework C# API** (`csharp-api.zip`, nightly-01433, SHA-256 87a909fe…629b, matches the release digest): source plugins in `reframework/plugins/source/*.cs` compile at runtime with Roslyn and hot-reload on save. Needs .NET 10. Standard .NET networking works (REFramework's own TestWebAPI.cs runs HttpListener on a thread). On first load it generated `plugins/managed/generated/REFramework.NET.{viacore,application,…}.dll` for RE7.
- Offline compile check: `local/build/coopnet-check/CoopNetCheck.csproj` builds against `REFramework.NET.dll` (0 warnings, 0 errors). The scratchpad path was too long for MSBuild.

### Transport v0 (`scripts/CoopNet.cs` + `coop_dummy.lua`)
- C# owns the UDP socket only and calls **no game API**. A receive thread plus an IO thread at 30 Hz.
- Lua ↔ C# go through a file bridge in `reframework/data/`. This is a stopgap until C# drives the ghost directly:
  - `coopnet_out.txt` (Lua writes the local player state at 30 Hz)
  - `coopnet_in.txt` (C# writes the last 32 received samples, replaced atomically via a temp file and File.Move)
  - `coopnet_status.txt` (C# stats every 1 s)
  - `coopnet_config.json` (mode echo|udp, bindHost, localPort 27777, peerHost, peerPort, sendHz)
- Packet: 56 bytes, `"R7C1" | u32 seq | f64 senderTime | 3×f32 pos | 4×f32 quat | u32 bank | u32 id | f32 frame`.
- Lua converts sender time to local time with a minimum-offset estimate and samples the network history at now − delay: 3 s for the echo test, 0.15 s live.
- 16:12: the plugin loads in game, with status `state=running mode=echo peer=127.0.0.1:27777`.
- **16:16 echo transport verified:** `sent=708 recv=708 bad=0 lastFrom=127.0.0.1:27777`, 32 samples in `coopnet_in.txt`, and the ghost anchor and body transform track the network history.
  - The owner saw the label follow but not the model. Same cause as before: after a restart no clip was playing, so the skeleton didn't update.
  - Fix, installed for the next reset: after the clips load, auto-pick walk/idle by name, play idle (or walk) immediately, and turn Auto on. Workaround now: click WALK.
  - The "Follow my path" checkbox is renamed "Move the ghost (source: …)". It's the master switch; the network checkbox only changes the source.
- 16:17 logs (`coop_dummy_log_161633/161718.txt`):
  - **Disabling the dummy's app.MotionManager/MotionFsm/SequenceController/EventActionController freezes the layer**: the frame stayed at 0.2889 for 13 s even after switching to Walk. RE7's app.MotionManager drives the via.motion.Motion update, so they're **no longer disabled**. The 16:05 "she walks" likely came from the 1 s before that disable.
  - Auto (now on by default) immediately overrode a manual WALK with Idle while the ghost stood still. Manual clip clicks now turn Auto off.
  - The first play on a fresh layer sometimes doesn't bind (end=0, 16:16 session). verify now retries up to 3 times at 0.5 s before the dynamic-bank fallback. Installed, untested.
- **16:20 MILESTONE: network-driven, animated ghost.** The owner confirmed "now she is moving with enemy walking animation". The pipeline is local player → Lua out-file → CoopNet.cs → UDP 127.0.0.1:27777 (echo) → in-file → Lua network history → ghost anchor → assembled Mia, with auto walk/idle. Status: `sent=4073 recv=4073 bad=0`. Walk binds (frame 60/532 one second after start); auto switches Walk/Idle_A by speed.
  - The clip is Mia's molded-enemy walk (`em2000_Gimmick_ch01_01_Walk` from `em2000_em2100.motbank`), the only walk loaded in this area.
  - The earlier "still frozen" reports at 16:18–16:19 were most likely the 3 s echo delay plus Auto on Idle while standing. No code change was needed after the MotionManager fix.
### Transport v1: Steam relay (2026-10-29)
- The game's `steam_api64.dll` (file version 6.28.18.86, 1,019 exports; read with `local/build/pe_exports.ps1` since there's no dumpbin) has the **modern flat API**: `SteamAPI_SteamNetworkingMessages_SteamAPI_v002`, `…NetworkingUtils_SteamAPI_v003`, `SteamUser_v021`, `SteamFriends_v017`, the `SteamNetworkingIdentity_*` helpers and `SteamNetworkingMessage_t_Release`. The legacy `ISteamNetworking` P2P API is also present.
- `CoopNet.cs` `"steam"` mode P/Invokes the already-initialised Steam in the game process:
  - Startup: `InitRelayNetworkAccess`.
  - Send: `SendMessageToUser` with flags UnreliableNoNagle (1) | AutoRestartBrokenSession (32), channel 7.
  - Receive: `ReceiveMessagesOnChannel` polled at 30 Hz, reading `SteamNetworkingMessage_t` with m_pData @0, m_cbSize @8 and identity @16, then `Release`.
  - `AcceptSessionWithUser(peer)` at start. Sessions with someone you've sent to are auto-accepted, so no callbacks are needed.
  - `peerSteamId: "self"` is a loopback experiment.
- **16:24 verified in game (self loopback):** hot-reload took about 1.7 s with no game restart; `relayStatus=100` (k_ESteamNetworkingAvailability_Current); `sent=486 recv=486 bad=0`; `lastSendResult=1` (k_EResultOK). Self-sends may short-circuit locally, so **the internet relay path is unverified until a second player connects.**
- Friend kit: `package/coop-re7-v0.1/` (+ `.zip`, 23 KB). It contains the save guard, dummy and probe Lua scripts, CoopNet.cs, a config template, and a README with official REFramework download links and SHA-256s. No REFramework binaries are redistributed, and there's no personal data (scanned).
- The friend test (two PCs) is **pending**. QA level: automated self-loopback only.
### Controller refinements + bot peer (2026-10-29, installed, NOT yet run: the game was closed)
- `CoopNet.cs` `"bot"` mode is a fake remote player for testing without a second PC. It walks a circle (botRadius 3 m, botSpeed 1.3 m/s) around the first local position it sees, pauses botPauseFor = 2.5 s every botPauseEvery = 8 s, and faces the tangent (+ botYawOffsetDeg in case the engine's forward axis differs). Its packets go through the real decode and receive path with simulated network conditions: simLatencyMs 80, simJitterMs ±30, simLossPct 5. Late, reordered packets are dropped by Lua's seq check.
- `coop_dummy.lua`:
  - `sample_interp`: lerp position and nlerp rotation (sign-corrected) between the samples around the render time; holds the nearest pose before the first or after the last sample.
  - Auto-anim speed is smoothed (EMA 0.5).
  - The walk layer's speed is ghost speed / `walk_ref` (default 1.2 m/s, clamped ×0.5–×2.0), adjustable with a menu slider "Walk clip natural speed".
- The test copy's config is set to `"bot"`. The friend kit was refreshed with the same scripts; its config template is still `"steam"`.
- **16:40 bot test (owner):** smooth, facing forward (botYawOffsetDeg 0 is correct, so the RE7 forward axis matches), walk animation working under 80 ms / ±30 ms / 5% loss at 0.15 s delay. Feet slid ("glides faster than her steps") at walk_ref 1.2, and look better at **0.8**, now the default.
- Next for a "human player" look:
  - a normal character with a full locomotion set (normal Mia, from the guest house onward, or Zoe), instead of molded Mia's gimmick walk;
  - send player state (run, crouch, aim, camera pitch/yaw, equipped item) and play matching clips;
  - procedural head and upper-body look toward the remote camera direction;
  - walk/run blend by speed, plus turn-in-place.
### Head look (installed 16:47, untested)
- **Packet v2 `R7C2`, 64 bytes**: adds `f32 lookYaw, lookPitch` (camera relative to the body, in radians). The text line has 14 fields. v1 packets and 12-field lines are rejected (not backward compatible).
- Sender (`local_look`): camera forward from the primary camera transform. The ±Z sign is auto-picked once as the one closest to the body facing, and logged as "look: camera forward is …". Yaw is relative to the body (+Z forward), pitch = asin(forward.y).
- Bot: lookYaw = 0.9·sin(0.7t), lookPitch = 0.35·sin(0.45t).
- Ghost (`apply_look`, in `re.on_pre_application_entry("PrepareRendering")`, so it runs after the animation): neck 40% / head 60% world-space rotation, yaw about world up and pitch about the body's right axis, clamped to ±1.2 / ±0.7 rad. Joints are found by name ("neck", "head" without "end"); all names go to `coop_joints.txt`. The pitch sign is unverified.
- **16:50 result: FAILED.** Joints found: 156, neck=`Neck`, head=`Head`; camera forward is −Z. But once `apply_look` ran, **the walk frame froze at 106.5** in every verify (clips still switched), and the head moved erratically: with the Motion no longer resetting joints, the per-frame world deltas accumulated. Writing `via.Joint.set_Rotation` from PrepareRendering stops RE7's Motion from updating that skeleton.
  - Head look is now **off by default** (opt-in checkbox). Walking is back once scripts are reset.
  - Next try: `via.motion.Motion.setLocalRotation(jointIndex, rot)` (joint index from `getJointIndexByNameHash`) applied as an offset on `getCalculatedLocalRotation`, or `registerExpression`, or an engine aim constraint.
- Test: launch, Continue, assemble em2050, tick network, Delay 0.15 s. Expect Mia circling about 3 m around the spot where network mode was enabled, smooth despite jitter and loss, pausing every 8 s.
- Next after the friend test: drive the ghost from C# directly (dropping the file bridge), send the animation clip and frame, and start world sync (enemies, doors, story flags), host-authoritative.

## Ethan as the ghost (2026-10-29 evening)
- Prior art: RE7's third-person mod is a Cheat Engine camera script (Nexus RE7 mod 12, not REFramework). The "Third Person Full Model Placeholders" mod uses **in-game models** for Ethan, Clancy, Mia, Zoe, Chris and Joe, and a Steam thread says Ethan has a full head model with a face (no facial animation). So the earlier "no full Ethan model" assumption was wrong.
- Already loaded in the Chapter 1 area: `Character/Player/pl0000/{pl0002,pl0023,pl0050}/…` and `pl0000/pl0000/{pl0010,pl0020,pl0080}.mesh`.
- Picker: new **"Assemble ETHAN (full body, from your player)"** button. It assembles from the first pl0000 candidate's root (the player object) with parts_mode=all, since first person hides parts such as the head on the source, and borrows the player's own motion bank. Installed 18:33.
- **18:37 result:** the first pl0000 candidate, `pl0080.mesh`, belongs to **`sm1649_EthanLHand_Event`**, a standalone event prop of Ethan's left hand (root = itself, 1 mesh, no motion bank). So the ghost got one hand mesh with no animation; banks never became active and nothing rendered, only the label. **Ethan's extra meshes are separate event objects, not children of the player.**
- Now: the scan logs owner, root and joint count per skinned mesh. There's one "Ethan piece" button per pl0000 mesh, each animated with **the player's own Motion bank** (`anim_from_player`), i.e. Ethan's real skeleton.
- **18:41: OWNER SEES ETHAN** (assembled from root `Pl0000_Chapter1`, the player object). Under the player there are 15 meshes:
  - first-person body pl0001 (on the root)
  - hands pl0020/pl0010, lower body pl0002, Codex watch pl0023
  - molded-arm attachments `Em5550PlArm_A/B/C` (em5550)
  - props `sm2241_EthanLeg_DetailSearchItem` and `wp0030_Light_Event`
  - **a full Shadow set** that RE7 renders only for the player's shadow: `ShadowBody` (pl0001), `ShadowHandL/R` (pl0020/pl0010), `ShadowLowerBody` (pl0002), **`ShadowHead` (pl0050, 253 joints, i.e. a face rig)**
- Ethan's animation: `Animation/Player/pl0000/pl0000.motbank` + `pl0000_JointMap.jmap`, **29 banks, 5,521 clips**. Bank 0 `pl0000_Hands` has Stand/Crouch loops; Walk/Jog/WalkCrouch in F/B/L/R; Turn L75/R75; damage variants. `pl0000_Idle`, `_Move`, `_TurnL/R` are tree nodes (−1 frames). Idle bound at frame 63/284, walk at 31/78.
- The auto-pick chose `Hands_WalkB_Loop` (backwards) as "walk". A second assemble stacked parts and the clips failed to bind (end=0).
- Fixes (installed, untested):
  - Ethan uses **only the Shadow\* pieces**, with ShadowBody as root and the others SameJointsConstraint-parented.
  - Re-assembling destroys the previous ghost.
  - Clips are picked by exact name (Walk/WalkB/WalkL/WalkR, Jog×4, Stand_Loop); walk_ref 1.3 and jog_ref 3.2 m/s.
  - **Directional locomotion**: velocity relative to facing (+Z forward, right = local −X) picks F/B/L/R, jog above 2.2 m/s, playback speed scaled. The left/right sign is unverified.
- **18:46 result:** Ethan from the Shadow set "looks good" and clips switch correctly (Walk_Loop / Stand_Loop by speed). But **he doesn't move**: the layer frame is stuck at 8.848 in every verify. Only the root transform (ShadowBody pl0001) follows the anchor; the SameJoints children stay where they spawned. Since the children borrow the root's skeleton, a frozen Motion freezes the whole visible body.
  - Hypothesis: the Shadow\* meshes are shadow-only in the source, and RE Engine skips animating skeletons it considers invisible.
  - Fix (installed, untested): force `DrawDefault=true` and `DrawShadowCast=true` on every piece, log the source flags, and verify logs "FROZEN" when the frame doesn't advance.
  - If that isn't it, check the Motion's IntervalUpdateOption / joint LOD next.
- **18:47 MILESTONE: Ethan walks.** Confirmed cause: every Shadow\* source mesh has **DrawDefault=false, DrawShadowCast=true** (shadow-only). Forcing DrawDefault=true makes RE Engine animate the skeleton. The owner confirmed "He walks now" under the bot (80 ms / ±30 ms / 5% loss, 0.15 s delay).
  - One `FROZEN` line at 18:48:01 (frame 4.397): a brief stall or a false positive. Watch for it.
  - The friend kit's README now tells players to build Ethan, with Mia as the alternative.
- **18:50 direction test (bot cycles facing 0/90/180/270° every 8 s; status shows `botExpect`):** the ghost **froze again** at frame 27.698 and never recovered. Both freezes (18:48, 18:50) start right after the switch to **`pl0000_Hands_Stand_Loop`** when the bot pauses: verify shows motion=10 but end=78 (WalkB's length; Stand is 284). **Stand_Loop never binds and jams the layer for good.**
  - Ethan's clip list repeats bank id 0 several times, i.e. several banks share id 0 with different bank types, so `changeMotion(bank, id, …)` may resolve to the wrong one.
  - Fix (installed, untested): verify detects a FROZEN frame or a WRONG BIND (end ≠ clip length), rebuilds a fresh constructed TreeLayer, retires the clip, and falls back through idles StandDamage_Loop → E-Radar_Stand_Loop → forward walk held at speed 0. The interrupted clip is then replayed.
- **18:55 result: the owner says he "keeps moving".** The recovery fired 5 times between 18:55:09 and :17, then stayed stable. It retired Stand_Loop; the idle is now **StandDamage_Loop**. Every direction clip played (Walk×13, WalkL×4, WalkR×3, WalkB, Jog, JogL×2).
  - False positives: "WRONG BIND" on Walk_Loop (end 68 vs 66: the previous clip's length during the blend), and "FROZEN end=0" on a freshly rebuilt layer.
  - TODO: only flag a stuck frame when endf > 0 and speed > 0, and allow a blend tolerance or a second confirmation.
- **18:58 directions verified:** the owner confirmed the ghost's chosen direction matches the bot's real motion (`botExpect`) through the forward/right/back/left cycle. The facing convention (+Z forward, right = local −X) and the strafe/backpedal clip selection are correct.
### Head look v2 (installed 19:00, untested)
- Approach: in `re.on_application_entry("UpdateMotion")` (post), for Neck (40%) and Head (60%):
  - get the joint index via `Motion.getJointIndexByNameHash(via.Joint.get_NameHash())`;
  - compute `new_local = conj(parentWorld) · D · parentWorld · calculatedLocal`, where D is a world-space yaw about up times pitch about the body's right axis;
  - write it with `Motion.setLocalRotation(idx, q)`.
  - The base is this frame's `getCalculatedLocalRotation`, so it can't accumulate.
- Diagnostics: the hook's fire count over 3 s is logged (0 means the entry name isn't valid in RE7).
- Safety: a FROZEN watchdog hit while look is on switches look OFF automatically.
- Opt-in checkbox "Head look v2"; the bot sweeps yaw ±0.9 rad and pitch ±0.35 rad. The pitch sign is unverified.
- **19:00 v2 result: no visible head motion, no freeze.** The UpdateMotion hook fires (928× in 3 s) and finds Neck#20 and Head#21. The look values arrive (yaw ±0.9, pitch ±0.35), and `setLocalRotation` is accepted (the readback matches the set value), **but at render time the Head joint holds exactly the plain animated pose**: Motion writes its own result into the skeleton after that hook.
- **v3 (installed 19:02, untested):** write `via.Joint.set_LocalRotation` in **pre-PrepareRendering**, using `Motion.getCalculatedLocalRotation(idx)` as the base each frame (so no accumulation even if a frame is skipped); parent world from `Motion.getWorldRotation(parent)`. The diag now runs post-PrepareRendering and shows whether the write survived. The freeze watchdog still switches look off.
- **19:04 v3 WORKS:** the owner confirmed "head moves, he walks fine". Writing `via.Joint.set_LocalRotation` at pre-PrepareRendering, based on `getCalculatedLocalRotation`, is the working recipe. Head look is now **on by default**.
- Owner feedback: "a bit of an animation delay when starting new movements". Tuned: auto check 0.25 → 0.1 s, speed EMA new-sample weight 0.5 → 0.7, clip blend 10 → 6 frames. The 0.15 s network buffer is unchanged.
- **The ghost is always Ethan now:** `build_ethan()` runs automatically once the stand-in body is ready. It picks the first pl0000 mesh whose root is the player (skipping event props such as sm1649_EthanLHand_Event) and builds the Shadow set.
  - Network mode is on by default with 0.15 s delay.
  - The menu is "Rebuild Ethan" plus a collapsed "Other characters (debug)" section (Mia, model picker).
  - The kit README is simplified to "just load in".
  - **19:07 verified by the owner:** Ethan appears on his own after Reset scripts with no clicks, and movement starts "feel better".
### Crouch / run sync (installed 19:10, untested)
- State source: `app.PlayerMovement.get_isCrouch()` and `get_isWalk()`; Ethan's real speeds are in fields `WalkSpeed` (0x120), `JogSpeed` (0x124) and `CrouchMoveSpeed` (0x130). These are used as the playback references instead of hand-tuned values (logged at build).
- The flags are packed into the packet's existing `animBank` u32, so there's **no protocol change**: bit0 crouch, bit1 walking, bit2 valid.
- Ghost: crouched → `WalkCrouch{,B,L,R}_Loop` / still `Crouch_Loop` (the watchdog can retire it like Stand_Loop); valid and not walking while moving → Jog×4; otherwise Walk×4. Samples without flags fall back to the speed > 2.2 jog rule. The menu shows `stance`.
- Bot: stance cycles walk → jog (3.4 m/s) → crouch (0.9 m/s) every 16 s; direction every 4 s, so every stance covers all 4 directions. `botExpect` reads e.g. "jog left".
- **19:09 result: T-pose.** After Reset scripts the retired-clip memory was gone, so auto-pick played **Stand_Loop first**. It didn't bind (end=0), and afterwards **no clip ever bound**, even after layer rebuilds and the dynamic-bank fallback. A layer that has never bound anything leaves the skeleton in bind pose (T-pose). The earlier recovery (18:55) worked only because a walk had bound first. The watchdog also switched head look off, but look wasn't the cause.
  - Refs read from PlayerMovement: walk 1.70, jog 2.70, crouch 1.20 m/s.
  - Fixes (installed 19:12, untested):
    - Stand_Loop is permanently blacklisted; the idle is StandDamage_Loop.
    - The first clip is always the forward walk.
    - After 3 failed binds in a row, the whole ghost is rebuilt via build_ethan (at most once per 30 s); a successful bind resets the streak.
    - Head look is no longer switched off by the watchdog.
- **19:14: all stances work** (owner): walk/jog/crouch × 4 directions plus the idles.
- Feedback: "rotates or changes animations too instant, not natural". Changes (installed 19:16, untested):
  - Body facing eases with an exponential slerp (TURN_TAU 0.1 s).
  - Blends: 12 frames between directions (BLEND_DIR), 16 across stance changes (BLEND_STANCE); was 6.
  - Direction hysteresis (the new axis must beat the old one by 25%) and a 0.3 s minimum hold for moving clips.
  - The bot turns at 240°/s instead of snapping 90°.
  - Tunables are globals at the top of coop_dummy.lua.
- **19:18 feedback: "better", but some sliding before the animation starts, plus choppiness.** Changes (installed 19:20, untested):
  - **Extrapolation:** past the newest sample, keep moving at the last velocity for up to EXTRAPOLATE_MAX = 0.1 s instead of holding. With 80 ms ± 30 ms latency and 33 ms sampling, the 0.15 s render time sometimes ran past the newest sample, causing hold-then-jump stutter.
  - **Look-ahead velocity:** velocity comes from the buffered future (render time + LOOKAHEAD 0.08 s over a 0.12 s window), so the walk starts as he moves rather than after the anchor has already slid.
  - Separate start/stop thresholds: MOVE_START 0.25, MOVE_STOP 0.15 m/s.
  - The stride playback rate is eased (0.7/0.3).
- (Older note, now resolved:) Still to verify: strafe/backpedal clips and the left/right sign (the bot only walks forward; set botYawOffsetDeg 90/180 to test). The head/face rig isn't driven, and head look is still off.

## Tooling: coop-anything MCP server (2026-10-29)
- The repo was downloaded as a zip from github.com/cranebeaker/coop-anything (main; zip SHA-256 98428783…9044366) to `<coop-anything clone>`. There's no git.
- `tools/mcp/coop_mcp.py` was read in full before running: read-only, repo-confined, no network or exec.
- Python 3.12.10 installed by winget (`Python.Python.3.12`, user scope, installer hash verified by winget), plus PyYAML 6.0.3 from PyPI.
- Registered with the bundled CLI: `claude mcp add coop-anything --scope user -- <python> <coop-anything clone>\tools\mcp\coop_mcp.py` → ✓ Connected. `~/.claude.json` was backed up first to `local/claude.json.backup-before-mcp`.
- Smoke test: tools/list returned 9 tools; search_directory "Resident Evil" gave 9 entries and no RE7 entry.

## Collision (2026-10-29)
- 19:22 owner: "still a little choppiness", but asked to move on to collision. Smoothing is parked.
- Scope v1: **the local player can't walk through the ghost.** The ghost vs the world is already handled by the other player's own game; enemies and bullets vs the ghost come later with enemy sync.
- API: `app.MovementController.warp(via.vec3, via.Quaternion)` moves the player through RE7's movement controller (setting the transform directly would be undone by the character controller). There's also `app.PlayerOrder.setPositionWithCamera(via.vec3)`.
- Implementation (installed 19:24, untested): a horizontal capsule test every frame, COLLIDE_RADIUS 0.6 m combined and COLLIDE_HEIGHT 1.7 m. When overlapping, warp the player out along the ghost→player line by the overlap, keeping rotation. Menu checkbox with a push counter (default on); the first push is logged.

## Session robustness + reload test (installed 19:50, untested)
- `respawn_ghost(reason)`: destroys parts and the dummy, resets anim, look and candidates, sets phase back to "wait", bumps `ghost_gen`.
  - It's triggered by a watcher every 0.5 s when the PlayerObj address changes (load, death, area change), or when the ghost's first part no longer answers get_Name (folder unloaded).
- Disconnect: ghost hidden (DrawSelf false) when the newest network sample is older than NET_TIMEOUT 2 s + delay; shown again when data resumes.
- Reload test (menu "Tests"): `request_reload()` calls `SaveDataManager.loadFileAutoRequest(LoadSlotNo or SaveSlotNo, false, false, false)`, i.e. what Continue does; read-only, and saves stay blocked.
  - 10 rounds, one every 45 s. PASS = ghost_gen rose, ≥5 parts, a clip bound after the load (`anim.bound_t`), and the network seq rose with the ghost not hidden. Timeout 90 s. Results in `reframework/data/coop_reload_test.txt`.
- Saves before the test match the 14:49 backup (hashes snapshot in `local/save_hashes_before_reload_test.txt`).
- **Run 1 (19:47–20:09): 5 PASS / 5 FAIL. All failures were the test's 90 s timeout, not the mod.**
  - Every round rebuilt the ghost and the network kept flowing.
  - **Saves were byte-identical afterwards**; 1 autosave attempt was blocked.
  - Timeline per round: `loadFileAutoRequest(slot 0)` → **the player immediately becomes a temporary loading-scene player** at (72.9, 29.4, 26.0) (the Pl2000/Chapter0 spot, no Ethan meshes, so "build Ethan: no Ethan mesh") → **the real player appears about 80 s later** → **Ethan is fully rebuilt and animating 7–8 s after that**.
  - Fixes: timeout 180 s; PASS lines report load time and ghost-back time separately; no ghost is spawned unless the player's name starts with `Pl0000` (Ethan). Known limit: chapters played as other characters (e.g. Mia) get no ghost until handled.

## In-game Connect panel (installed 20:15, untested)
- The owner skipped the reload rerun ("chapter 1 loading scene takes too long"). The rebuild path itself was proven (7–8 s after the real player appears).
- CoopNet.cs:
  - Steam initialises in **every** mode (own SteamID and relay status are always in the status file).
  - `PollCommand()` reads `reframework/data/coopnet_command.txt` once per IO tick. `steam <SteamID64>` (validated > 76561197960265728) switches to Steam and sets the peer live; `bot` switches to the bot.
  - Old samples are cleared on a switch; the config is saved (`SaveConfig`) so the next launch reconnects; `lastCommand` goes in the status.
  - UDP/echo are config-only (they'd need socket rebuilds).
- coop_dummy.lua: a "Connect" tree at the top of the menu, open on first draw:
  - status text (Bot test / Not connected / Waiting for your friend / Connected, from network freshness);
  - your SteamID + Copy (`sdk.copy_to_clipboard`);
  - friend ID input (17 digits starting 7656119), Connect, Test with bot.
  - The body is pcall'd inside the tree so `tree_pop` always runs.
- Kit README step 4 now uses the panel instead of editing JSON.
- Verified after hot-reload: bot mode with Steam up (`relayStatus=100`, steamSelf present).
- **20:18: the owner confirmed "Panel works".**

## v0.3 (2026-10-29 evening)
- Installer `install-coop-re7.ps1` + `Install.cmd` (PowerShell 5.1-compatible):
  - finds Steam via HKCU SteamPath and libraryfolders.vdf, checks free space, robocopies the game, writes steam_appid.txt;
  - downloads REFramework.zip and csharp-api.zip from the pinned nightly-01433 with SHA-256 checks (dinput8.dll only, plus all of csharp-api);
  - copies the kit's reframework/ (keeps an existing coopnet_config.json), backs up userdata\*\418370\remote to Documents\RE7-coop-save-backups, writes the "Start RE7 Co-op" .cmd and a desktop .lnk.
  - **Tested end-to-end against a fake game folder** (all 6 steps OK, hashes verified), plus the `-NoGameCopy` update path (friend ID kept).
- Saving: coop_saveguard reads `coop_settings.json` (`allow_saving`) every 2 s; when allowed, hooks return CALL_ORIGINAL. CoopNet `BackupSaves` uses `ISteamUser_GetUserDataFolder` → sibling `remote`, copies to `reframework/data/save_backups/<stamp>_<reason>/` (keeps 20), at every plugin start and on `backup <reason>`. **Launch backup verified (3 files).**
- Packet fields: animId = chapter (`GameManager._CurrentChapter`), animFrame = echo of the newest peer sender time mod 1000 s, giving RTT. The bot echoes too and has `botChapter` to fake another chapter.
- HUD (`draw.text`, top-left): connection with peer name and ping, other-chapter warning, version-mismatch warning (bad packets rising), saving state. Nameplate via draw.world_text 2 m above the anchor (Steam `GetFriendPersonaName`; "Bot" in bot mode). Teleport via MovementController.warp (same chapter only).
- 20:50 owner: "appears to be working", but saw the **model desync from the controller**. Cause: **`pl0000_Hands_Crouch_Loop` jams like Stand_Loop**; together with a blend false positive (JogB reported 48 = JogL's length), the watchdog chained into two full ghost rebuilds.
  - Fix: blacklist Crouch_Loop; crouch-still is WalkCrouch_Loop held at speed 0; WRONG BIND needs two consecutive checks (re-check after 0.5 s).
- Chapter switcher: enumerate `app.GameManager.ChapterNo` statics → `getChapterJumpDataKey(value)` → `chapterJumpRequest(key, false, "")`. **Refused while allow_saving is on.**
- Floating "RE7 Co-op" window (`imgui.begin_window`, always paired with end_window, body pcall'd) with Connect/saving/display and Testing sections (bot, rebuild, teleport, reload test, chapter switcher). Shown while the REFramework menu is open.

- 20:55 chapter switcher: the first attempt "didn't work" because **allow_saving was on**, and the refusal only showed on the "Last:" line. Saves were untouched; backups from launch and from switching saving on exist. Now a jump while saving is on switches saving OFF, waits 2.5 s for coop_saveguard to re-read, then jumps; there's a red notice and everything is logged. **The owner's jump worked**: `chapterJumpRequest("Chapter3_Start")` → respawn → Ethan rebuilt 8 s later. A chapter jump is a much faster load test than Continue in Chapter 1 (about 80 s). In Chapter 3 the player is named `Pl0000`, which the Ethan check accepts.
- Head look error after a manual Rebuild Ethan ("Invoke threw an exception"): stale look2 joint cache. assemble_from now clears look2 and look.err.
- The bot circled its first-ever centre (Chapter 1 coordinates), so after a jump it was outside the map. It now re-centres on a chapter change, or when the player is more than 30 m (horizontal) or 10 m (vertical) from the circle. Hot-reloaded 21:00:53.

- **21:05 owner: after chapter switching, cutscenes were heard but not shown and the player stood outside the map** (probe: y = 0.000, a default position). The logs show **seven jumps in 50 s**, several before the previous had loaded (Chapter4 ×4, Chapter7_1, Chapter8, Chapter3). Most likely back-to-back `chapterJumpRequest`s left GameManager's chapter-jump state machine half-switched. The single jump at 20:55 had worked.
  - Fixes (installed 21:10):
    - **One jump at a time:** refused while `GameManager.RequestChapterJump` is set, until the new player has appeared (2-minute escape hatch), and for JUMP_SETTLE = 10 s after it appears.
    - **Collision pushes only while the local player is walking** (`PlayerMovement.get_isMove`) and the ghost isn't hidden, so a warp can never fire during cutscenes or loads.
    - The rebuild also resets anim.motion, ready and verify (fixes the head-look error after Rebuild Ethan).
  - Recovery: restart the test copy (saving was off).
  - Chapter7_1 and Chapter8 aren't Ethan sections (no ghost there anyway).
  - **21:14 verified by the owner:** after restarting the test copy, a single jump plays its cutscenes normally.
- 21:15 owner: "the co-op dummy is doing loops around during the cutscene". Cutscene detection: GameManager's static `_GameEventMan` (app.GameEventManager) → `RunningEventControllers.Count > 0`, or `GameManager.PlayingMovie ~= nil`, debounced 0.5 s.
  - The ghost is hidden while *we* are in a cutscene, and while the peer's flags carry a new bit `STANCE_CUTSCENE = 8` (packed in animBank, no format change).
  - The HUD shows "Friend is watching a cutscene"; state changes are logged with the running-event count.
  - Installed 21:18. **Verified by the owner:** the ghost is hidden during the cutscene and back afterwards.

- 21:20 (installed, UNTESTED): the owner was stuck in Chapter 3's chair after its cutscene; two autosave requests were skipped during it, and the scene probably waits on "save finished".
  - Save guard v2: in block mode, requests run and `via.storage.saveService.SaveService.saveSingle()/(Int32)/saveSlotDialog()` are skipped and report true. Menu saves are still refused at the request. `save_block_mode="strict"` restores the old behaviour; strict is forced if the write hooks are missing.
  - Save hashes before the test: `local/save_hashes_before_writeblock_test.txt`. **Compare after the Chapter 3 test before trusting v2.**
  - The ghost now builds for any playable character (Pl\d) that has a Shadow body; clips are matched by suffix; players without a Shadow body get no ghost.
  - Still todo: make refused chapter jumps more visible; publish v0.3 (needs the owner's OK).

### SAVE INCIDENT (found 2026-10-30)
- With saving OFF, **chapter jumps wrote the real Steam save folder**: `data00-80.bin` (512 B) at 21:03:03 (Chapter8 jump, guard v1), and data000/data00-1/data00-3 at 21:22:24 (data000 went 87 KB → 6.6 MB, guard v2 in "write" mode, which logged nothing). Chapter jumps save through internal paths that neither guard hooked.
- All plugin backups (20:46, 20:48, 21:00) are byte-identical to the 14:49 morning backup, which is the real progress.
- **2026-10-30 10:22: restored the morning saves with the owner's OK.** The suspect files are kept in `local/save-backups/2026-10-29_2122_suspect/` (data00-80.bin moved there). The restored files were touched with the current time so Steam Cloud treats the local copy as newest. If Steam shows a conflict, keep the local copy.
- The guard is strict by default again, plus hooks on 20 internal paths (chapterJump*Save, folderSave, saveFile*Core/Single/Auto/Menu, dataSaveA–D).
- **2026-10-30 10:24–10:27 supervised jump test: PASS.** Continue, one jump to Chapter3_Start, the cutscene, then quit. **All 3 save hashes unchanged.** The guard blocked chapterJumpEnemySave and chapterJumpEnemyStampSave at the jump, saveFileAutoRequest after the cutscene, and folderSave ×11.
  - `data00-80.bin` (512 B, mtime 21:03:04) **reappeared**: Steam Cloud re-downloaded it at launch. It's an old jump artifact in a separate slot; left alone.
  - Watch whether blocking folderSave affects in-session area state (items or doors resetting).
  - **The owner could move after the Chapter 3 chair cutscene** with the strict guard and internal hooks.
  - On Continue the temporary loading-scene player was `pl2000` and it **has** a Shadow body, so a ghost was briefly built for it until the real player appeared. Harmless.

## Published (2026-10-29)
- 20:22: pushed **v0.2** (b64adbf): auto Ethan, stance sync, head look v3, collision, respawn after loads, net-timeout hide, Connect panel. Personal-info scan was clean before the push.
- Mod repo (MIT): https://github.com/xXCroissantXx/coop-re7, initial commit 607e7c6. It contains the kit's reframework/ files, README, LICENSE and docs/NOTES.md (a scrubbed copy of this file, with local paths replaced). Built from `<publish folder>`.
- Hub contribution: fork xXCroissantXx/coop-anything, branch `game/resident-evil-7` cut from upstream 3dbf6dd, commit 547b864. **Draft PR https://github.com/cranebeaker/coop-anything/pull/257** (mergeable, no CI checks reported yet).
  - Changes: the directory entry (qa none, status prototype, steam-relay), regenerated DIRECTORY.md, the RE Engine playbook row, and games/resident-evil-7/README.md.
  - Re-applied to the fresh upstream by `local/build/apply_hub_changes.py`.
- Tooling: GitHub CLI 2.103.3 portable in %LOCALAPPDATA%\Programs\gh (verified against the release checksums; the MSI got stuck on 1618). Git 2.56 via winget. gh is logged in as the owner, with commits under their noreply address.

## Next phases (not started)
- Phase 4, Choose: likely host-authoritative. The host runs the world and enemies, and the client sends input and pose. Transport: Steam networking (relay) via a native REFramework plugin, since Lua has no sockets.
- Hard problems to expect: a single-protagonist game (the second player needs a puppet or ghost actor), scripted chases (Jack), cutscenes, item and key progression sync, and the save system.

## Open questions
- Does the friend own RE7 on Steam (same build)?

## v0.4: easy joining (2026-10-31)

Prompted by the RE2 (2019) multiplayer mod on Nexus (mod 3118, Kenjiro, 2026-10-30): lobby from the game's
menu, connect by Steam invite / IP / LAN, native `REENGINECOOP.dll` + large Lua, exported mesh/rig/face data,
character choice. Code is not public and asset/modification use needs the author's permission, so only ideas
were taken. Its users' main problems: wrong REFramework version (hang on "loading"), files in the wrong
folder, missing sounds for player 2, RT build only.

- **Friend list**: `ISteamFriends` flat API (`GetFriendCount`/`GetFriendByIndex` with k_EFriendFlagImmediate=4,
  `GetFriendPersonaState`, `GetFriendGamePlayed` → FriendGameInfo_t whose first 8 bytes are the CGameID; low
  24 bits = app id 418370). Written every 2 s to `coopnet_friends.txt` (id, flags R/C/I, version, name).
- **Invites without callbacks**: Steam rich presence (shared automatically between friends in the same game).
  `coop_re7` = mod version (we're running co-op), `coop_re7_to` = SteamID we connected to. The other side sees
  `coop_re7_to == self` → invite line on the HUD and an Accept button (= connect back). Cleared on unload.
  Not yet verified with two accounts.
- **Go to my friend's chapter**: `_CurrentChapter` values = `ChapterNo` enum values; jump targets logged:
  Chapter0=2, Title=3, Chapter1=4, Chapter3=5, Chapter4=6, FF000=7, FF030=10, FF040=11, FF050=12,
  Chapter123=13, Chapter324=14, Chapter7_1..4=29..32, Chapter8=35, Chapter9=37 (33 targets in all).
- **Auto-teleport after a jump was dropped.** Tries: teleport fired during load (ghost not built yet) and
  reported success anyway; then onto the bot whose circle had been centred on the loading-scene position →
  outside the map; then right after a cutscene → the game loaded another chapter. RE7 streams areas in, so a
  long warp can land in unloaded space even with a real friend. Teleport is now manual, onto the friend's
  position ~1 s ago (walked ground), refused beyond 40 m.
- Bot: `botrecenter` command sent when the ghost is rebuilt after a load; `botchapter <n>` (not saved;
  "Test with bot" resets it; it had been persisted by SaveConfig once and kept the bot in Chapter0).
- ~10 debug chapter jumps in one session again broke the game (black screen in Chapter3). A fresh launch
  fixed it; the single-jump test then **passed** (2026-10-31, bot claims another chapter → Go to my friend's
  chapter → arrived at its start, playable).
- Fixed: periodic diag in the ghost update indexed `get_player()` while it was nil during a load.

## v0.5: polish (2026-10-31)

- **Names**: REFramework's default ImGui font (1.92, dynamic glyphs with Windows fallbacks) already renders
  Cyrillic, CJK, kana, Hangul and accents in `draw.text`/`draw.world_text`. Loading Microsoft YaHei with
  `imgui.load_font` *broke* Hangul (YaHei has none) → reverted. No font change shipped.
- **Footsteps**: the player has `app.FootEffectController` with `callSE(SETriggerTypeEnum, via.vec3,
  UInt32 material)`, which plays Ethan's footstep at any position. `SETarget` (Player=0, PlayerJog=1,
  PlayerCrouch=2) picks the sound set; set it for the ghost's stance and restore. Steps fire per stride
  travelled by the ghost (walk 0.75 m, jog 1.05 m, crouch 0.6 m), alternating LeftLegContact/RightLegContact,
  with the local player's `MaterialID`. Heard and confirmed by the owner with the bot.
- **Non-RT**: the pinned nightly has only a unified `REFramework.zip` (runtime game/TDB detection, DX11 code
  present), no `RE7_TDB49` asset. The installer reads `appmanifest_418370.acf` for `"BetaKey"` and warns.
  Not run on non-RT.
- Research helper `coop_devexec.lua` (test copy only, never in the kit): runs `data/coop_exec.lua` once and
  writes `coop_exec_out.txt`, so probes run without "Reset scripts". All REFramework autorun scripts share
  one Lua state, so globals from coop_dummy are visible to it.

## Enemy sync research (2026-10-31)

- Enemies are in `app.ObjectManager.ManagedObjects` (List<List<GameObject>>, 11 lists in Chapter3); list
  **1** held the enemies (Em3300, Em3390, Em6100, Em3000, Em3200, Em3100). The `ListType` enum (EnemySave=0,
  Item=1, ...) does not match these indices; find the list by contents, not by number.
- Each enemy's folder is scene data, e.g. `Chapter/Chapter3/Enemy_c03/Enemy_c03_1` (Em3000),
  `.../c03_1_deactivate_DinnerAfter` (Em3100, Em3200). Inactive ones have Draw/Update false.
- **Stable ID**: regular enemies (Em3000, the Molded) have `app.EnemySave` with `SaveGUID` (System.Guid; read
  `mData1..3`, `mData4_0..7`; `ToString()` on the ValueType returned garbage). Saved scene data, so the same
  on both PCs. Story/boss characters (Em3300, Em3100, Em3200, Em6100) have no EnemySave → fall back to
  folder path + name.
- **Health**: `app.DamageController` (Em3000: `app.Em3000.Em3000DamageController` → EnemyDamageController →
  DamageController): `get_health`/`get_maxHealth` (Em3000 10000/10000), `get_isDead`, `setHealth`,
  `addManualDamage`, `doDie`. `app.EnemyStatus.get_isFinishedDead`, `get_isAppeared`.
- Plan: (1) deaths: a kill on either side kills the same enemy on the other (idempotent, no authority),
  remembered for the session so an area loaded later spawns it dead; (2) damage events applied on both sides;
  (3) host-authoritative enemy movement (the guest's copy driven like the ghost). Same chapter only.
  One-PC test: the bot sends "friend killed / damaged the nearest enemy".
- **Correction: Em3000 is Jack Baker** (the stalker: Em3000Grapple, Em3000DoorActionController; Em3001/3002
  are his later fights). The Molded are Em4000/Em4100/Em4200. Jack also has EnemySave + SaveGUID.
- Test spawn: an inactive enemy in a loaded folder comes alive with `GameObject.set_UpdateSelf(true)` +
  `set_DrawSelf(true)`; `app.MovementController.warp` moves it. It attacked at once (owner took 660 damage).
  No `app.EnemyGenerator` exists in the Chapter3 main-house area.
- **Kill**: `DamageController.setHealth(0, max)` sets isDead but the enemy keeps walking: not a kill.
  `DamageController.newFakeDamageInfo(damage, attacker, target)` (static) + `addManualDamage(info)` with
  damage > health → health 0, death/down animation (motion 0), owner confirmed Jack went down.
  `isFinishedDead` stayed false (Jack revives in the real game; check whether he gets up).
- Consequence: stalkers/bosses (Jack) only go down temporarily, so sync "down" as an event and don't
  remember them as dead; regular Molded die for good and are remembered. Still to test on a Molded.
- **Step 1 built** (`coop_enemies.lua` + reliable events in CoopNet.cs): "R7E1"+UTF-8 text over
  `k_nSteamNetworkingSend_Reliable` (8); Lua writes `coopnet_ev_out.txt` (ids from os.time()*1000, so they keep
  growing across Reset scripts; CoopNet skips what's in the file at its own start), CoopNet writes the last 50
  received to `coopnet_ev_in.txt` (deleted at start; count from 1). Event: `kill <id> <chapter> <name>`.
  Bot: `botevent <text>` delivers an event "from the friend" after the simulated latency.
- Bugs found testing: `fs.read` of a missing file returns "" (not nil), so the "first read = already handled"
  rule swallowed the first real event; fixed. A kill of health+1000 left Jack on 2300/10000 (damage is scaled,
  ~0.7): now hp*4+1000, up to 3 hits until `get_isDead`.
- **Result 2026-10-31**: local kill of Jack detected and sent (`sent: kill g:71041570-... 5 Em3000`); bot's
  kill of Jack applied, Jack went down (owner confirmed), not echoed back. Not yet tested: a Molded, the
  "remember for later" path, two real players.
- **Step 2 (damage)**: scan compares `get_health` every 0.25 s; a drop while alive sends `dmg <id> <chapter>
  <amount> <name>` (the health actually lost, after the game's scaling). Receiving: `setHealth(hp - amount,
  max)`, never below 1 (the kill event finishes it properly), and `e.hp` updated so it isn't sent back.
  No hit-reaction animation on the receiving side yet.
- Finding a Molded: only `*_Start` jump keys drop into gameplay; `Chapter8` (key without _Start) went to the
  title. Chapter4_Start loads as Pl2100 with 4 Em4000, 3 Em4100, 2 Em4200 asleep plus Mia (Em2000) awake,
  but the level didn't load (grey void) from the title; restart fixed it. Molded still untested.
- **Results 2026-10-31 (fresh launch, Chapter3, all driven via coop_devexec)**: bot kill of the sleeping
  Jack labelled Em4000 → remembered; waking Jack → killed at once, not echoed. Bot hit 2500 → Jack 10000 →
  7500 exactly, not echoed. Local hit of 1000 → health 6800, sent `dmg ... 700.0`. Bot kill → down.

## Enemy movement research (2026-10-31)

- **Targeting**: `app.EnemyThinkBase` (Em3000Think etc.) has `_Target` (GameObject), `setTarget(GameObject,
  ReasonType)`, `updateTarget()`, `get_targetStatus()` (ICharacterStatus) and `playerStatus` (IPlayerStatus);
  Em3000Think adds `setTargetPlayer(GameObject)`. The player carries `app.AI.AIVisionBeacon` (enemies'
  `app.AI.AIVisionSensor`/`AIHearingSensor` perceive beacons). Pointing an enemy at the other player's ghost
  needs a target with a status component; not tried yet.
- **Animation**: enemies have `via.motion.Motion` with 8 layers (TreeLayer), driven by `via.motion.MotionFsm`.
  Layer state readable: `MotionBankID`, `MotionID`, `Frame`, `Speed`, `EndFrame`. With
  `MotionFsm.set_Enabled(false)`, `TreeLayer.changeMotion(bank, id, frame, interp, 2, 0)` plays a chosen clip
  and the frame advances: an enemy can be animated by hand. `MovementController.warp` moves it.
- AI off: `EnemyOrder.requestThinkOff(Object)` / `requestThinkOn(Object)` exist (not tried).
- Jack after a death stays down (bank 50 id 0, frame 405) even with `setHealth(10000, 10000)`; he can't be
  reused for a recording until he gets up by himself or the area reloads.
- **Step 3 built** (coop_enemies.lua + "R7S1" unreliable snapshots in CoopNet.cs): host (lower SteamID; bot
  mode = host) writes `coopnet_es_out.txt` 10 Hz: `seq`, `t <time> ch <chapter>`, one line per awake enemy
  `id x y z yaw bank motion frame speed` (layer 0). Guest: per-id timelines (host clock + smallest offset),
  puppet = `MotionFsm.set_Enabled(false)` + `EnemyOrder.requestThinkOff(owner string)`, placed 0.15 s behind
  with `MovementController.warp`, clip via `TreeLayer.changeMotion(bank, id, frame, 8, 2, 0)`, frame corrected
  with `set_Frame` beyond 4 frames; released (brain back on) 3 s after the enemy leaves the snapshots.
- Bug: `local _, s = l and parse_line(l)` keeps only the first return value (s = nil): first recording empty.
- Chapter3 jump fired by script ~15 s after the title appeared loaded Chapter3 with a black screen and no
  dinner cutscene (loadingState stuck at 0); the owner's own jump after a restart worked.
- **Record/replay test 2026-10-31 (Jack, fresh launch)**: 6 s recording, 59 samples, clips 20:100 (walk) then
  20:1600; replay with FSM off retraced 24.65,8.31 → 24.5,12.1, clip switch at 3.5-4.0 s (recorded 3.7 s),
  frames advancing; released after the end. Not yet seen by eye; enemies still only target their own player.
- Bot/ghost bugs found 2026-10-31: (1) follow-mode bot replayed our own cutscene bit (recorded during the
  dinner scene), so the ghost hid for "their cutscene"; the hide test read `anim.flags`, which only updates
  while the ghost animates, so it never un-hid. Bot now masks Bank to stance bits; hide test reads the newest
  sample's flags. (2) A hide applied right after a rebuild was undone by the build steps (parts switched back
  on): a visible, frozen, nameless Ethan with ghost_hidden=true. Draw state is now re-applied every 0.5 s.
- Jack replayed as a puppet looked "mostly natural" (owner) but held his hands as if carrying something with
  nothing in them: his held weapon (EquipManager) isn't driven when the FSM/AI are off. To sync later.
- **Ghost stuck hidden after the peer's clock restarts** (2026-10-31): the receiver's clock offset is the
  smallest `now - senderTime` seen, never raised. When the sender's clock restarted (CoopNet hot reload here;
  a friend restarting their game in real play), every new sample mapped minutes into the past → "no data"
  forever, until Reset scripts. Now the offset restarts when a sample looks 5 s+ older than the offset
  allows (and on a seq reset); same for enemy snapshots.
- **Cutscene fast-forward (testing)**: no skip API (cutscenes are `app.GameEventController` + via.timeline;
  no skip methods). `via.Scene.set_TimeScale(8)` on the current scene while `local_cutscene()` is true, back
  to 1 when it ends: the Chapter3 dinner scene finished in ~8 s, every scripted step intact. Button
  "Fast-forward this cutscene" and option "Fast-forward every cutscene" in Testing.
- **Targeting test 2026-10-31**: `Em3000Think.setTarget(ghost VrDummyPlayer, Specified=4)` was accepted
  (get_Target = VrDummyPlayer) but cleared within a second (target none): `updateTarget` re-picks from the
  vision/hearing sensors, and the ghost (no status component, no AIVisionBeacon) isn't a valid target. Jack
  stood still. Faking a second player (beacon + PlayerStatus on the ghost) risks the game treating it as the
  player.
- **Better design: per-enemy ownership.** Each enemy is run (real AI) by the game of the player it's closest
  to / engaged with, and is a puppet in the other game. The owner hands it over (reliable `own <id>` event)
  when the other player is clearly closer (hysteresis). Enemies then always target a real local player, and
  their hits land in the game of the player they attack. No fake targets.
- **Ownership built** (coop_enemies.lua): `em_move.own[id]` = "me"/"peer". Default: the game where the enemy
  is awake; both sending → host (lower SteamID) keeps it. Owner hands over (reliable `own <id> <ch> <name>`)
  when the friend's Ethan is 3 m+ closer (checked every 0.5 s; off in bot mode). Handed enemies are held as
  puppets until the friend's snapshots arrive; no data for 3 s → taken back. Receiving `own` → release
  the puppet, run its AI.
- **One-PC test 2026-10-31 (Jack)**: hand to the bot → FSM off, own=peer; 3 s later taken back (FSM on,
  own=me). Hand to the bot, then bot's `own` event → released at once, "your friend handed Em3000 to you".
  Real handovers between two games untested.

## Doors and items (2026-10-31)

- **Doors**: `app.DoorPush` (is_a `app.Door`; 8 in the Chapter3 main house 1F/2F, found with
  `scene:findComponents(app.DoorPush)`), each with `SaveGUID` (unique), `get_isLocked`, `get_doorState`
  (0 closed, 1 locked, 2 little open, 3 pushed, 4 auto-open, 5 opened, 6 auto-close), `get_currentAngle`,
  `unlockDoor()`, `requestAutoOpen(OpenSide)` (Auto = 2 → swung to 90°, state 5), `requestClosed(bool)`.
  Also `Fsm`, `FsmStateTracker`, `MapDoor` on the same object. Key doors are pairs (L and R halves).
- **Items**: `app.Item` (42-58 in the area; ObjectManager list 3 here), `SaveGUID`, `ItemDataID`
  ("ShotgunBullet", "Herb", "3CrestKeyA"...), `get_ItemData().Category` (ItemCategoryType: 0 Other, 1 Weapon,
  2 Shell, 3 Drug, 4 KeyItem, 5 File, 6 Map, 7 Material, 8 StackWeapon, 9 UsableKeyItem, 10
  DiscardableKeyItem (coins, lockpicks, car key), 11 SupplyBox). Pickup = `changeStateInventoryIn(GameObject)`
  (hooked); `disableFromScene()` hides it (Draw/Update false, state 6) without touching any inventory.
- **coop_world.lua**: shares the reliable event channel via `coop_send_event` / `coop_world_on_event`.
  `unlock <id> <ch>`, `open <id> <ch>` (states 3-5 only, not the approach creak), `took <id> <ch> <name>`
  for supplies (category not 4/5/6/9/10); key items stay in both worlds. Took-events for unloaded items are
  remembered and applied when the item appears. Doors/items found every 3 s / 2 s, doors polled 4x a second.
- **Bot test 2026-10-31**: bot `open` → a closed door swung open (state 5); bot `unlock` → the left key-door
  half unlocked, "your friend unlocked a door"; bot `took` → a Herb vanished, "your friend took Herb". No
  echoes (sent 0). Own pickups not yet tested.
- Own pickups: a hook on `app.Item.changeStateInventoryIn` never fired when the owner picked up handgun ammo.
  The world item went `getItemState` 0 → 6 (hidden, like `disableFromScene`) and a separate inventory Item
  appeared (`wp1011_HandgunBullet_Item`, state 2). Now detected by polling world items for 0 → 6 (4x a
  second), skipping ones hidden on the friend's word. Own door push: `open` sent (5c8bdf4a-...).
- Own pickup via the state poll, 2026-10-31: `sent: took 3ff9028b-... 5 HandgunBullet`. Door and item sync
  checked both ways on one PC.

## Story and cutscenes research (started 2026-10-31)

- `app.GameFlowFsmManager.GameFlowKindEnum` splits chapters into story stages: C00_Main, C01_Main,
  C03_1..C03_5_Main (main house), C04_1..C04_3_Main, FF000/030/040/050_Main, C07_1..C07_4_Main, C08_Main,
  C03_IMD_Main, C09_Main. A finer progress marker than `_CurrentChapter`; runtime state not read yet.
- Cutscenes: `app.GameEventController` (RunningEventControllers on `_GameEventMan`), each with a
  `GameEventSetting` (`get_eventSetting`) and `GameEventTask`; start/end handlers exist (`add_StartHandler`,
  `add_EndHandler`). No skip API.
- `app.GameFlowFsmManager` (singleton): `CurrentMainGameFlow`, `setCurrentFlow(string)`, progress numbers
  per flow keyed by a uint32 hash: `setProgressiveNo(hash, int)`, `jumpProgressiveNo(hash, int)`,
  `getProgressiveNo(hash|string|Guid)` → via.userdata.Variable; `sendEventEnded(hash)`, `isEventEnded(hash)`,
  `sendBattleEnded(hash)`; dictionaries `Flows`, `Gimmicks`, lists `EventEnd`, `BattleEnd`.
- Cutscenes: `GameEventController.requestSetup(GameEventSetting, Transform)`; `GameEventSetting.get_eventName`
  gives names like `c03e00_00` (chapter 3 event 00 part 00). `onEndHandler(GameObject, bool)` fires once per
  object taking part (Pl0000, Em3000, doors, props).
- **Logged 2026-10-31, Chapter3 jump + dinner + a few minutes of play**: load sets flows c03_1..c03_5 and
  progress 0 on five hashes (2c60d2ac, 43faffd1, 2e2d3671, 9fb77189, 69442936); dinner = cutscenes
  c03e00_00 → c03e00_01 → c03e00_02; then `sendEventEnded 9fb77189` and progress on flow 9fb77189 went
  100 → 200 → 300 → 400 as the owner followed the objective (one step per story beat). A title-screen intro
  c00e00_00 ran under flow c00_Main in between (the jump passes through it).
- So story position = (flow hash, progress value) pairs plus "event ended" hashes; cutscenes have stable
  names. Next experiments: what `jumpProgressiveNo`/`setProgressiveNo` do to a game that's behind (world
  state, gimmicks), and whether a named cutscene can be started on the other side.
- **`jumpProgressiveNo(9fb77189, 500)` changed only the number** (owner unpaused and played 30 s: no new
  objective, event or world change). Progress numbers record the story; triggers (areas, items, cutscene ends)
  drive it.
- **Starting a named cutscene works**: `GameManager._GameEventMan` (`app.GameEventManager`) has
  `requestEvent(String name, Transform, Boolean)`, `isSameEventRequested(String)`,
  `requestEventFromOtherEvent(String, Transform, String)`. 41 GameEventSettings were loaded in the Chapter3
  main house (c03e00_00..02, c03e01_00..02, c03e02_00/10, c03e03_00/01, Jack's em3000_* moves, door kicks,
  interact actions). `requestEvent("c03e01_00", nil, false)` started that story cutscene at once (the deputy
  at the window), out of order.
- Story-sync design (one player leads): mirror story cutscenes by name (`c\d\de\d\d_\d\d`) from the game that
  triggers them (hook `GameEventController.requestSetup`), play each once per side (`requestEvent`), and copy
  progress numbers (`setProgressiveNo`) and ended events so later triggers line up. The follower's player is
  pulled into the scene wherever they are.
- **coop_story.lua built** (events `story <name> <ch>`, `prog <hash> <value> <ch>`, `evend <hash> <ch>` via the
  shared reliable channel; hooks on GameEventController.requestSetup, setProgressiveNo, sendEventEnded).
  Bot test 2026-10-31: bot `story c03e00_00` → played in the owner's game ("your friend's story"), not echoed;
  bot `prog 9fb77189 600` → 500 → 600; a later `prog ... 300` left it at 600 (never backwards). Own sends
  not yet confirmed.
- **Hung-cutscene recovery 2026-10-31**: after Reset scripts emptied the played list, the bot's `story
  c03e00_00` replayed the already-finished dinner; its controller hung (`Process` 3), the owner couldn't
  move, and `requestEvent("c03e00_02")` didn't help. A chapter jump queued by `jump_to_chapter` didn't fire
  while the event ran. `RunningEventControllers[0].EventTask:doTerminate()` cleared the running event
  (`local_cutscene` false) but the player stayed locked; a direct `chapterJumpRequest("Chapter3_Start")`
  then reloaded the chapter (respawn 20:48:55) and the dinner played normally. Fix: the played list is now
  kept in `coop_story_played.json` per chapter, so a finished cutscene is never replayed on the friend's word.
- On chapter load the game calls `setProgressiveNo` 100→400 for 9fb77189 at once (restoring progress); these
  go out as `prog` events (harmless: the other side only moves forward).
- **Chapter jumps keep the story progress of the session.** After the jump, the game restored 9fb77189 to
  100→400 (and this session had been pushed to 500/600 by tests); the dinner c03e00_00 then hung at
  `Process` 3 even on a fresh jump. A full game restart clears GameFlowFsmManager; the first jump of a
  session (progress 0) plays the dinner normally. Story tests that push progress numbers need a restart after.
- After a full restart and one Chapter3 jump, the dinner played and the owner had control again.

## Player deaths (research 2026-10-31)

- `app.PlayerDamageController` (DamageController): `canDie(DamageInfo)`, `isEnableDieByDamageInfo(DamageInfo)`,
  `get_isEnableDie`, `doDie(DamageRecord)`, `add_DieHandler(Action)`, `playDeadMotion(DamageInfo)`,
  `playBlowDeadMotion(dir)`, `get_isLegCutDead`; `app.PlayerStatus.get_IsDead/IsDeadInternal/IsDeadAction`.
  Game over: `GameManager.setGameOverFlag(bool)`, `isGameOver`, `checkGameOver`, `gameOverUpdate`,
  `setGameOverPauseFlag`; screen `app.GameOverScreen`. Hooking `canDie` (return false) is the likely place
  to stop a death in co-op.
- **coop_revive.lua built**: pre-hooks on `PlayerDamageController.isEnableDieByDamageInfo` and
  `DamageController.canDie` (player only, by address) return false (SKIP_ORIGINAL + retval 0) when a friend is
  with us; the player is held in place (warp) on 1 health; friend within 2.8 m for 3 s → health 35%. Both down,
  90 s alone, or the friend's `gameover` while down → a real death (`allow_death`, a self-hit). Events
  `down <ch>`, `up`, `gameover`.
- **Test 2026-10-31** (follow-me bot 2.5 m away): fatal self-hit 985 → health 1, not dead, `down` sent; 3 s
  later back up at 350/1000, `up` sent, no game over. Bot `down` → "Your friend is down! ... (2 m away)";
  bot `up` cleared it. Both-down and timeout paths untested.
- Downed look: `PlayerOrder.setReserveProne()` did nothing visible; `PlayerMovement.set_isCrouch(true)`
  (crouchRate 1.0, the owner's view dropped) + `PlayerOrder.switchPlayerOperatable(false, Base=0)` +
  `setDamageGUIMonochrome(true)` does; all reversed on revive/death. Re-applied each frame if the crouch drops.
- **Full revive test 2026-10-31**: bot set to stay, owner ~4.8 m away, fatal self-hit → down (crouched, no
  control, monochrome; health crept 1 → 81 from regeneration while down). Bot switched to follow, walked the
  trail and stopped 2.6 m away; revived at 21:03:55 (28 s after going down), `up` sent.
