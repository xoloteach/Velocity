# Godot systems integration

Systems are independent GDScript components. Avoid cyclic preloads. The root coordinator passes itself dynamically as game. Use untyped var game for cross-system calls and explicit types for locals inferred from its members. All coordinates are meters in Godot world space, Y up, forward -Z. The hero is a CharacterBody3D named runner. Collision layers are 1 world, 2 hero, 4 phaseable, 8 near-field actors, 16 water sensing or navigation when applicable. Hero masks 1 + 4 + 8, and drops layer 4 while phased. The world owns generation, static bodies, meshes and collision. Combat and population own their own data, nodes, snapshots and cleanup.

## Shared coordinator API

- game.runner is CharacterBody3D with position and velocity. game.hero_heading, game.health, game.energy and game.speed are floats.
- game.realm is String ("city" or "rift"). game.orbit is Vector2. game.quality is int 0–3. game.effects and game.paused are bool. game.sim_time is float.
- game.world, game.hud, game.combat, game.population, game.powers, game.progress, game.history and game.campaign are module instances.
- game.announce(message: String, duration: float = 2.6), game.event(key: String, payload: Dictionary = {}), game.damage(amount: float), game.teleport(to: Vector3, destination: String = "city"), game.pulse(key: String, location: Vector3, strength: float = 1.0).
- game.snapshot() -> Dictionary and game.restore(frame: Dictionary) are the coordinator's rewind integration. game.safe_position is last valid unphased ground.
- game.command(action: String) forwards input edges. Command keys comprise jump, interact, light, heavy, counter, dodge, lock, slide, lightning, shockwave, phase, tornado, redirect, mirage, slow, portal, rewind, pause, resume, restart, menu, upgrade_speed, upgrade_accel, upgrade_turn, pull, prestige, map, missions, race, patrol, skip, next.

## City and mission layout

City bounds x ±315, z +84 to -512 or larger. Main Calder boulevard x near ±10, z=15 to -330. Keep west-east streets centered z=-119 and z=-226 and don't put buildings on main campaign sites. Start (0,0,8). Central mission sites at (0,0,-30), (0,0,-113), (0,0,-148), (0,0,-202). Waterfront east/west spanning x -110 to -182, bridges near z=-119 and z=-177, and water runway near z=-141. Foundry mission sites x=106, z=-119 and x=148, z=-119 through -226. Provide broad drivable space and boss arenas. Rift realm around (0,0,1360), separate finite floor. Basic trial gate sequence in shared/course.json. All campaign code owns encounter instantiation and objectives. World does not start missions.
