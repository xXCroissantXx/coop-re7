# coop-re7: first two-player session checklist

Everything in coop-re7 has so far been tested on one PC against a simulated player (the bot). This list walks
two real players through every shared feature once, so problems show up in a known order. It takes about
45 minutes. Tick things off as you go and note anything odd (what you saw, roughly when).

**Before you start (both players)**

- [ ] Both installed the same coop-re7 release (the friend list warns if your versions differ).
- [ ] *Allow saving* **off** for this session (the default). Nothing you do will be saved.
- [ ] Voice chat open (Discord or Steam) so you can say what you see.

## 1. Connect (5 min)

- [ ] Both start **Start RE7 Co-op** and load any save.
- [ ] Each sees the other under *Your Steam friends in RE7 Co-op*.
- [ ] Player A clicks **Connect** next to Player B. Player B sees "*A* invited you to co-op" at the top left.
- [ ] Player B presses Insert and clicks **Accept**.
- [ ] Both see **Co-op: connected to *name* - *ping* ms** at the top left. Note the ping: ____ ms

## 2. Meet up in Chapter 3 (5 min)

- [ ] Both open **Testing → Chapter switcher** and click **Chapter3**, once each. (Or: one player clicks it,
      the other uses **Go to my friend's chapter**.)
- [ ] Watch the dinner (fast-forward is fine) until you can both move.
- [ ] Each can see the other's Ethan, with their name above it. Walk, jog and crouch around each other.
- [ ] You hear each other's footsteps.
- [ ] You can't walk through each other.

## 3. Doors and items (5 min)

- [ ] Player A pushes a door open. It swings open on Player B's screen too.
- [ ] Player A picks up some ammo, a herb or a chemical. It disappears from Player B's world.
- [ ] A key item, file or map stays for both (each picks up their own).

## 4. Enemies (10 min)

Jack appears soon after dinner. Saving is off, so getting hurt costs nothing.

- [ ] Both see Jack in the same place, doing the same thing.
- [ ] Shooting Jack on one screen lowers his health on the other (the RE7 Co-op window, *Testing*, shows
      "Enemy sync" with his health).
- [ ] Knocking Jack down on one screen knocks him down on the other.
- [ ] Walk away from Jack while your friend stays near him. He should keep chasing the nearer player
      (enemies change hands when the other player is 3 m closer).

## 5. Going down and reviving (5 min)

- [ ] Let Jack hit Player A until a fatal hit. Player A goes **down** (crouched, black and white, can't move)
      instead of a game over. Player B sees "Your friend is down!" with the distance.
- [ ] Player B stands next to Player A for 3 seconds. Player A gets back up.
- [ ] (Optional) Both get downed at once: that should be a normal game over for both.

## 6. Story (10 min)

- [ ] Follow the objective until a story cutscene starts for one of you. The other player's game should play
      the same cutscene (they're pulled into the scene).
- [ ] After it, both carry on normally. If someone is stuck and can't move, restart the game (nothing was
      saved) and note which cutscene it was.

## 7. Leaving (2 min)

- [ ] Player B closes the game. Player A's view of B disappears within a few seconds; enemies B was running
      come back to Player A within 3 seconds.
- [ ] Player B starts again and reconnects. A sees B again.

## Afterwards

Each player sends these files from their co-op folder (`Documents\RE7-coop\reframework\data`):

- `coop_dummy_log.txt`, `coop_enemies_log.txt`, `coop_world_log.txt`, `coop_story_log.txt`,
  `coop_revive_log.txt`, `coopnet_status.txt`

`coopnet_status.txt` contains your SteamID and Steam name; delete those two lines before posting it anywhere
public.
