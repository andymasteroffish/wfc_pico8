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
source_c = 38
source_r = 14

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

is_done = false
need_first_move = true
auto_advance = true

--history
root_move = nil 
cur_move = nil

revert_target_depth = 0
doing_revert = false

--bandaid time, babey
last_scroll_dir = -1
num_reverts_since_stable = 0

--testing
tester_x = 12
tester_y = 12

--camera
cam_x = 0
cam_y = 0

--player
pl = nil
actors = {} --all actors in world

player_start_x = 12
player_start_y = 12

--https://www.lexaloffle.com/bbs/?tid=2119
function make_actor(x,y)
	local a={}
	a.x = x
	a.y = y
	a.dx = 0
	a.dy = 0
	a.grav = 0.1
	a.spr = 64
	a.frame = 0
	a.t = 0
	a.inertia = 0.6
	a.bounce = 1

	a.w = 0.3
	a.h = 0.3

	add(actors,a)
	return a
end



--init
function _init()
	palt(0,false)
	palt(5,true)

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




--update
function _update()
	if (btnp(4)) then
		advance()
	end
	if auto_advance then
		for i=1, 4 do
			advance()
		end
	end


	--a
	if (btnp(5,1)) then
		auto_advance = not auto_advance
		printh("auto "..tostr(auto_advance))
	end

	--s
	if (btnp(0,1)) then
		printh("reset")
		need_first_move = true
		reset_output()
	end

	--d testing blowing shit up
	if (btnp(3,1)) then
		blow_up_rect(tester_x-2, tester_y-2, tester_x+2, tester_y+2)
	end

	--f scrolling
	if (btnp(1,1) and is_done) then
		scroll_left(buffer_dist)
	end

	--scrolling the camera
	local scroll_dist = 50
	local scroll_speed = 0.7
	local tester_screen_x = (tester_x-buffer_dist)*8 - 4 - cam_x
	local tester_screen_y = (tester_y-buffer_dist)*8 - 4 - cam_y
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

	--do we need to scroll the grid?
	if (is_done) then
		if (tester_x <= buffer_dist*3) then
			printh(" natural scroll right")
			scroll_right(buffer_dist)
		elseif (tester_x >= output_c-buffer_dist*3) then
			printh(" natural scroll left")
			scroll_left(buffer_dist)
		elseif (tester_y <= buffer_dist*3) then
			printh(" natural scroll down")
			scroll_down(buffer_dist)
		elseif (tester_y >= output_r-buffer_dist*3) then
			printh(" natural scroll up")
			scroll_up(buffer_dist)
		end
	end

	check_input()

	foreach(actors, move_actor)
end

function check_input()

	if pl == nil then
		if btnp(0) then tester_x -= 1 end
		if btnp(1) then tester_x += 1 end
		if btnp(2) then tester_y -= 1 end
		if btnp(3) then tester_y += 1 end
	else
		accel = 0.15
		if (btn(0)) pl.dx -= accel
		if (btn(1)) pl.dx += accel

		if btnp(2) then 
			pl.dy = -1.5
			printh("bounce")
		end
	end

	--spawn the player
	if btnp(2,1) then
		pl = make_actor(tester_x-0.5, tester_y-0.5)
	end
end

function blow_up_rect(x1,y1, x2,y2)
	printh("blow up "..tostr(x1)..","..tostr(y1).." to "..tostr(x2)..","..tostr(y2))
	local start_x = max(1, x1)
	local end_x = min(output_c, x2)
	local start_y = max(1, y1)
	local end_y = min(output_r, y2)

	--knock em out
	for x=start_x, end_x do
		for y=start_y, end_y do
			output[x][y].reset(unique_ids)
		end
	end

	--rule out based on neighbors
	for x=start_x, end_x do
		for y=start_y, end_y do

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

	take_snapshot()
	is_done = false
end


