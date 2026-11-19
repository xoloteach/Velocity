# Progression and rewind

## Earning and spending

Travel checks the horizontal displacement reported by the physics simulation against a speed and frame-time envelope. Each paid segment requires at least 18 metres of travel and 18 metres of separation from the previous anchor. A known cell can pay again after at least 126 metres of fresh motion, seven other recent cells, and another pass within one continuous journey. A teleport, retry or reload starts a new journey. Ineligible or discontinuous segments move the anchor without awarding currency. Ten speed thresholds pay once through stable transaction IDs.

The cache costs 25 earned SFC. Its table comes from `shared/game.json` and contains six integer weights totaling 10,000 tickets. Common draws 50%, Rare 27%, Epic 14%, Legendary 6.5%, Mythic 2% and Divine 0.5%. Duplicate trails convert to 2–12 materials based on tier. Three materials exchange for one SFC. The first earned trail equips automatically. Each purchase commits the exact result, currency, inventory and draw index before the coordinator shows the reveal.

Speed, acceleration and turning have independent levels. Upgrades start at 12 SFC, with a rising price and a gradual physical soft cap. Completing five levels of every stat unlocks prestige at a displayed SFC cost. Prestige resets the three upgrade levels, contributes to movement scaling and advances the rank while retaining mission and cosmetic progress.

## Save formats

Progress lives at `user://velocity-profile.a` and `user://velocity-profile.b`. The current revision contains schema, world generation version, slot identity, safe position and realm, campaign flags, upgrades, race result, SFC, materials, inventory, draw sequence, visited cells, settings and exact paid transaction IDs. Schema 1 records and the Godot prototype's `user://velocity-v1.cfg` have migration paths. The prototype config supplies its race result, speed limiter and effects preference.

Each commit stages a new revision, closes it and verifies its shape, length and SHA-256 before replacing the alternate slot. An interrupted staging write keeps the previous revision available. A damaged newest revision falls back to the valid copy and reports the rollback. If both slots fail validation, their bytes remain available for recovery. The recent audit retains up to 100 transaction summaries. Exact award IDs use a larger independent ledger so audit rotation cannot repay old objectives.

The Web build relies on persistent browser storage for `user://`. When the browser reports session-only storage, the game can continue with that session's progression and exposes a storage warning. A write failure in persistent mode rolls back the corresponding permanent transaction. Use a stable origin when confirming Web persistence. Earn SFC, change a touch layout position, buy a cache draw, close and reopen the game, then compare the wallet, item and settings. Native checks exercise on-disk reopening and corrupt-slot recovery. Exported browser storage and restart behavior require their own end-to-end check.

## Snapshot playback

Rewind samples coordinator frames at 24 Hz and holds at most 193 samples for eight seconds. A normal request rewinds three seconds. The first retained sample anchors the range, so playback restores up to 192 intervals. The coordinator restores hero and active actors and consumes the final recovery physics tick. Realm transitions and explicit checkpoint barriers empty the buffer. The ring discards its future when playback moves backward.

The movement cursor and its anchor come from the snapshot while the journey's accepted-distance high-water mark remains current. Repeating those metres has no effect on earnings. Wallet, purchases, permanent mission flags, upgrades and award history remain in the profile. Combat, population and the campaign coordinator define which local objects and reversible events are included.

## Reproducible checks

Run from the Godot project directory.

```sh
godot --headless --path . --script tests/progress_rewind_test.gd
```

The suite enumerates all rarity tickets, reopens purchases and checkpoints, corrupts isolated test slots, checks prototype migration and transaction rollback, and tests speed and travel earnings after rewind and retry. A four-actor fixture checks restoration of the hero, a car, a civilian and a prop and wraps the history ring to its exact capacity. The game's mission implementation and real entity history require an integrated run in addition to this fixture.
