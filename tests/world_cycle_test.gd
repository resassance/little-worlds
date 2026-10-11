extends SceneTree
var checks:=0
var failures:=0
func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition: failures+=1; push_error("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var w:=WorldState.new(); w.generate(1024); w.populate_demo()
	var distant:=Vector2i(8000,-5000)
	w.paint(distant,24,WorldState.Terrain.GRASS)
	w.paint(distant+Vector2i(8,0),6,WorldState.Terrain.FOREST)
	w.paint(distant+Vector2i(-8,-7),2,WorldState.Terrain.MOUNTAIN)
	WorldClimate.paint(w,distant,24,2)
	for i in 6: w.add_person(distant+Vector2i(i%3,i/3),false)
	check(w.towns.is_empty() and w.metrics.discoveries==0,"two groups start without settlements or free technologies")
	var contact_tick: int=-1
	var developed:=0
	var both_lived:=true
	for i in WorldLife.YEAR*80:
		w.step()
		for home in w.towns:
			var directions:=WorldDevelopment.profile(w,home)
			var count:=0
			for direction in directions:
				if directions[direction].operating>0: count+=1
			developed=maxi(developed,count)
		if w.ticks%WorldLife.YEAR==0:
			if w.people.is_empty(): both_lived=false
			check(WorldAudit.conserved(w),"year %d: food, wood and six material balances close" % w.year())
		if contact_tick==-1:
			for value in w.contacts:
				var a:=WorldEconomy.town(w,value.a); var b:=WorldEconomy.town(w,value.b)
				if not a.is_empty() and not b.is_empty() and Vector2i(a.x,a.y).distance_to(Vector2i(b.x,b.y))>1000: contact_tick=w.ticks; break
		if contact_tick!=-1 and developed>=4: break
	check(contact_tick>0,"autonomous societies meet across the ocean after building and researching")
	check(developed>=4,"real local production operates in four independent directions")
	check(both_lived and w.metrics.births>0 and w.metrics.lessons>0,"generations and teaching coexist with shipping and industry")
	var path: String="user://world-cycle.json"
	check(SaveStore.save_world(w,path)==OK,"full two-continent cycle saves")
	var loaded:=SaveStore.load_world(path)
	check(loaded!=null,"full cycle loads with contacts and regional data")
	for i in WorldLife.YEAR:
		w.step()
		if loaded!=null: loaded.step()
	check(loaded!=null and JSON.stringify(w.to_dict())==JSON.stringify(loaded.to_dict()),"different climates and advanced societies continue identically for a saved year")
	check(WorldAudit.conserved(w),"saved cycle continues with all ledgers closed")
	print("World cycle: %d checks, %d failures; contact at year %.1f, directions %d, %d people, %d births, %d discoveries." % [checks,failures,float(contact_tick)/WorldLife.YEAR,developed,w.people.size(),w.metrics.births,w.metrics.discoveries])
	quit(1 if failures else 0)
