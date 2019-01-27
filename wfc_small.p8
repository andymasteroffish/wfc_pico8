pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

dir_n = 1
dir_e = 2
dir_s = 3
dir_w = 4

--individual tiles being used
source_tiles = {}

--the map of source tiles
source = {}
source_c = 12
source_r = 9

unique_ids = {}

--output grid
output = {}
output_snap = {}
buffer_dist = 2
output_c = 16+buffer_dist*2
output_r = 16+buffer_dist*2

tile_state_inactive = 1
tile_state_active = 2
tile_state_set = 3

flag_deadly = 0
flag_solid = 1
flag_ladder = 2
flag_collectable = 3
flag_liquid = 4

is_done = false
need_first_move = true
auto_advance = true

--history
root_move = nil 
cur_move = nil

revert_target_depth = 0
doing_revert = false


--testing
tester_x = 12
tester_y = 12
tester_control = true

--camera
cam_x = 0
cam_y = 0

--player
pl = nil
actors = {} --all actors in world

player_start_x = 12
player_start_y = 12

wraith = nil

--https://www.lexaloffle.com/bbs/?tid=2119
function make_actor(x,y)
	local a={}
	a.x = x-0.5
	a.y = y-0.5
	a.dx = 0
	a.dy = 0
	a.tx = 1
	a.ty = 1
	a.dir = 1
	a.grav = 0.03
	a.bounce_mult_x = 0 	--by default, just stop when they bounce
	a.bounce_mult_y = 0
	a.spr = 5
	a.frame = 0
	a.t = 0
	a.fric = 1
	a.killed_by_tiles = true

	a.kills_player = false
	a.grounded = false

	a.w = 0.3
	a.h = 0.3

	a.type = "unkown"
	a.die_off_screen = true
	a.die_in_solid = true

	add(actors,a)
	return a
end

function make_player(x,y)
	local a = make_actor(x,y)
	a.type = "player"
	a.jump = -0.35
	a.speed = 0.15
	a.spr = 64
	a.die_off_screen = false
	a.die_in_solid = false
	a.on_ladder = false;
	return a
end

function make_scorpion(x,y)
	local a = make_actor(x,y)
	a.type = "scorp"
	a.speed = 0.05
	a.spr = 80

	a.bounce_count = 0
	a.kills_player = true
	
	return a
end

function make_cutter(x,y)
	local a = make_actor(x,y)
	a.type = "cut"
	a.speed = 0.002
	a.spr = 96
	a.w = 0.1
	a.h = 0.1
	a.bounce_count = 0
	a.grav = 0
	a.bounce_mult_x = -1.2
	a.bounce_mult_y = a.bounce_mult_x
	a.fric = 0.98
	a.kills_player = true
	return a
end

function make_bomb(x,y, dir)
	local a = make_actor(x,y)
	a.type = "bomb"
	a.bounce_mult_x = -0.2
	a.bounce_mult_y = -0.8
	a.fric = 0.99
	a.spr = 101
	a.w = 0.2
	a.h = 0.2
	a.kill_time = 60
	a.killed_by_tiles = false

	a.dx = 0.2 * dir
	a.dy = -0.2

	return a
end




function make_wraith(x,y)
	local a = {}
	a.x = x-0.5
	a.y = y-0.5
	a.dx = 0
	a.dy = 0
	a.fric = 0.99

	a.tilex = -1
	a.tiley = -1
	a.p_tilex = -1
	a.p_tiley = -1

	a.move = function()
		local spd = 0.0005
		if pl.x < a.x then
			a.dx -= spd
		else
			a.dx += spd
		end
		if pl.y < a.y then
			a.dy -= spd
		else
			a.dy += spd
		end

		a.x += a.dx
		a.y += a.dy

		a.dx *= a.fric
		a.dy *= a.fric
	end

	a.draw = function()
		local sx = out_x + (a.x * 8)-4
		local sy = out_y + (a.y * 8)-4
		local flip_x = a.dx < -0.08
		spr(112, sx, sy, 1, 1, flip_x, false)
		pset(out_x+a.x*8, out_y+a.y*8, 11)
	end

	return a
end

