extends SceneTree
func _initialize() -> void:
 var w:=WorldState.new(); w.generate(42817)
 var land: Array[Vector2i]=[]
 for y in w.height:
  for x in w.width:
   if w.walkable(Vector2i(x,y)): land.append(Vector2i(x,y))
 for i in 400: w.add_person(land[(i*13)%land.size()],false)
 for i in 100: w.step()
 w.profiling=true
 var start:=Time.get_ticks_usec()
 for i in 200: w.step()
 print("PROFILE ",w.timings," total_ms ",(Time.get_ticks_usec()-start)/1000," people ",w.people.size()," towns ",w.towns.size())
 quit()
