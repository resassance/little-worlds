extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := WorldState.new(); world.generate(42817); world.populate_demo()
	world.weather.rate = 0
	for i in 100: world.step()
	var home: Dictionary = world.towns[0]
	var member: Dictionary = world.people[0]
	member.vocation.skill = "wood"; member.vocation.goal = "connect"
	member.vocation.target = 3; member.vocation.progress = 0
	member.vocation.review = world.ticks + 60
	member.social_need = 40; member.hunger = 0; member.energy = 100
	member.cargo = 0; member.rations = 2; home.food = 500
	var original_food: int = home.food
	check(WorldVocation.assign_goal(world, member, home) and member.task.kind == "visit", "social goal schedules a real visit when food and energy are sufficient")
	check(home.food == original_food, "a personal goal does not create or spend fictional food")
	member.task = {}
	check(not WorldVocation.assign_goal(world, member, home), "personal opportunities are attempted at most once per month")
	member.vocation.attempt = -1; member.hunger = 40
	check(not WorldVocation.assign_goal(world, member, home), "hunger takes priority over personal aspirations")
	member.hunger = 0; home.food = 0
	check(not WorldVocation.assign_goal(world, member, home), "community food shortage prevents optional social tasks")
	WorldVocation.milestone(member, "connect")
	check(WorldVocation.progress(member) == 1, "actual social completion advances the matching goal")
	WorldVocation.milestone(member, "explore")
	check(WorldVocation.progress(member) == 1, "unrelated actions cannot complete a goal")
	member.vocation.goal = "master"; member.vocation.goal_skill = "wood"
	member.vocation.baseline = member.skills.wood; member.vocation.target = 40
	member.skills.wood += 10
	check(WorldVocation.progress(member) == 10, "craft goals require real personal experience")
	var skill: String = member.vocation.skill
	WorldVocation.review(world, member, home)
	check(member.vocation.skill == skill, "profession preference is not rerolled on every task")
	var choices := {}
	for person in world.people: choices[person.vocation.goal] = true
	check(choices.size() >= 2, "residents start with distinct personal aspirations")
	var saved := world.to_dict()
	var second := saved.duplicate(true)
	for person in second.people: person.erase("vocation")
	var restored := WorldState.new(); restored.world_seed = world.world_seed; restored.ticks = world.ticks
	var copy: Dictionary = member.duplicate(true)
	check(WorldVocation.restore(restored, copy) and copy.vocation == member.vocation, "goals and profession preferences retain their state after restoration")
	copy = member.duplicate(true); copy.erase("vocation")
	check(WorldVocation.restore(restored, copy) and copy.has("vocation"), "legacy residents gain valid goals without losing personal skills")
	copy = member.duplicate(true); copy.vocation.goal = "invalid"
	check(not WorldVocation.restore(restored, copy), "loading rejects unknown goal kinds")
	var other: Dictionary = member.duplicate(true)
	other.vocation.skill = "food"; other.vocation.goal = "master"
	check(WorldWorkforce.score(member, "wood") > WorldWorkforce.score(other, "wood"), "profession preference affects existing worker assignment")
	other.skills.wood += 40
	check(WorldWorkforce.score(other, "wood") > WorldWorkforce.score(member, "wood"), "actual expertise outweighs a novice preference")
	var clean := WorldState.new(); clean.generate(71); clean.populate_demo(); clean.weather.rate = 0
	for i in 50: clean.step()
	var record := clean.to_dict()
	var roundtrip := WorldState.from_dict(JSON.parse_string(JSON.stringify(record)))
	check(roundtrip != null and JSON.stringify(roundtrip.to_dict()) == JSON.stringify(record), "real simulation saves preserve every resident goal exactly")
	for person in record.people: person.erase("vocation")
	var legacy := WorldState.from_dict(record)
	check(legacy != null, "existing saves load without vocation fields")
	print("Vocation: %d failures" % failures)
	quit(1 if failures else 0)