--init
function _init()
	palt(0,true)
	--palt(5,true)

	printh("")
	printh("starting...")
	
	--setup the source map based on the sprite map
	--also go through and add unique tiles to the list of source tiles
	for x=1, source_c do
		add(source, {})
		for y=1, source_r do
			local tile_id = mget(x-1,y-1)	--sprite map is 0 indexed
			add(source[x], tile_id)	
			--printh("x:"..tostr(x).." y:"..tostr(y).."  "..tostr(source[x][y]))

			--check if this is a new tile and needs to be added to source tiles
			local is_new = true
			for s=1, #source_tiles do
				if source_tiles[s].id == tile_id then
					is_new = false
				end
			end

			if is_new then
				printh("add source tile for "..tostr(tile_id))
				add(source_tiles, make_source_tile(tile_id))
				add(unique_ids, tile_id)
			end
		end
	end

	--setup the output tiles
	printh("unique ids: "..tostr(#unique_ids))
	for x=1, output_c do
		add(output, {})
		add(output_snap, {})
		for y=1, output_r do
			add(output[x], make_output_tile(x,y,unique_ids))
			add(output_snap[x], make_output_tile(x,y,unique_ids))
		end
	end

	set_neighbor_info()

	root_move = make_check_point(nil)
	cur_move = make_check_point(nil)	

end

function start_game()
	pl = make_player(player_start_x, player_start_y)
	--wraith = make_wraith(1,1)
end


--update
function _update()
	if auto_advance then
		for i=1, 4 do
			advance()
		end
	end

	if false then
		if (btnp(4)) then
			advance()
		end
		

		--a
		if (btnp(5,1)) then
			auto_advance = not auto_advance
			printh("auto "..tostr(auto_advance))
		end

	end

	--keeping the tester in range
	tester_x = min( max(tester_x, buffer_dist+1), output_c-buffer_dist)
	tester_y = min( max(tester_y, buffer_dist+1), output_r-buffer_dist)

	--scrolling the camera
	if (pl != nil) then
		local scroll_dist = 50
		local scroll_speed = 1.7
		local tester_screen_x = (pl.x-buffer_dist)*8 - cam_x
		local tester_screen_y = (pl.y-buffer_dist)*8 - cam_y

		--printh("tester screen: "..tester_screen_x)
		if (tester_screen_x > 128-scroll_dist)  then
			cam_x += scroll_speed
		end
		if (tester_screen_x < scroll_dist)  then
			cam_x -= scroll_speed
		end
		if (tester_screen_y > 128-scroll_dist)  then
			cam_y += scroll_speed
		end
		if (tester_screen_y < scroll_dist)  then
			cam_y -= scroll_speed
		end
	end

	--do we need to scroll the grid?
	if (is_done and pl != nil) then
		if (pl.x <= buffer_dist*3) then
			printh(" natural scroll right")
			scroll_right(buffer_dist)
		elseif (pl.x >= output_c-buffer_dist*3) then
			printh(" natural scroll left")
			scroll_left(buffer_dist)
		elseif (pl.y <= buffer_dist*3) then
			printh(" natural scroll down")
			scroll_down(buffer_dist)
		elseif (pl.y >= output_r-buffer_dist*3) then
			printh(" natural scroll up")
			scroll_up(buffer_dist)
		end
	end

	check_input()

	foreach(actors, move_actor)

	--did the player touch anything?
	if (pl != nil) then
		for a in all(actors) do
			if a.type != "player" then
				if dist(a.x,a.y, pl.x,pl.y) < pl.w + a.w and a.kills_player then
					kill_actor(pl)
					break
				end
			end
		end

		if (output[pl.tx][pl.ty].has_flag(flag_collectable)) then
			local sp_id = output[pl.tx][pl.ty].set_id
			output[pl.tx][pl.ty].set_id = 0
			if sp_id == 7 then 	--coin
				printh("ding")
			end
		end
	end

	--wraith!
	if (wraith != nil and btn(4,0) == false) then
		wraith.move()

		--fuck up some tiles
		wraith.tilex = flr(wraith.x)+1
		wraith.tiley = flr(wraith.y)+1

		if (wraith.tilex != wraith.p_tilex or wraith.tiley != wraith.p_tiley) then
			local wx = wraith.tilex
			local wy = wraith.tiley
			if (wx >= 1 and wx <= output_c and wy >= 1 and wy <= output_r) then
				if (output[wx][wy].state == tile_state_set) then
					blow_up_rect(wx,wy,wx,wy)
				end
			end
		end

		wraith.p_tilex = wraith.tilex
		wraith.p_tiley = wraith.tiley
	end

	--update the tiles
	for x=1, output_c do
		for y=1, output_r do
			output[x][y].t += 1
		end
	end
end

function dist(x1, y1, x2, y2)
  return sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function check_input()

	--tester
	if btnp(0,1) then tester_x -= 1 end
	if btnp(1,1) then tester_x += 1 end
	if btnp(2,1) then tester_y -= 1 end
	if btnp(3,1) then tester_y += 1 end

	if (btnp(4,1)) then
		blow_up_rect(tester_x-2, tester_y-2, tester_x+2, tester_y+2)
	end

	--player
	if (pl != nil) then



		if btnp(2,0) and pl.grounded then 
			pl.dy = pl.jump
		end

		local touching_ladder = false
		if output[pl.tx][pl.ty].has_flag(flag_ladder) then
			touching_ladder = true
		end

		--climbing up a bit further
		if touching_ladder == false and pl.ty < output_r then
			if output[pl.tx][pl.ty+1].has_flag(flag_ladder) and pl.y-flr(pl.y) > 0.75 then
				touching_ladder = true
			end
		end

		if btn(2,0) and touching_ladder then
			pl.dy = -pl.speed
			pl.x = pl.tx-0.5
			pl.on_ladder = true
		end
		if btn(3,0) and touching_ladder then
			pl.dy = pl.speed
			pl.x = pl.tx-0.5
			pl.on_ladder = true
		end

		--horizontal movement
		if btn(0,0) then 
			pl.dx = -pl.speed
			pl.dir = -1
			pl.on_ladder = false
		elseif btn(1,0) then 
			pl.dx = pl.speed
			pl.dir = 1
			pl.on_ladder = false
		else 
			pl.dx = 0
		end

		--horizontal attack
		if btnp(4,0) then
			local px = flr(pl.x) + 1
			local py = flr(pl.y) + 1
			if pl.dir > 0 then
				blow_up_rect(px+2,py-1, px+3,py+1)
				blow_up_rect(px+1,py, output_c,py)
			else
				px +=1 --this was too far to the right
				blow_up_rect(px-3,py-1, px-2,py+1)
				blow_up_rect(1,py, px-4,py)
			end
		end

		--bomb
		if btnp(5.0) then
			make_bomb(pl.tx, pl.ty, pl.dir)
		end

	end

	--e spawn the player -- not used
	if btnp(2,1) and false then
		if (tester_control and pl == nil) then
			pl = make_actor(tester_x-0.5, tester_y-0.5)
		end
		tester_control = not tester_control
	end
end

function blow_up_rect(x1,y1, x2,y2)
	printh("heyo")
	blow_up_rect_circ(x1,y1, x2,y2, 99)
end

function blow_up_rect_circ(x1,y1, x2,y2, range)
	printh("blow up "..tostr(x1)..","..tostr(y1).." to "..tostr(x2)..","..tostr(y2))
	local start_x = max(1, x1)
	local end_x = min(output_c, x2)
	local start_y = max(1, y1)
	local end_y = min(output_r, y2)

	local cent_x = (x1+x2)/2
	local cent_y = (y1+y2)/2

	printh("range "..tostr(range))

	--knock em out
	for x=start_x, end_x do
		for y=start_y, end_y do
			if dist(x,y, cent_x,cent_y) < range then
				output[x][y].reset(unique_ids)
			end
		end
	end

	--rule out based on neighbors
	for x=start_x, end_x do
		for y=start_y, end_y do
			if (output[x][y].state == tile_state_inactive) then
				--north
				if y > 1 then
					if output[x][y-1].state == tile_state_set then
						local s_tile = get_source_tile_from_id(output[x][y-1].set_id)
						output[x][y].rule_out_based_on_neighbor(s_tile, dir_s)
					end
				end
				--east
				if x < source_c then
					if output[x+1][y].state == tile_state_set then
						local s_tile = get_source_tile_from_id(output[x+1][y].set_id)
						output[x][y].rule_out_based_on_neighbor(s_tile, dir_w)
					end
				end
				--south
				if y > 1 then
					if output[x][y+1].state == tile_state_set then
						local s_tile = get_source_tile_from_id(output[x][y+1].set_id)
						output[x][y].rule_out_based_on_neighbor(s_tile, dir_n)
					end
				end
				--west
				if x > 1 then
					if output[x-1][y].state == tile_state_set then
						local s_tile = get_source_tile_from_id(output[x-1][y].set_id)
						output[x][y].rule_out_based_on_neighbor(s_tile, dir_e)
					end
				end
			end
		end
	end

	take_snapshot()
	is_done = false
end


--draw
function _draw()
	camera(0,0)
	local bg_col = 0
	--if (doing_revert)	bg_col = 12
	rectfill(0,0,128, 128, bg_col)
	--map(0,0, 0,0, 12, 9)

	camera(cam_x, cam_y)

	--draw output
	out_x = -buffer_dist*8
	out_y = -buffer_dist*8
	for x=1, output_c do
		for y=1, output_r do
			local sprite = get_rand_sprite(output[x][y]) -- 1 --grey checker
			if output[x][y].state == tile_state_active then
				sprite = get_rand_sprite(output[x][y]) -- 2 --color checker
			end
			if output[x][y].state == tile_state_set then
				sprite = output[x][y].set_id
			end
			if (wraith != nil and false) then
				if x == wraith.tilex and y == wraith.tiley then
					sprite = 32 --wraith tile
				end
			end

			--recently cleared tiles should always blink for a bit
			if output[x][y].t < 10 then
				sprite = get_rand_sprite(output[x][y])	
				if output[x][y].t % 4 < 3 then
					
				else
					sprite = 2
				end
			end

			spr(sprite, out_x+(x-1)*8, out_y+(y-1)*8)

			--num choices
			if false and output[x][y].state == tile_state_active then
				print(tostr(#output[x][y].potential_ids), out_x+(x-1)*8+1, out_y+(y-1)*8+1, 7)
			end
		end
	end
	
	--actors
	foreach(actors, draw_actor)	--runs through array, calling function on each
	if (wraith != nil) then wraith.draw() end

	--draw source
	if (false) then
		local src_x = 1
		local src_y = 1
		rectfill(src_x-1, src_y-1, src_x+source_c*8+1, src_y+source_r*8+1, 12)
		for x=1, source_c do
			for y=1, source_r do
				spr(source[x][y], src_x+(x-1)*8, src_y+(y-1)*8)
			end
		end
	end

	if false then
		--draw tester
		if (pl != nil) then
			tester_x = pl.tx
			tester_y = pl.ty
		end

		tester_draw_x = out_x+(tester_x-1)*8
		tester_draw_y = out_y+(tester_y-1)*8
		rect(tester_draw_x, tester_draw_y, tester_draw_x+8, tester_draw_y+8, 7 )


		camera(0,0)

		local debug_text = tostr(tester_x)..","..tostr(tester_y)
		debug_text = debug_text.."\n"..tostr(output[tester_x][tester_y].has_flag(flag_solid))
		debug_text = debug_text.."\n".."state: "..tostr(output[tester_x][tester_y].state)
		debug_text = debug_text.."\n".."setid: "..tostr(output[tester_x][tester_y].set_id)
		debug_text = debug_text.."\n".."depth: "..tostr(cur_move.get_depth())
		if (wraith != nil) then
			debug_text = debug_text.."\n".."wraith x: "..tostr(wraith.x)
			debug_text = debug_text.."\n".."wraith y: "..tostr(wraith.y)
		end
		if (pl != nil) then
			debug_text = debug_text.."\n".."pl x: "..tostr(pl.x)
			debug_text = debug_text.."\n".."pl y: "..tostr(pl.y)
		end

		local first_move_text = "nil"
		if (root_move.next != nil) then
			local move = root_move.next.this_move
			first_move_text = "x:"..tostr(move.col).." y:"..tostr(move.row).."  id:"..tostr(move.id)
		end
		debug_text = debug_text.."\n"..first_move_text

		if btn(5) or tester_control then
			print(debug_text, 2, 9, 7)
		end
	end
end

function get_rand_sprite(t)
	if (t.t % 4 < 3) then
		return flr((t.rnd + t.t/3) % 10) + 2
	end
	return 2 -- red checker
end

--https://www.lexaloffle.com/bbs/?tid=2119
function move_actor(a)
	--liquid slows ya down
	if output[a.tx][a.ty].has_flag(flag_liquid) then
		local w_fric = 0.6
		a.dx *= w_fric
		a.dy *= w_fric
	end

	--moving along x (if clear)
	if not solid_area(a.x+a.dx, a.y, a.w, a.h) then
		a.x += a.dx
		if (a.type == "scorp" or a.type == "cut") then
			a.bounce_count = 0
		end
	else
		a.dx *= a.bounce_mult_x
		if (a.type == "scorp" or a.type == "cut") then
			a.dir *= -1
			a.bounce_count += 1
			if (a.bounce_count > 15) then
				kill_actor(a)
				return
			end
		end
		
	end

	--now y
	if not solid_area(a.x, a.y+a.dy, a.w, a.h) then
		a.y += a.dy
	else
		a.dy *= a.bounce_mult_y
	end

	--constrain speeds
	a.dx = min(1, max(-1, a.dx))
	a.dy = min(1, max(-1, a.dy))

	a.dx *= a.fric
	a.dy *= a.fric

	a.grounded = solid_area(a.x, a.y+0.1, a.w, a.h) or output[a.tx][a.ty].has_flag(flag_liquid)

	--movement
	a.dy += a.grav

	--undo grav when on ladder
	if a == pl then if a.on_ladder then a.dy = 0 end end

	a.t += 1

	--set tile pos
	a.tx = flr(a.x)+1
	a.ty = flr(a.y)+1

	--specific actor things
	if (a.type == "scorp") then
		a.dx = a.speed * a.dir
	end

	if (a.type == "cut") then
		local ang = atan2(pl.x-a.x, pl.y-a.y)
		a.dx += cos(ang) * a.speed
		a.dy += sin(ang) * a.speed
	end

	if (a.type == "bomb") then
		a.frame = 0
		if a.t > a.kill_time - 30 then
			a.frame = a.t/2%2
		end

		if a.t > a.kill_time then
			--local r=2
			blow_up_rect_circ(a.tx-5,a.ty-5, a.tx+5, a.ty+5, 2.5)
			kill_actor(a)
			return
		end
	end

	--if you're off grid, you're a dead mother fucker
	if a.x < 1 or a.x > output_c or a.y < 1 or a.y > output_c then
		if a.die_off_screen then
			kill_actor(a)
			return
		end
	end

	--if you're on a deadly tile... you die
	if output[a.tx][a.ty].has_flag(flag_deadly) and a.killed_by_tiles then
		kill_actor(a)
		return
	end
end

function kill_actor(a)
	printh("kill "..tostr(a.type))
	del(actors, a)
	if a == pl then
		pl = nil
	end
	printh(" actors left:"..tostr(#actors))
end

function solid_area(x,y,w,h)
	local left_x = flr(x-w+1)
	local right_x = flr(x+w+1)
	local top_y = flr(y-h+1)
	local bot_y = flr(y+h+1)

	--printh("lef_x:"..tostr(left_x).." rig_x:"..tostr(right_x).." top_y:"..tostr(top_y).." bot_y:"..tostr(bot_y) )

	if left_x < 1 or top_y < 1 or right_x >output_c or bot_y > output_r then
		return true
	end

	return
		output[left_x][top_y].has_flag(flag_solid) or
		output[right_x][top_y].has_flag(flag_solid) or
		output[left_x][bot_y].has_flag(flag_solid) or
		output[right_x][bot_y].has_flag(flag_solid)
end

--https://www.lexaloffle.com/bbs/?tid=2119
function draw_actor(a)
	local sx = out_x + (a.x * 8)-4
	local sy = out_y + (a.y * 8)-5
	local flip_x = a.dir < 0

	local spr_id = a.spr + a.frame

	--player
	if (a == pl) then
		--standing is default
		if pl.on_ladder	then
			spr_id = 67
			if flr(pl.y*2.0) % 2 == 0 then
				spr_id += 1
			end
			flip_x = false
		elseif pl.grounded == false then 
			spr_id = 65 
		elseif abs(pl.dx) > 0.1 then
			spr_id = 65
			if flr(pl.t/4) % 2 == 0 then spr_id += 1 end
		end
	end

	spr(spr_id, sx, sy, 1, 1, flip_x, false)
end



-- ************
-- wfc functions
-- ************


--resets the output image
function reset_output()
	printh("reset output")
	for x=1, output_c do
		for y=1, output_r do
			output[x][y].copy_from(output_snap[x][y])
		end
	end

	is_done = false
end

--saves the current board state and treats it as root
function take_snapshot()
	printh("take snapshot")
	--save current tile states
	for x=1, output_c do
		for y=1, output_r do
			output_snap[x][y].copy_from(output[x][y])
		end
	end

	--get rid of the old history
	--this makes the root move and empty one, but that's ok. it'll look for a good spot to use after it rejects the empty move
	root_move.prune()
	cur_move.copy_from(root_move)
	root_move.next = cur_move
	cur_move.prev = root_move
end

--scrolling the grid
function scroll_left(num_times)
	printh("scroll left")
	for x=1, output_c do
		for y=1, output_r do
			if x < output_c then
				output[x][y].copy_from(output[x+1][y])
			else
				output[x][y].reset(unique_ids)
				if (output[x-1][y].state == tile_state_set) then
					local s_tile = get_source_tile_from_id(output[x-1][y].set_id)
					output[x][y].rule_out_based_on_neighbor(s_tile, dir_e)
				end

			end
		end
	end

	move_actors_from_scroll(-1,0)

	if (num_times <= 1) then scroll_cleanup()
	else 				scroll_left(num_times-1)	end
end

function scroll_right(num_times)
	printh("scroll right")
	for x=output_c, 1, -1 do
		for y=1, output_r do
			if x > 1 then
				output[x][y].copy_from(output[x-1][y])
			else
				output[x][y].reset(unique_ids)
				if (output[x+1][y].state == tile_state_set) then
					local s_tile = get_source_tile_from_id(output[x+1][y].set_id)
					output[x][y].rule_out_based_on_neighbor(s_tile, dir_w)
				end
			end
		end
	end

	move_actors_from_scroll(1,0)

	if (num_times <= 1) then scroll_cleanup()
	else 				scroll_right(num_times-1)	end
end

function scroll_up(num_times)
	printh("scroll up")
	for x=1, output_c do
		for y=1, output_r do
			if y < output_r then
				output[x][y].copy_from(output[x][y+1])
			else
				output[x][y].reset(unique_ids)
				if (output[x][y-1].state == tile_state_set) then
					local s_tile = get_source_tile_from_id(output[x][y-1].set_id)
					output[x][y].rule_out_based_on_neighbor(s_tile, dir_s)
				end
			end
		end
	end

	move_actors_from_scroll(0,-1)

	if (num_times <= 1) then scroll_cleanup()
	else 				scroll_up(num_times-1)	end
end

function scroll_down(num_times)
	printh("scroll down")
	for x=1, output_c do
		for y=output_r, 1, -1 do
			if y > 1 then
				output[x][y].copy_from(output[x][y-1])
			else
				output[x][y].reset(unique_ids)
				if (output[x][y+1].state == tile_state_set) then
					local s_tile = get_source_tile_from_id(output[x][y+1].set_id)
					output[x][y].rule_out_based_on_neighbor(s_tile, dir_n)
				end
			end
		end
	end

	move_actors_from_scroll(0,1)

	if (num_times <= 1) then scroll_cleanup()
	else 				scroll_down(num_times-1)	end
end

function move_actors_from_scroll(tile_dx, tile_dy)
	cam_x += tile_dx * 8
	cam_y += tile_dy * 8
	tester_x += tile_dx
	tester_y += tile_dy

	if (wraith != nil) then
		wraith.x += tile_dx
		wraith.y += tile_dy
	end

	for a in all(actors) do
		a.x += tile_dx
		a.y += tile_dy
	end
end

function scroll_cleanup()
	is_done = false
	take_snapshot()
end

--run through the source tiles and log neighbor frequency
function set_neighbor_info()
	printh(" set neighbor info")
	
	for s in all(source_tiles) do
		s.reset_neighbor_info()
	end 

	for x=1, source_c do
		for y=1, source_r do
			local this_id = source[x][y]

			--north
			if y > 1 then
				get_source_tile_from_id(this_id).note_neighbor(dir_n, source[x][y-1])
			end
			--east
			if x < source_c then
				get_source_tile_from_id(this_id).note_neighbor(dir_e, source[x+1][y])
			end
			--south
			if y < source_r then
				get_source_tile_from_id(this_id).note_neighbor(dir_s, source[x][y+1])
			end
			--west
			if x > 1 then
				get_source_tile_from_id(this_id).note_neighbor(dir_w, source[x-1][y])
			end
		end
	end
end

--kicks things off
function do_first_move()
	printh("doing first move")
	need_first_move = false
	root_move.prune()
	cur_move.copy_from(root_move)

	local start_x = player_start_x --flr(rnd(output_c)+1)
	local start_y = player_start_y  --flr(rnd(output_r)+1)
	local start_id = 0 --source_tiles[flr(rnd(#source_tiles))+1].id
	cur_move = make_check_point(root_move)
	cur_move.move(start_x, start_y, start_id)
	update_board_from_move(cur_move, true, false)
end

--makes the next move
function advance()
	if is_done then	return end

	if doing_revert then
		do_revert_step()
		return
	end

	if need_first_move then
		do_first_move()
		return
	end

	local old_move = cur_move
	cur_move = make_check_point(old_move)

	--printh("prev move bad moves:"..tostr(#old_move.bad_moves))

	--figure out the lowest number of choices any tile has
	local low_val = #source_tiles+1
	for x=1, output_c do
		for y=1, output_r do
			if output[x][y].state == tile_state_active then
				low_val = min(low_val, #output[x][y].potential_ids)
			end
		end
	end

	--get all of the active tiles with the least choices
	local choices = {}
	for x=1, output_c do
		for y=1, output_r do
			if (output[x][y].state == tile_state_active and #output[x][y].potential_ids == low_val) then
				--printh("  low val:"..tostr(x)..","..tostr(y))
				add(choices, output[x][y])
			end
		end
	end

	--maybe we're done
	if (#choices == 0) then
		printh("we done")
		finalize_tiles()
		return
	end

	--select one at random
	local this_choice = flr(rnd(#choices)+1)

	--printh(" looking at "..tostr(choices[this_choice].x)..","..tostr(choices[this_choice].y).."  status: "..tostr(choices[this_choice].state))

	--get the frequency for each direction
	local this_tile_id = -1
	local tile_choices = get_tile_choices_with_freq(choices[this_choice].x, choices[this_choice].y)

	--printh(" i have "..tostr(#tile_choices).." choices")

	local total_freq = 0
	for t in all(tile_choices) do
		total_freq += t.freq
	end
	local roll = rnd(total_freq)

	for i=1, #tile_choices do
		roll -= tile_choices[i].freq
		if roll <= 0 then
			this_tile_id = tile_choices[i].id
			break
		end
	end

	--make a move
	cur_move.move(choices[this_choice].x, choices[this_choice].y, this_tile_id)

	--update the board
	--printh("update from advance")
	update_board_from_move(cur_move, true, false)

end

function finalize_tiles()
	is_done = true
	--spawn the player if this is the first time we're done
	if (pl == nil) then
		start_game()
	end

	local scorp_id = 11
	local cut_id = 12
	for x=1, output_c do
		for y=1, output_r do
			if (output[x][y].set_id == scorp_id) then
				make_scorpion(x,y)
				output[x][y].set_id = 0
				printh("scorp on "..tostr(x)..","..tostr(y))
			end
			if (output[x][y].set_id == cut_id) then
				make_cutter(x,y)
				output[x][y].set_id = 0
				printh("cutter on "..tostr(x)..","..tostr(y))
			end
		end
	end
end



--gets potential source tiles that culd go in a given slot, weighted by frequency
function get_tile_choices_with_freq(col, row)
	--get all tiles this once could still potentially be
	local choices = {}
	for id in all(output[col][row].potential_ids) do
		local info = make_neighbor_info(id)
		info.freq = 0
		add(choices, info)
	end

	--check north
	if row > 1 then
		if output[col][row-1].state == tile_state_set then
			local this_id = output[col][row-1].set_id
			get_source_tile_from_id(this_id).add_neighbor_freq(dir_s, choices)
		end
	end
	--check east
	if col < output_c then
		if output[col+1][row].state == tile_state_set then
			local this_id = output[col+1][row].set_id
			get_source_tile_from_id(this_id).add_neighbor_freq(dir_w, choices)
		end
	end
	--check south
	if row < output_r then
		if output[col][row+1].state == tile_state_set then
			local this_id = output[col][row+1].set_id
			get_source_tile_from_id(this_id).add_neighbor_freq(dir_n, choices)
		end
	end
	--check west
	if col > 1 then
		if output[col-1][row].state == tile_state_set then
			local this_id = output[col-1][row].set_id
			get_source_tile_from_id(this_id).add_neighbor_freq(dir_e, choices)
		end
	end

	return choices
end

--takes a move and updates the output map
function update_board_from_move(point, do_validate, print_debug)
	if is_done then return end

	local move = point.this_move
	if move.col == -1 or move.id == -1 then
		printh("empty move, skipping")
		validate_board()
		return
	end

	if print_debug then
		printh("updating board  x:"..tostr(move.col).." y:"..tostr(move.row).."  id:"..tostr(move.id).."  depth: "..tostr(point.get_depth()))
		printh(" previous bad moves: "..tostr(#point.bad_moves))
	end

	--set given tiles
	output[move.col][move.row].set(move.id)

	--rule out anything that previously lead to dead ends
	for bad in all(point.bad_moves) do
		output[bad.col][bad.row].rule_out_id(bad.id)
		printh(" dont do "..tostr(bad.col)..","..tostr(bad.row)..": "..tostr(bad.id))
	end

	--update neighbors
	local tile = get_source_tile_from_id(move.id)
	if tile != nil then 	--this should never be nil
		if move.row > 1 then
			--printh("rule out north")
			output[move.col][move.row-1].rule_out_based_on_neighbor(tile, dir_n)
		end
		if move.col < output_c then
			--printh("rule out east")
			output[move.col+1][move.row].rule_out_based_on_neighbor(tile, dir_e)
		end
		if move.row < output_c then
			output[move.col][move.row+1].rule_out_based_on_neighbor(tile, dir_s)
		end
		if move.col > 1 then
			output[move.col-1][move.row].rule_out_based_on_neighbor(tile, dir_w)
		end
	end

	--validate
	if do_validate then validate_board() end
end

--if any tiles have no viable options, we need to revert
function validate_board()
	is_valid = true
	for x=1, output_c do
		for y=1, output_r do
			if (output[x][y].state == tile_state_active and #output[x][y].potential_ids == 0) then
				is_valid = false
				printh("thats a bad bake")
				break
			end
		end
	end

	if is_valid == false then
		printh("move "..tostr(cur_move.get_depth()).." is a problem")
		cur_move.prev.rule_out_move(cur_move.this_move)

		printh(" ruling out "..tostr(cur_move.this_move.col)..","..tostr(cur_move.this_move.row).." id:"..tostr(cur_move.this_move.id))
		printh(" total ruled out: "..tostr(#cur_move.prev.bad_moves))

		revert_to_check_point(cur_move.prev)
	end
end

--resetting the board to a previous check point
--sets thigns up to happen one at a time when advanced
revert_to_check_point = function(point)
	revert_target_depth= point.get_depth()
	doing_revert = true


	printh("reverting to "..tostr(revert_target_depth))
	reset_output()

	if (revert_target_depth == 0) then
		need_first_move = true
		printh("full reset")
	end

	--go back to the first move to start
	cur_move.copy_from(root_move)
end

do_revert_step = function()
	local revert_is_done = false

	local num_steps = 10
	for i=1, num_steps do
		printh("redo move "..tostr(cur_move.get_depth().." of "..tostr(revert_target_depth)))
		cur_move = cur_move.next
		update_board_from_move(cur_move, true, false)
		if (cur_move.get_depth() == revert_target_depth) then
			revert_is_done = true
			break
		end
	end

	if revert_is_done then
		printh("revert done, pruning")
		doing_revert = false
		cur_move.prune()

		--auto_advance = false
	end

	
end

--resetting the board to a previous check point
--done in one shot, not using
revert_to_check_point_one_shot = function(point)
	local this_depth = point.get_depth()

	printh("reverting to "..tostr(point.get_depth()))
	reset_output()

	if (this_depth == 0) then
		need_first_move = true
		printh("full reset")
	end

	--you probably can just use a for loop from 0 to this_depth
	cur_move.copy_from(root_move)
	while(cur_move.get_depth() != this_depth) do
		printh("redo move "..tostr(cur_move.get_depth()))
		--printh("  prev:"..tostr(cur_move.prev))
		update_board_from_move(cur_move, false, false)
		cur_move = cur_move.next
	end

	printh(" do the final update for the revert")
	update_board_from_move(cur_move, true, false)
	cur_move.prune()

	--auto_advance = false
end

--grabs the source tile based on the id
function get_source_tile_from_id(id)
	--printh("check "..tostr(id))
	for s in all(source_tiles) do
		--printh("  against "..tostr(s.id))
		if s.id == id then
			return s
		end
	end

	printh("bad: source tile not found for id:"..tostr(id))
	return nil
end


-- ************
-- wfc classes
-- ************

--helper class for trakcing source tile neighbors
function make_neighbor_info(id)
	local info = {}
	info.id = id
	info.freq = 1
	return info
end

--source tiles
function make_source_tile(id)
	local t = {}
	t.id = id
	t.neighbors = { {}, {}, {}, {}}

	-- 1:n, 2:e, 3:s, 4:w
	t.reset_neighbor_info = function()
		for n in all(t.neighbors) do
			n = {}
		end
	end

	t.note_neighbor = function(dir, neighbor_id)
		--is this already in the list?
		for n in all(t.neighbors[dir]) do
			if (n.id == neighbor_id) do
				n.freq+=1
				return
			end
		end

		--if not, add it
		add(t.neighbors[dir], make_neighbor_info(neighbor_id))
	end

	--takes the incoming array and adds frequncy values to it based on this tiles neighbors
	t.add_neighbor_freq = function(dir, choices)
		for i=1, #choices do
			for k=1, #t.neighbors[dir] do
				if (choices[i].id == t.neighbors[dir][k].id) then
					choices[i].freq += t.neighbors[dir][k].freq
				end
			end
		end
	end

	return t
end

--output tiles
function make_output_tile(x,y, _unique_ids)
	local t = {}
	t.state = tile_state_inactive
	t.potential_ids = {}
	t.set_id = -1

	t.x = x
	t.y = y

	t.t = 0

	t.rnd = flr(rnd(100))

	t.reset = function(_unique_ids)
		t.state = tile_state_inactive
		t.set_id = -1
		t.potential_ids = {}
		for i=1, #_unique_ids do
			add(t.potential_ids, _unique_ids[i])
		end
		t.t = -flr(rnd(3))
	end

	t.set = function(id)
		t.state = tile_state_set
		t.set_id = id
		t.potential_ids = {}
	end

	t.copy_from = function(other)
		t.state = other.state
		t.set_id = other.set_id
		--t.x = other.x
		--t.y = other.y
		t.potential_ids = {}
		for i=1, #other.potential_ids do
			add(t.potential_ids, other.potential_ids[i])
		end
	end

	t.get_rand_potential_id = function()
		return t.potential_ids[ flr(rnd(#t.potential_ids)+1) ]
	end

	t.rule_out_based_on_neighbor = function (other, dir)
		--printh(" rule me out brah "..tostr(other.id).." in dir "..tostr(dir))
		if t.state == tile_state_set then return end

		--if this is having things ruled out, it must have a neighbor
		t.state = tile_state_active

		local good_ids = {}
		for i=1, #other.neighbors[dir] do
			add(good_ids, other.neighbors[dir][i].id)
		end

		--printh(" got "..tostr(#good_ids).." good ids")

		--go through and remove and ids that are no good
		--doing this in reverse so we can remove items
		for i=#t.potential_ids,1,-1 do
			local is_good = false
			for k=1, #good_ids do
				if t.potential_ids[i] == good_ids[k] then
					is_good = true
				end
			end

			if is_good == false then
				del(t.potential_ids, t.potential_ids[i])
			end
		end
	end

	t.rule_out_id = function(id)
		for i=#t.potential_ids,1,-1 do
			if (t.potential_ids[i] == id) then
				del(t.potential_ids, t.potential_ids[i])
			end
		end
	end

	--paraphrased from https://www.lexaloffle.com/bbs/?tid=2119
	t.has_flag = function(flag)
		if t.state == tile_state_set then
	 		return fget(t.set_id, flag)
 		end
 		return false
 	end

	t.reset(_unique_ids)
	return t
end


--check points
function make_move_info(col, row, id)
	local m = {}
	m.col = col
	m.row = row
	m.id = id

	m.set = function(col, row, id)
		m.col = col
		m.row = row
		m.id = id
	end

	m.clear = function()
		m.col = -1
		m.row = -1
		m.id = -1
	end

	return m
end

function make_check_point(prev_move)
	local m = {}

	m.prev = nil
	m.next = nil
	m.this_move = make_move_info(-1, -1, -1)
	m.bad_moves = {}

	m.setup = function(prev_move)
		m.prev = prev_move
		if (m.prev != nil) then
			m.prev.next = m
		end
	end

	m.copy_from = function(other)
		m.prev = other.prev
		m.next = other.next
		m.this_move = make_move_info(other.this_move.col, other.this_move.row, other.this_move.id)
		m.bad_moves = {}
		for i=1, #other.bad_moves do
			add(m.bad_moves,make_move_info(other.bad_moves[i].col, other.bad_moves[i].row, other.bad_moves[i].id))
		end
	end

	m.move = function(col, row, id)
		m.this_move.set(col, row, id)
	end

	m.rule_out_move = function (bad)
		add(m.bad_moves, make_move_info(bad.col,bad.row,bad.id))
	end

	--this probably leaks memory like a mother fucker
	m.prune = function()
		m.next = nil
	end

	m.get_depth = function()
		if m.prev == nil then
			return 0
		else
			return m.prev.get_depth()+1
		end
	end

	m.setup(prev_move)
	return m
end



__gfx__
00000000060606060e0e0e0e0003300044444444000000000040400000000000000c00000dd00dd0babbbbbb0800000000000000000000000000000000000000
0000000060606060e0e0e0e00003bb00000000000000074f40404040000440000166cc1007777770bb3333338558000000000000000000000000000000000000
00000000060606060e0e0e0e00300b0040444044ffffff0f7dddddd000f49400111111110dd00dd033333b335008e000008e0880000000000000000000000000
0000000060606060e0e0e0e0000300000000000044444f0f00400d00004f99001c1111110dd00dd033b333b38000808e00055000000000000000000000000000
00000000060606060e0e0e0e0bb30000444044400f000f74404007000094940011111c110dd00dd033333333585800880005e000000000000000000000000000
0000000060606060e0e0e0e00b00300000000000ff0000007dddddd00009400011111111077777703333333b085558500880e800000000000000000000000000
00000000060606060e0e0e0e0000300040444044000000000040404000000000111111110dd00dd0333bb3330885550000000000000000000000000000000000
0000000060606060e0e0e0e00003000000000000000000004040404000000000111111110dd00dd0333b33338000055000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
80000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08022080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00800800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
02088020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
02088020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00800800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08022080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
80000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00333000003330000033300000333000003330000033300000000000000000000000000000000000000000000000000000000000000000000000000000000000
00399300033d9000033d90000d33300000333d000333d00000000000000000000000000000000000000000000000000000000000000000000000000000000000
00d99d0003d99090033990000533d00000d335000333900000000000000000000000000000000000000000000000000000000000000000000000000000000000
005555009d55550000d5500005555d000d555500055555d900000000000000000000000000000000000000000000000000000000000000000000000000000000
05d555000005500009d55d9000d55d000d55d00005d5500000000000000000000000000000000000000000000000000000000000000000000000000000000000
09ddd90000dddd0000ddd00000ddd00000ddd00000ddd0000dddd000000000000000000000000000000000000000000000000000000000000000000000000000
00d0d00009d0090000d0d00000d090000090d00000d09000339ddd90000000000000000000000000000000000000000000000000000000000000000000000000
009090000000090000909000009000000000900009000900399dddd9000000000000000000000000000000000000000000000000000000000000000000000000
08000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
85580000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5008e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8000808e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
58580088000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08555850000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08855500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
80000550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000001110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000011990000000000000000000003c0000003c000000000000000000000000000000000000000000000000000000000000000000000000000
008e088000000000001199000000000000000000003ccc00003ccc00000000000000000000000000000000000000000000000000000000000000000000000000
000550000000000000555500000000000000000003cbbcc003c88cc0000000000000000000000000000000000000000000000000000000000000000000000000
0005e0000000000000005590000000000000000003cbb3c003c883c0000000000000000000000000000000000000000000000000000000000000000000000000
0880e80000000000009dd500000000000000000000c33c0000c33c00000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000055000000000000000000000cc000000cc000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000050a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a025500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00581810000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a211550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00551500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00252200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
52105200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000402080008100411000002020200000000000000000000000202020202000000000000000000000000000000020000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
00000003000404040400000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b000300060000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0404040409040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000009000000050004040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0408080804080808040003040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0404040404040404040003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000070000000003000003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a0a040a0a040003000003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0404040404040403000403040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
