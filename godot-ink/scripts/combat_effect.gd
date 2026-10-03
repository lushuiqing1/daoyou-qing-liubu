extends Node2D
## Short original vector ink strokes. No baked UI or actor-name textures.
var kind = "strike"
var origin = Vector2.ZERO
var target = Vector2.ZERO
var accent = Color("a64230")
var strong = false
var still = false
var progress = 0.0:
	set(value):
		progress = value
		queue_redraw()

func _draw():
	var fade = 1.0 if still else clampf((1.0-progress)*3.0,0.0,1.0)
	var ink = Color(accent,fade)
	var paper = Color("fff4d4"); paper.a = fade
	var radius = 32.0 if not strong else 43.0
	if kind == "strike" and not still:
		var travel = clampf(progress*2.8,0.0,1.0)
		var curve = PackedVector2Array()
		for i in range(24):
			var t = maxf(0.0,travel-0.48)+i/23.0*minf(0.48,travel)
			curve.append(origin.lerp(target,t)+Vector2(0,-sin(t*PI)*22))
		draw_polyline(curve,Color(accent,fade*0.25),13 if strong else 9,true)
		draw_polyline(curve,ink,5 if strong else 3.5,true)
		draw_polyline(curve,paper,1.2,true)
	if kind == "strike" and (progress > 0.26 or still):
		var bloom = 1.0 if still else clampf((progress-0.26)*3.2,0.0,1.0)
		for i in range(11):
			var angle = i*TAU/11+0.2
			var direction = Vector2.from_angle(angle)
			var length = radius*(0.6+(i%3)*0.22)*bloom
			draw_line(target+direction*9,target+direction*length,ink,2 if i%2 else 3,true)
		var slash = PackedVector2Array()
		for i in range(22):
			var t = i/21.0
			slash.append(target+Vector2(-radius+radius*2*t,radius*0.72-radius*1.44*t-sin(t*PI)*15))
		draw_polyline(slash,paper,8 if strong else 6,true)
		draw_polyline(slash,ink,3.5,true)
	elif kind in ["heal","shield","entry","defeat"]:
		var spread = 1.0 if still else 0.65+progress*0.65
		draw_arc(target,radius*spread,0,TAU,56,Color(accent,fade*0.65),2.5,true)
		draw_arc(target,radius*spread+7,-PI*0.8,PI*0.35,40,Color(accent,fade*0.3),1.5,true)
		for i in range(8):
			var at = target+Vector2.from_angle(i*TAU/8+0.3)*radius*spread
			draw_circle(at,2.3 if i%2 else 3.2,ink)
		if kind == "shield":
			var shield = PackedVector2Array([Vector2(-16,-20),Vector2(16,-20),Vector2(16,5),Vector2(0,21),Vector2(-16,5),Vector2(-16,-20)])
			for i in range(shield.size()): shield[i] += target
			draw_polyline(shield,paper,6,true); draw_polyline(shield,ink,3,true)
