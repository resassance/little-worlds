extends SceneTree

func fixture() -> WorldState:
	return WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/population-2000-world.json")))

func measure(world: WorldState, count: int) -> Dictionary:
	var slices: Array[int] = []
	var elapsed := 0
	var peak := 0
	for i in count:
		var before := Time.get_ticks_usec()
		var job := WorldStepJob.new(world)
		while not job.finished:
			var started := Time.get_ticks_usec(); job.advance(2000); slices.append(Time.get_ticks_usec()-started)
		elapsed += Time.get_ticks_usec()-before; peak = maxi(peak,job.max_unit_usec)
	slices.sort()
	return {"mean_step_ms":elapsed/float(count)/1000,"slice_p95_ms":slices[floori(slices.size()*0.95)]/1000.0,"slice_max_ms":slices.back()/1000.0,"unit_max_ms":peak/1000.0,"cold_reads":world.regions.cold_reads}

func _initialize() -> void:
	var baseline := fixture()
	var historical := fixture()
	if baseline == null or historical == null: quit(1); return
	for i in WorldHeritage.LIMIT:
		var cell := Vector2i(100000+i*32,0)
		var home := {"id":historical.next_id,"name":"Прошлое %d" % i,"x":cell.x,"y":cell.y,"food":0,"wood":0,"level":1}
		historical.next_id += 1
		historical.heritage.origin(historical,home,0)
		historical.heritage.add_remain(historical.heritage.origin_index[home.id].remains,{"x":cell.x,"y":cell.y,"kind":"house"})
		historical.heritage.abandon(historical,home,"Поселение опустело")
		historical.heritage.forget_origin(home)
	for i in 3: baseline.step(); historical.step()
	var first := measure(baseline,20)
	var second := measure(historical,40)
	var last := measure(baseline,20)
	historical.ticks = (historical.ticks/WorldLife.YEAR+1)*WorldLife.YEAR
	var before := Time.get_ticks_usec()
	var job := WorldHeritageJob.new(historical)
	var units := 0
	var largest := 0
	while not job.finished:
		var started := Time.get_ticks_usec(); job.unit(); units += 1
		largest = maxi(largest,Time.get_ticks_usec()-started)
	var heritage_usec := Time.get_ticks_usec()-before
	var result := {"baseline_first":first,"with_256_sites":second,"baseline_last":last,"heritage_job_usec":heritage_usec,"heritage_units":units,"heritage_unit_max_usec":largest,"sites":historical.heritage.sites.size(),"people":historical.people.size(),"conserved":WorldAudit.conserved(historical)}
	var file := FileAccess.open("res://artifacts/heritage-performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")); file.close()
	print(JSON.stringify(result))
	quit(0 if result.conserved and result.sites == WorldHeritage.LIMIT else 1)