--draw
function _draw()
	camera(0,0)
	local bg_col = 5
	if (doing_revert)	bg_col = 12
	rectfill(0,0,128, 128, bg_col)
	--map(0,0, 0,0, 12, 9)

	camera(cam_x, cam_y)

	--draw output
	local out_x = -buffer_dist*8
	local out_y = -buffer_dist*8
	for x=1, output_c do
		for y=1, output_r do
			local sprite = 1 --grey checker
			if output[x][y].state == tile_state_active then
				sprite = 2 --color checker
			end
			if output[x][y].state == tile_state_set then
				sprite = output[x][y].set_id
			end
			spr(sprite, out_x+(x-1)*8, out_y+(y-1)*8)

			--num choices
			if output[x][y].state == tile_state_active then
				print(tostr(#output[x][y].potential_ids), out_x+(x-1)*8+1, out_y+(y-1)*8+1, 7)
			end
		end
	end
	
	--actors
	foreach(actors, draw_actor)	--runs through array, calling function on each

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

	--draw tester
	tester_draw_x = out_x+(tester_x-1)*8
	tester_draw_y = out_y+(tester_y-1)*8
	rect(tester_draw_x, tester_draw_y, tester_draw_x+8, tester_draw_y+8, 7 )


	camera(0,0)

	--testing
	if false then
		for i=1, #source_tiles do
			local x_pos = 2+(i-1)*12
			spr(source_tiles[i].id, x_pos, 90)
			print(tostr(source_tiles[i].id), x_pos,100, 7)
		end
	end

	local debug_text = tostr(tester_x)..","..tostr(tester_y)
	debug_text = debug_text.."\n"..tostr(output[tester_x][tester_y].solid())
	debug_text = debug_text.."\n".."state: "..tostr(output[tester_x][tester_y].state)
	debug_text = debug_text.."\n".."setid: "..tostr(output[tester_x][tester_y].set_id)
	debug_text = debug_text.."\n".."depth: "..tostr(cur_move.get_depth())
	debug_text = debug_text.."\n".."reverts: "..tostr(num_reverts_since_stable)

	local first_move_text = "nil"
	if (root_move.next != nil) then
		local move = root_move.next.this_move
		first_move_text = "x:"..tostr(move.col).." y:"..tostr(move.row).."  id:"..tostr(move.id)
	end
	debug_text = debug_text.."\n"..first_move_text

	if btn(5) then
		print(debug_text, 2, 9, 7)
	end
	
	
end

--https://www.lexaloffle.com/bbs/?tid=2119
function move_actor(a)
	printh("vel "..tostr(a.dx)..","..tostr(a.dy))

	a.dy += a.grav

	--moving along x (if clear)
	if not solid_area(a.x+a.dx, a.y, a.w, a.h) then
		a.x += a.dx
	else
		a.dx = 0
	end

	--now y
	if not solid_area(a.x, a.y+a.dy, a.w, a.h) then
		a.y += a.dy
	else
		a.dy = 0
	end

	a.dx *= a.inertia
	a.dy *= a.inertia

	a.t += 1

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
		output[left_x][top_y].solid() or
		output[right_x][top_y].solid() or
		output[left_x][bot_y].solid() or
		output[right_x][bot_y].solid()
end

--https://www.lexaloffle.com/bbs/?tid=2119
function draw_actor(a)
	local sx = (a.x * 8)-4
	local sy = (a.y * 8)-4
	spr(a.spr + a.frame, sx, sy)
	--printh("pos at "..tostr(a.x)..","..tostr(a.y))
	--printh("draw at "..tostr(sx)..","..tostr(sy))

	--test
	pset(a.x*8, a.y*8, 8)
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
	last_scroll_dir = dir_w
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
	last_scroll_dir = dir_e
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
	last_scroll_dir = dir_n
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
	last_scroll_dir = dir_s
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
		is_done = true
		num_reverts_since_stable = 0
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
	num_reverts_since_stable += 1

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

	--if this has been going on for a really long time, bail
	if false then
		if num_reverts_since_stable > 100 and last_scroll_dir >= 1 then
			printh("too many reverts, unscroll")
			num_reverts_since_stable = 0
			reset_output()
			if last_scroll_dir == dir_n then scroll_down(buffer_dist) 
			elseif last_scroll_dir == dir_e then scroll_left(buffer_dist) 
			elseif last_scroll_dir == dir_s then scroll_up(buffer_dist) 
			elseif last_scroll_dir == dir_w then scroll_right(buffer_dist) 
			end
			doing_revert = false
		end
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

	t.reset = function(_unique_ids)
		t.state = tile_state_inactive
		t.set_id = -1
		t.potential_ids = {}
		for i=1, #_unique_ids do
			add(t.potential_ids, _unique_ids[i])
		end
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
	--flag 1 set means not solid
	t.solid = function ()
		if t.state == tile_state_set then
	 		-- check if flag 1 is set (the
	 		-- orange toggle button in the 
	 		-- sprite editor)
	 		return fget(t.set_id, 1) == false
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
55555555565656565e5e5e5e444444443444444444444443344444435944444444444495594444955bbbbbb55555555555555555555555555555555555555555
5555555565656565e5e5e5e544444444344444444444444334444443594444444444449559444495bb3bb3bb5555555555555555555555555555555555555555
55555555565656565e5e5e5e44444444244444444444444224444442594444444444449559444495b323323b5555555555555555555555555555555555555555
5555555565656565e5e5e5e544444444444444444444444444444444594444444444449559444495b342243b5555555555555555555555555555555555555555
55555555565656565e5e5e5e444444444444444444444444444444445944444444444495594444955b4444b55555555555555555555555555555555555555555
5555555565656565e5e5e5e544444444444444444444444444444444594444444444449559444495544444455555555555555555555555555555555555555555
55555555565656565e5e5e5e444444444444444444444444444444445944444444444495594444955944449555555555555555b55555b55555b555b55555b555
5555555565656565e5e5e5e5444444444444444444444444444444445944444444444495594444955944449555b555b555b555b55b55b5b555b555b55555b555
5bbbbbbbbbbbbbbbbbbbbbb54444444434444444444444433444444359444443344444955bbbbbb5594444955555555555555555555555555555555555555555
bb3bb3bbbb3bb3bbbb3bb3bb444444443444444444444443344444435944444334444495bb3bb3bb594444955555555555555555555555555555555555555555
b3233233332332333323323b444444442444444444444442444444445944444224444495b323323b594444955555555555555555555555555555555555555555
b3422422224224222242243b444444444444444444444444444444445944444444444495b342243b5944449555555555555555555555ee5555555555555dd555
5b44444444444444444444b54444444444444444444444444444444459444444444444955b4444b559444495555555a555555555555eeae555555555555d6dd5
544444444444444444444445444444444444444444444444444444445944444444444495544444455444444555555a1a5555855555eaee55555555555dd6666d
524444444444444444444425444444444444444444444444444444445944444444444495524444255244442555555ba55558a855555eeb5555b555555d6666dd
552222222222222222222255224444442244444422444444224444445944444444444495552222555522225555555b5555558b555555b55555b55b5555566d55
5bbbbbbbbbbbbbbbbbbbbbb544444444344444444444444334444443594444433444449559444444444444444444449555555555555555555555555555553555
bb3bb3bbbb3bb3bbbb3bb3bb44444444344444444444444334444443594444433444449559444444444444444444449555555555555555555555555555553555
b3233233332332333323323b44444444444444444444444224444442594444422444449559444444444444444444449555555555555555555555555555533555
b3422422224224222242243b44444444444444444444444444444444594444444444449559444444444444444444449555555555555555555555555555533355
5b44444444444444444444b54444444444444444444444444444444459444444444444955944444444444444444444955555555555555555555555555533b335
54444444444444444444444544444444444444444444444444444444594444444444449554444444444444444444444555555555555555555555555553333355
59444444444444444444449544444444444444444444444444444444594444444444449552444444444444444444442555555555555555555555555555333335
594444444444444444444495444444224444442244444422444444225944442222444495552222222222222222222255555555555555555555555555533b3333
5bbbbbbbbbbbbbbbbbbbbbb544444444344444444444444334444443594444444444449559444443444444433444444434444443344444955555555533333355
bb3bb3bbbb3bb3bbbb3bb3bb44444444344444444444444334444443594444444444449559444443444444433444444434444443344444955555555555333355
b3233233332332333323323b44444444244444444444444224444442594444444444449559444442444444422444444424444442244444955555555553b33335
b3422422224224222242243b44444444444444444444444444444444594444444444449559444444444444444444444444444444444444955555555553333b33
5b44444444444444444444b544444444444444444444444444444444594444444444449559444444444444444444444444444444444444955555555533333335
54444444444444444444444544444444444444444444444444444444594444444444449554444444444444444444444444444444444444455555555555522555
59444444444444444444449544444444444444444444444444444444594444444444449552444444444444444444444444444444444444255555555555544555
59444422224444222244449522444422224444222244442222444422594444222244449555222222222222222222222222222222222222555555555555444455
55111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55991155555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55991155555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55000055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
59005555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
550dd955555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55005555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55595555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
__gff__
0200000000000000000000020202020200000000000000000000000202020202000000000000000000000000000000020000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00202122000a0000000a000000000a000a000000000000002f20212200301111320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007030800090000200622000020261116220000002022003f07030800090000090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00292a2b000900101403251200070800070800000029152121242a2b00090000090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000001a000029332b0000293511342b00000000070303080000003911113d002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0010120019000000001a000000001a001a0000000020242a2a3800000000000000003f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000002012000000000000000a00292b000017212200002021212121212200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001011111200002f00001a00000000000000103c120000000007030800000703030303030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000003f0000000020212200000a0000000a000000292a2b00000703232a13030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000202121212200103b2a2b0010280019002712000000000000000703080007030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0020212200291303232b000000000000001a0000001a00001021212200000703052104030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00292a380000292a3800000a000a001022001031120000000007030800000703030303030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000001a000000001a00102b002912001a00001a0000000000292a2b0000292a2a2a2a2a2b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
