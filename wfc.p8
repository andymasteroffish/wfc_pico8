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
output_c = 16
output_r = 16

tile_state_inactive = 1
tile_state_active = 2
tile_state_set = 3

is_done = false
need_first_move = true
auto_advance = false

--history
root_move = nil 
cur_move = nil

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

	t.reset = function(x,y, _unique_ids)
		t.x = x
		t.y = y

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

	t.reset(x,y,_unique_ids)
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

--init
function _init()
	palt(0,false)
	--palt(4,true)

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
		for y=1, output_r do
			add(output[x], make_output_tile(x,y,unique_ids))
		end
	end

	set_neighbor_info()

	root_move = make_check_point(nil)	

	--testing
	if false then
		printh("checking tile: 1")
		local s_tile = get_source_tile_from_id(1)
		local dir_names = {"north","east","south","west"}
		for d=1, 4 do
			printh(dir_names[d].."  "..tostr(#s_tile.neighbors[d]))
			for t in all(s_tile.neighbors[d]) do
				printh("  sprite "..tostr(t.id).." :"..tostr(t.freq).." occurrences")
			end
		end
	end
end

--resets the output image
function reset_output()
	printh("reset output")
	for x=1, output_c do
		for y=1, output_r do
			output[x][y].reset(x,y, unique_ids)
		end
	end

	is_done = false
	
end

--run through the source tiles and log neighbor frequency
function set_neighbor_info()
	
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
	cur_move = root_move

	local start_x = flr(rnd(output_c)+1)
	local start_y = flr(rnd(output_r)+1)
	local start_id = source_tiles[flr(rnd(#source_tiles))+1].id
	cur_move = make_check_point(cur_move)
	cur_move.move(start_x, start_y, start_id)
	update_board_from_move(cur_move, false)
end

--makes the next move
function advance()
	if is_done then	return end

	if need_first_move then
		do_first_move()
		return
	end

	local old_move = cur_move
	cur_move = make_check_point(old_move)

	--make a list of the active potential tiles with the fewest posibilities
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
				add(choices, output[x][y])
			end
		end
	end

	--maybe we're done
	if (#choices == 0) then
		printh("we done")
		is_done = true
		return
	end

	--select one at random
	local this_choice = flr(rnd(#choices)+1)

	--get the frequency for each direction
	local this_tile_id = -1
	local tile_choices = get_tile_choices_with_freq(choices[this_choice].x, choices[this_choice].y)

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
	update_board_from_move(cur_move, false)
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
function update_board_from_move(point, print_debug)
	if is_done then return end

	local move = point.this_move
	if move.col == -1 then
		printh("empty move")
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
		printh("hey brah dont do "..tostr(bad.col)..","..tostr(bad.row)..": "..tostr(bad.id))
	end

	--update neighbors
	local tile = get_source_tile_from_id(move.id)
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

	--validate
	validate_board()
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
		revert_to_check_point(cur_move.prev)
	end
end

--resetting the board to a previous check point
revert_to_check_point = function(point)
	printh("reverting to "..tostr(point.get_depth()))
	reset_output()

	if (point.get_depth() == 0) then
		need_first_move = true
		printh("full reset")
	end

	cur_move = root_move
	while(cur_move != point) do
		--printh("redo move "..tostr(cur_move.get_depth()))
		--printh("  prev:"..tostr(cur_move.prev))
		update_board_from_move(cur_move, false)
		cur_move = cur_move.next
	end

	update_board_from_move(cur_move, false)
	cur_move.prune()

	printh("done reverting")

	--auto_advance = false
end


--update
function _update()
	if (btnp(4) or auto_advance) then
		--printh("advance")
		advance()
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

	printh("that is bad")
	return nil
end

--draw
function _draw()
	rectfill(0,0,128,128, 0)
	--map(0,0, 0,0, 12, 9)

	--draw output
	if (need_first_move == false or true) then
		local out_x = 0
		local out_y = 0
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
	end

	--draw source
	if (btn(5)) then
		local src_x = 1
		local src_y = 1
		rectfill(src_x-1, src_y-1, src_x+source_c*8+1, src_y+source_r*8+1, 12)
		for x=1, source_c do
			for y=1, source_r do
				spr(source[x][y], src_x+(x-1)*8, src_y+(y-1)*8)
			end
		end
	end




	--testing
	if false then
		for i=1, #source_tiles do
			local x_pos = 2+(i-1)*12
			spr(source_tiles[i].id, x_pos, 90)
			print(tostr(source_tiles[i].id), x_pos,100, 7)
		end
	end
end

__gfx__
00000000060606060e0e0e0e444444443444444444444443344444430944444444444490094444900bbbbbb00000000000000000000000000000000000000000
0000000060606060e0e0e0e044444444344444444444444334444443094444444444449009444490bb3bb3bb0000000000000000000000000000000000000000
00000000060606060e0e0e0e44444444244444444444444224444442094444444444449009444490b323323b0000000000000000000000000000000000000000
0000000060606060e0e0e0e044444444444444444444444444444444094444444444449009444490b342243b0000000000000000000000000000000000000000
00000000060606060e0e0e0e444444444444444444444444444444440944444444444490094444900b4444b00000000000000000000000000000000000000000
0000000060606060e0e0e0e044444444444444444444444444444444094444444444449009444490044444400000000000000000000000000000000000000000
00000000060606060e0e0e0e444444444444444444444444444444440944444444444490094444900944449000000000000000b00000b00000b000b00000b000
0000000060606060e0e0e0e0444444444444444444444444444444440944444444444490094444900944449000b000b000b000b00b00b0b000b000b00000b000
0bbbbbbbbbbbbbbbbbbbbbb04444444434444444444444433444444309444443344444900bbbbbb0094444900000000000000000000000000000000000000000
bb3bb3bbbb3bb3bbbb3bb3bb444444443444444444444443344444430944444334444490bb3bb3bb094444900000000000000000000000000000000000000000
b3233233332332333323323b444444442444444444444442444444440944444224444490b323323b094444900000000000000000000000000000000000000000
b3422422224224222242243b444444444444444444444444444444440944444444444490b342243b0944449000000000000000000000ee000000000000055000
0b44444444444444444444b04444444444444444444444444444444409444444444444900b4444b009444490000000a000000000000eeae000000000005d6550
044444444444444444444440444444444444444444444444444444440944444444444490044444400444444000000a1a0000800000eaee000000000005d66665
024444444444444444444420444444444444444444444444444444440944444444444490024444200244442000000ba00008a800000eeb0000b00000056666d5
002222222222222222222200224444442244444422444444224444440944444444444490002222000022220000000b0000008b000000b00000b00b0000566d50
0bbbbbbbbbbbbbbbbbbbbbb044444444344444444444444334444443094444433444449009444444444444444444449000000000000000000000000000003000
bb3bb3bbbb3bb3bbbb3bb3bb44444444344444444444444334444443094444433444449009444444444444444444449000000000000000000000000000003000
b3233233332332333323323b44444444444444444444444224444442094444422444449009444444444444444444449000000000000000000000000000033000
b3422422224224222242243b44444444444444444444444444444444094444444444449009444444444444444444449000000000000000000000000000033300
0b44444444444444444444b04444444444444444444444444444444409444444444444900944444444444444444444900000000000000000000000000033b330
04444444444444444444444044444444444444444444444444444444094444444444449004444444444444444444444000000000000000000000000003333300
09444444444444444444449044444444444444444444444444444444094444444444449002444444444444444444442000000000000000000000000000333330
094444444444444444444490444444224444442244444422444444220944442222444490002222222222222222222200000000000000000000000000033b3333
0bbbbbbbbbbbbbbbbbbbbbb044444444344444444444444334444443094444444444449009444443444444433444444434444443344444900000000033333300
bb3bb3bbbb3bb3bbbb3bb3bb44444444344444444444444334444443094444444444449009444443444444433444444434444443344444900000000000333300
b3233233332332333323323b44444444244444444444444224444442094444444444449009444442444444422444444424444442244444900000000003b33330
b3422422224224222242243b44444444444444444444444444444444094444444444449009444444444444444444444444444444444444900000000003333b33
0b44444444444444444444b044444444444444444444444444444444094444444444449009444444444444444444444444444444444444900000000033333330
04444444444444444444444044444444444444444444444444444444094444444444449004444444444444444444444444444444444444400000000000022000
09444444444444444444449044444444444444444444444444444444094444444444449002444444444444444444444444444444444444200000000000044000
09444422224444222244449022444422224444222244442222444422094444222244449000222222222222222222222222222222222222000000000000444400
__gff__
0200000000000000000000020202020200000000000000000000000202020202000000000000000000000000000000020000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
00000000000000000000000000000000000000000000000000000d0000001b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00202122000a0000000a000000000a000a000000000d00002f20212200301111320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007030800090000200622000020261116220000002022003f07030800090000090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00292a2b000900101403251200070800070800000029152121242a2b00091b0c090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000001a000029332b0000293511342b00000000070303080000003911113d002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0010120019000000001a000000001a001a00001b0020242a2a380d000000000000003f0d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001d000e0000000000002012000000000000000a00292b000017212200002021212121212200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001011111200002f00001a000b1d0d000000103c120000000007030800000703030303030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000d003f0000000020212200000a0000000a000000292a2b00000703232a13030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001b1c1d00202121212200103b2a2b001028001900271200001c000000000703080007030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0020212200291303232b000000000000001a0000001a00001021212200000703052104030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00292a380000292a3800000a000a001022001031120000000007030800000703030303030800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000001a000000001a00102b002912001a00001a0000000000292a2b0000292a2a2a2a2a2b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
