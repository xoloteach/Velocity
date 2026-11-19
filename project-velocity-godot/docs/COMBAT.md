# Combat and rival encounters

Combat uses the runner's position and a facing-weighted soft lock. Light and heavy strikes have separate windup, active and recovery windows. There is one buffered input during late recovery. Contact requires reach, compatible height and a clear world ray. Enemy lunges and traces test a swept segment each tick, including a separate impact flag for an intentional second trace. Dodge provides lateral movement and a short immunity window. Counter accepts the final 0.29 seconds of a guard tell or 0.34 seconds of a rival tell, within 3.55 meters. Interact can start a takedown on a staggered or critically injured ordinary enemy.

Only one nearby enemy holds an attack lane at a time. Repeated light strikes can draw a guard or sidestep. Heavy strikes and counters break the response. Mirage can draw a real lunge away from the player. Slow time affects opponent movement and tell clocks while player inputs retain their cadence.

| Rival | First phase | Second phase | Final phase |
|---|---|---|---|
| Nullstride | Read the marked rush and use its recovery. | Avoid two displaced lanes and step out of their local slow field. | Two physical phaseable gates narrow the yard. Leave the radial tell and break the defense with a counter or reflected projectile. |
| Afterlight | Distinguish the solid runner and lane from the false trace. | Dodge, brake or phase out of the three-waypoint relay route. | Disrupt the repeating rush, projectile and delayed trace through rewind, counter, redirect or shockwave. Then finish during recovery. |

Boss phase boundaries are tied to health, and each phase has at least 0.25 seconds of visible telegraph before the next boundary can unlock. The final guards each require a documented interruption. Combat pauses rival clocks during the campaign introduction to preserve the first reaction window. The campaign receives one defeat event after the finishing beat.

Combat snapshots include stable IDs, positions, velocities, stance, animation time, health, phase, tell timers, projected paths, spent collision flags, armor, gate state and the player's queued or buffered actions. Restoring a snapshot rebuilds missing actors and derives collisions and telegraphs from that state. Restoring an actor does not emit campaign rewards or defeat events.

Run the physics fixture from the project directory.

```sh
godot --headless --path . --script res://tests/combat_integration.gd
```

The fixture covers obstruction, late contact inside an active window, targeting, combos, takedown, a coordinated 1v3, early and late counters, dodge immunity, mirage, slow time, rewind, every rival phase, projectiles, defense-break conditions and both wins using only timed counters and heavy inputs.
