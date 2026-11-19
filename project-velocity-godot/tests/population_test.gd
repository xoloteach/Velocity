extends SceneTree

const Population = preload("res://systems/population.gd")
const DT := 1.0/60.0

class Fixture extends Node3D:
	var runner := CharacterBody3D.new()
	var speed := 0.0
	var quality := 2
	var realm := "city"
	var notices: Array[Dictionary] = []
	var damage_received := 0.0

	func event(key: String,payload: Dictionary) -> void:
		notices.append({"key":key,"payload":payload})

	func damage(amount: float) -> void:
		damage_received += amount

var game: Fixture
var population: Node3D
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = Fixture.new()
	root.add_child(game)
	game.add_child(game.runner)
	population = Population.new()
	game.add_child(population)
	population.setup(game)
	for id in population._actors.keys():
		population.deactivate(id)
	await physics_frame

	_check_routes_and_signals()
	_check_pedestrian_reactions()
	_check_pursuit()
	_check_physics()
	_check_rewind()
	_check_dispatch()
	print("Population checks complete: %d failure(s)." % failures)
	quit(0 if failures==0 else 1)

func _advance(count: int) -> void:
	for _k in count:
		population.step(DT)

func _spawn(id: String,kind: String,pos: Vector3,options: Dictionary = {}) -> Dictionary:
	return population.spawn(id,kind,pos,options)

func _check(condition: bool,message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _has_notice(key: String,id: String) -> bool:
	for item in game.notices:
		if item.key==key and item.payload.id==id:
			return true
	return false

func _check_routes_and_signals() -> void:
	game.runner.global_position = Vector3(19,0,-109)
	population._clock = 7.6
	var sedan := _spawn("test.sedan","car",Vector3(3.7,0,-100),{
		"goal":Vector3(3.7,0,-245),"speed":10.0,
	})
	_advance(180)
	_check(sedan.pos.z>-110.6 and sedan.pos.z<-108.8,"Red signal should hold car before the Calder stop line.")
	_check(sedan.speed<0.4,"Car should be stationary by the red signal.")
	population._clock = 16.3
	var crossing := _spawn("test.crossing","civilian",Vector3(3.7,0,-108.0),{"held":true})
	# The pedestrian begins ahead of the queued vehicle in its driving lane.
	crossing.pos.z = -113.5
	_advance(160)
	_check(sedan.pos.z>-111.2,"A live pedestrian in the crosswalk should keep the vehicle stopped on green.")
	population.deactivate("test.crossing")
	_advance(190)
	_check(sedan.pos.z<-124.0,"The queued vehicle should continue once the crossing clears.")

	sedan.pos = Vector3(3.7,0,-206.0)
	sedan.speed = 0.0
	population._clock = 6.0
	game.runner.global_position.z = -211.0
	_advance(175)
	_check(sedan.pos.z>-218.0 and sedan.pos.z<-215.8,"The same car should stop at the second signal.")
	population._clock = 12.1
	_advance(195)
	_check(sedan.pos.z<-230.0,"The same car should cross the second intersection when released.")
	_check(population._nodes.has("test.sedan"),"An active visual/collider should exist near the runner.")
	_check(population._nodes["test.sedan"].body.collision_layer==8,"Nearby car should have a live actor collider.")
	population.deactivate("test.sedan")

func _check_pedestrian_reactions() -> void:
	game.runner.global_position = Vector3(11.3,0,-60)
	var walker := _spawn("test.walker","civilian",Vector3(11.5,0,-63),{"goal":Vector3(11.5,0,-85),"speed":1.3})
	game.speed = 31.0
	_advance(10)
	_check(walker.status=="flee","Pedestrian should flee a nearby high-speed runner.")
	_check(walker.health==100.0,"Near-miss must not damage a pedestrian.")
	var initial: Vector3 = walker.pos
	game.speed = 0.0
	population.area_effect(Vector3(11.3,0,-61.0),12.0,13.0,"shockwave")
	_advance(25)
	_check(walker.pos.distance_to(initial)>0.7 and walker.health==100.0,"Shockwave should provoke flight without hurting a civilian.")
	_advance(290)
	_check(walker.status in ["walk","arrived"],"Pedestrian should resume its route after danger clears.")
	population.deactivate("test.walker")

func _check_pursuit() -> void:
	game.runner.global_position = Vector3(14,0,-73)
	var culprit := _spawn("test.culprit","van",Vector3(3.7,0,-57),{
		"goal":Vector3(3.7,0,-94.0),"speed":5.4,"chase":true,
	})
	var officer := _spawn("test.officer","police",Vector3(3.7,0,-44.0),{"target":"test.culprit","speed":13.6})
	_advance(335)
	_check(officer.pos.z<-58.0 and officer.pos.distance_to(culprit.pos)<8.5,"Patrol car should pursue the moving culprit.")
	_check(_has_notice("population_police_contact","test.culprit"),"Police should emit contact for the real targeted vehicle.")
	_check(population._nodes.has("test.officer") and population._nodes["test.officer"].siren.playing,"Nearby active police pursuit should have a siren.")
	game.runner.global_position = culprit.pos
	_check(population.interact_id("test.culprit"),"Player should be able to intercept the actual pursuit target at low speed.")
	_check(culprit.status=="intercepted","Successful interception should stop the culprit vehicle.")
	population.deactivate("test.culprit")
	population.deactivate("test.officer")

func _check_physics() -> void:
	game.runner.global_position = Vector3(3.7,0,-24.0)
	var van := _spawn("test.van","van",Vector3(3.7,0,-32.0),{"goal":Vector3(3.7,0,-11.0),"speed":8.2})
	_advance(125)
	_check(game.damage_received>0.0 and _has_notice("population_collision","test.van"),"A vehicle impact should produce an actual collision response.")
	var stunned: int = population.area_effect(Vector3(3.7,0,-20.0),10.0,13.0,"shockwave")
	_check(stunned==1 and van.status=="stagger","A clear close Shockwave should stop the vehicle.")
	_check(_has_notice("population_staggered","test.van"),"Vehicle stagger should publish the actual actor identifier.")
	var stopped_z: float = van.pos.z
	_advance(38)
	_check(is_equal_approx(van.pos.z,stopped_z),"Vehicle must hold its position during stagger.")
	population.deactivate("test.van")

func _check_rewind() -> void:
	game.runner.global_position = Vector3(1,0,-53)
	var van := _spawn("test.rewind.van","van",Vector3(3.7,0,-52.0),{"goal":Vector3(3.7,0,-76.0),"speed":6.0})
	var civilian := _spawn("test.rewind.civilian","civilian",Vector3(11.5,0,-54.0),{"held":true})
	var barrel := _spawn("test.rewind.prop","prop",Vector3(9.3,0,-53.0))
	_advance(10)
	var saved: Dictionary = population.snapshot()
	var original_van: Vector3 = van.pos
	var original_prop: Vector3 = barrel.pos
	var original_civilian: Vector3 = civilian.pos
	population.injure("test.rewind.civilian")
	population.area_effect(Vector3(8.0,0,-53.0),4.0,13.0,"shockwave")
	_advance(40)
	_check(barrel.pos.distance_to(original_prop)>1.0 and van.pos.distance_to(original_van)>1.0 and civilian.health==0.0,
		"Car movement, injury and prop impulse should independently change the staged state.")
	population.deactivate("test.rewind.civilian")
	_spawn("test.rewind.future","prop",Vector3(5.0,0,-53.0))
	population.restore(saved)
	var restored_van: Dictionary = population.query("test.rewind.van")
	var restored_civilian: Dictionary = population.query("test.rewind.civilian")
	var restored_prop: Dictionary = population.query("test.rewind.prop")
	_check(restored_van.get("pos",Vector3.ZERO).distance_to(original_van)<0.001,"Rewind must restore car position within 1 mm.")
	_check(restored_prop.get("pos",Vector3.ZERO).distance_to(original_prop)<0.001,"Rewind must restore prop position within 1 mm.")
	_check(restored_civilian.get("pos",Vector3.ZERO).distance_to(original_civilian)<0.001 and restored_civilian.get("health",0.0)==100.0,
		"Rewind must restore a removed civilian to the healthy historical state.")
	_check(population.query("test.rewind.future").is_empty(),"Rewind must remove actors from the future timeline.")
	var historical_z: float = restored_van.pos.z
	_advance(20)
	_check(float(restored_van.pos.z)<historical_z-0.2,"The restored car should continue moving after rewind.")
	for id in ["test.rewind.van","test.rewind.civilian","test.rewind.prop"]:
		population.deactivate(id)

func _check_dispatch() -> void:
	game.runner.global_position = Vector3(9,0,-63)
	population.set_patrol(true)
	population._crime_cooldown = 0.0
	var before_dispatch: Dictionary = population.snapshot()
	_advance(1)
	var first_id: String = population.crime.id
	var target_id: String = population.crime.primary_id
	var robber: Dictionary = population.query(target_id)
	_check(population.crime.kind=="pursuit" and not robber.is_empty(),"Dispatch should enact the pursuit with a real fleeing actor.")
	game.runner.global_position = robber.pos
	_check(population.interact_id(target_id),"Dispatch should complete when the actual fleeing target is intercepted.")
	_check(_has_notice("crime_completed",first_id),"Dispatch completion must expose a stable reward key.")
	population.restore(before_dispatch)
	game.runner.global_position = Vector3(9,0,-63)
	_advance(1)
	_check(population.crime.id==first_id,"Repeating a rewound crime must preserve its identifier for reward deduplication.")
	population.set_patrol(false)
	population.set_patrol(true)
	population._crime_cooldown = 0.0
	_advance(1)
	var rescue_id: String = population.crime.primary_id
	var rescue: Dictionary = population.query(rescue_id)
	_check(population.crime.kind=="rescue" and rescue.get("status")=="injured","Dispatch should rotate into an actual injury rescue.")
	game.runner.global_position = rescue.pos
	var safe: Vector3 = rescue.pos+Vector3(0,0,4.0)
	_check(population.begin_escort(rescue_id,safe),"Injured civilian should support a staged escort.")
	game.runner.global_position = safe
	_advance(210)
	_check(rescue.pos.distance_to(safe)<0.65 and rescue.status=="escort","Escorted civilian should physically reach the handoff point.")
	_check(population.interact_id(rescue_id) and rescue.status=="rescued","A staged escort should allow a final handoff.")
	population.set_patrol(false)
	population.set_patrol(true)
	population._crime_cooldown = 0.0
	_advance(1)
	_check(population.crime.kind=="escape","The next dispatch should enact a suspect on foot.")
	var failure_id: String = population.crime.id
	var escape_id: String = population.crime.primary_id
	population.crime.time = 0.01
	_advance(2)
	_check(population.crime.outcome=="failed" and _has_notice("crime_failed",failure_id),"A missed dispatch should expire with an explicit fail result.")
	_check(not _has_notice("crime_completed",failure_id),"Expired dispatch must have no reward event.")
	_advance(245)
	_check(population.crime.is_empty() and population.query(escape_id).is_empty(),"Expired incident must release its actors after cleanup.")
