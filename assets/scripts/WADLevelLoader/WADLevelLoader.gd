extends Spatial

# 0.3(development release) - Godot 3 script for generate levels from WAD files
# originally created by Chaosus in 2017-2018
# MIT license

# EXPORTS

export(String, FILE) var WADPath = "e1m1.wad"

export(String) var LevelName = "E1M1"

export(int, "Map", "Geometry", "Overlay") var Mode = 0

export(SpatialMaterial) var DefaultWallMaterial = null

export(float) var Scale = 0.05

export(bool) var PrintDebugInfo = true

# CONSTANTS

const PIXELS_PER_UNIT = 64.0

const PIXELS_PER_FLAT = 64.0

const SHORT2FLOAT = 1.0 / PIXELS_PER_UNIT

const SKYTEXNAME = "F_SKY1"

const SHORTMAXVALUE = 32767

# I/O methods

func decode_32_as_string(file):
	var c1 = char(file.get_8())
	var c2 = char(file.get_8())
	var c3 = char(file.get_8())
	var c4 = char(file.get_8())
	return c1 + c2 + c3 + c4

func decode_64_as_string(file):
	var c1 = char(file.get_8())
	var c2 = char(file.get_8())
	var c3 = char(file.get_8())
	var c4 = char(file.get_8())
	var c5 = char(file.get_8())
	var c6 = char(file.get_8())
	var c7 = char(file.get_8())
	var c8 = char(file.get_8())
	return c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8

func read_lump(file):
	var lump = Lump.new()
	lump.offset = file.get_32()
	lump.size = file.get_32()
	lump.name = decode_64_as_string(file)
	return lump
 
# combine two bytes to short
func to_short(a, b):
	return wrapi((b << 8) | (a & 0xff), -32768, 32768)

# combine eight bytes to string
func combine_8_bytes_to_string(c1, c2, c3, c4, c5, c6, c7, c8):
	return char(c1) + char(c2) + char(c3) + char(c4) + char(c5) + char(c6) + char(c7) + char(c8)

# EXTRACTED TYPES

class Header:
	var type
	var lumpNum
	var dirOffset

class Lump:
	var offset
	var size
	var name

class Thing:
	var x
	var y
	var angle
	var type
	var options

# LINEDEF FLAGS
enum {
	LDF_IMPASSIBLE = 1,
	LDF_BLOCK_MONSTERS = 2,
	LDF_TWO_SIDED = 4
	LDF_UPPER_UNPEGGED = 8,
	LDF_LOWER_UNPEGGED = 16,
	LDF_SECRET = 32,
	LDF_BLOCK_SOUND = 64,
	LDF_NOT_ON_MAP = 128,
	LDF_ALREADY_ON_MAP = 256
}	

class Linedef:
	var start
	var end
	var flags
	var type
	var trigger
	var front
	var back

class Sidedef:
	var x_offset
	var y_offset
	var upper_texture
	var lower_texture
	var middle_texture
	var sector

class Vertex:
	var x
	var y
	func get_v2():
		return Vector2(x, y)
	
class Segment:
	var from
	var to
	var angle
	var linedef
	var direction
	var offset

class SubSector:
	var seg_num
	var seg_first

class Node:
	var x
	var y
	var dx
	var dy
	var y_upper_right
	var y_lower_right
	var x_lower_right
	var x_upper_right
	var y_upper_left
	var y_lower_left
	var x_lower_left
	var x_upper_left
	var node_right
	var node_left
	
class Sector:
	var floor_height
	var ceil_height
	var floor_texture
	var ceil_texture
	var light_level
	var special
	var tag

# Contains all extracted data
class Map:
	var things = []
	var linedefs = []
	var sidedefs = []
	var vertexes = []
	var segments = []
	var subsectors = []
	var nodes = []
	var sectors = []

# CUSTOM GEOMETRY TYPES

class Triangulation:
	var map
	func _init(p_map):
		map = p_map
		
	func get_sector_sidedefs(sector):
		var output = []
		for sd in map.sidedefs:
			if sd.sector == sector:
				output.append(sd)
		return output
		
	func get_sector_linedefs(sector):
		var output = []
		var sidedefs = get_sector_sidedefs(sector)
		
		for ld in map.linedefs:
			if sidedefs.has(ld.front) or sidedefs.has(ld.back):
				var fs = map.sidedefs[ld.front].sector
				var bs
				if ld.back != 0xFFFF:
					bs = map.sidedefs[ld.back].sector
				else:
					bs = -1
				if fs != bs:
					output.append(ld)
		
		return output
	
	func vertex_to_v2(vertex):
		return map.vertexes[vertex].get_v2()
	
	func line_angle(a, b):
		return atan2(b.y - a.y, b.x - a.x)
	
	func trace_lines(sector):
		var output = []
		var lines = get_sector_linedefs(sector)
		
		var i = 0
		var safe1 = 1000
		var safe2 = 1
		
		var vertex_lines = {}
		for l in lines:
			if not vertex_lines.has(l.start):
				vertex_lines[l.start] = 1
			else:
				vertex_lines[l.start] += 1
			
			if not vertex_lines.has(l.end):
				vertex_lines[l.end] = 1
			else:
				vertex_lines[l.end] += 1
				
		var found_unclosed_sector = 0
		
		for e in vertex_lines:
			if e < 2:
				found_unclosed_sector += 1
		
		if found_unclosed_sector > 0:
			print("unclosed_sector :", sector)
			return null
		
		while lines.size() > 0 && safe1 > 0:
			safe1-=1
			
			var trace = PoolIntArray()
			var line = lines[0]
			lines.remove(0)
			
			trace.append(line.start)
			var next = line.end
			
			safe2 = 1000
			while trace[0] != next && safe2 > 0:
				safe2-=1
				var connected_lines = PoolIntArray()
				var connected_line_front = PoolByteArray()
				for line in lines:
					if line.start == next:
						connected_lines.append(i)
						connected_line_front.append(1)
					elif line.end == next:
						connected_lines.append(i)
						connected_line_front.append(0)
				
				if connected_lines.size() == 1:
					trace.append(next)
					next = lines[connected_lines[0]].end if connected_line_front[0] == 1 else lines[connected_lines[0]].start
					lines.remove(abs(connected_lines[0]))
				else:
					var v1 = vertex_to_v2(trace[trace.size()-1])
					var v2 = vertex_to_v2(next)
					var point_index = lines[connected_lines[0]].end if connected_line_front[0] == 1 else lines[connected_lines[0]].start
					var v3 = vertex_to_v2(point_index)
					var min_angle = abs(line_angle(v1, v2) - line_angle(v3, v2))
					var min_index = 0
					i = 1
					for i in range(1, connected_lines.size()):
						point_index = lines[connected_lines[i]].end if connected_line_front[i] else lines[connected_lines[i]].start
						v3 = vertex_to_v2(point_index)
						var new_angle = abs(line_angle(v1, v2) - line_angle(v3, v2))
						if new_angle < min_angle:
							min_index = i
							min_angle = new_angle
						i+=1
					trace.append(next)
					next = lines[connected_lines[min_index]].end if connected_line_front[min_index] else lines[connected_lines[min_index]].start
					lines.remove(abs(connected_lines[min_index]))
			
			var v2_trace = PoolVector2Array()
			for v in trace:
				v2_trace.append(vertex_to_v2(v))
			
			output.append(v2_trace)
		
		if safe1 <= 0:
			print("first while loop exceeded limit!")
		if safe2 <= 0:
			print("second while loop exceeded limit! Sector: ", sector, " Lines left: ", lines.size())
		
		return output
		
	func triangulate(sector):
		var polygons = trace_lines(sector)
		
		if polygons == null:
			return null
		
		print("SUCCESS !")
		
		return polygons

# VARIABLES

var map = null
var map_material

# FUNCTIONS

# <almost_finished>
func load_wad(wad_path, level_name, mode):
	var buffer
	var i
	print("Opening %s" % wad_path + "...")
	
	var file = File.new() 
	if file.open(WADPath, File.READ) != OK:
		print("Failed to open WAD file %s" % wad_path)
		return
		
	if PrintDebugInfo:
		print("READING HEADER...")	
	var header = Header.new()  
	header.type = decode_32_as_string(file)
	header.lumpNum = file.get_32()
	header.dirOffset = file.get_32()
	
	if header.type != "IWAD" && header.type != "PWAD":
		print("ERROR: ",wad_path, "is not IWAD or PWAD !")
		return
	print(wad_path," is ", header.type)
	
	map = Map.new()
	
	if PrintDebugInfo:
		print("READING LUMPS...")
	
	var lump_mapname
	var lump_things
	var lump_linedefs
	var lump_sidedefs
	var lump_vertexes
	var lump_segs
	var lump_subsectors
	var lump_nodes
	var lump_sectors
	var lump_reject
	var lump_blockmap
	
	var breakAfter = false
	var lumps_readed = false
	var first = true
	file.seek(header.dirOffset)
	for i in range(header.lumpNum):
		if breakAfter && lumps_readed:
			break
		
		var lump = read_lump(file)
		if first:
			lump_mapname = lump
			first = false
		var name = lump.name
		#print(name)
		match lump.name:
			"THINGS":
				lump_things = lump
			"LINEDEFS":
				lump_linedefs = lump
			"SIDEDEFS":
				lump_sidedefs = lump
			"VERTEXES":
				lump_vertexes = lump
			"SEGS":
				lump_segs = lump
			"SSECTORS":
				lump_subsectors = lump
			"NODES":
				lump_nodes = lump
			"SECTORS":
				lump_sectors = lump
			"REJECT":
				lump_reject = lump
			"BLOCKMAP":
				lump_blockmap = lump
				if breakAfter:
					lumps_readed = true
			level_name:
				breakAfter = true
	if PrintDebugInfo:
		print("Internal map name: " + lump_mapname.name)
	
	if PrintDebugInfo:
		print("READING THINGS...")
	file.seek(lump_things.offset)
	buffer = file.get_buffer(lump_things.size)
	i = 0
	while i < buffer.size():
		var thing = Thing.new()
		thing.x = to_short(buffer[i], buffer[i+1])
		thing.y = to_short(buffer[i+2], buffer[i+3])
		thing.angle = to_short(buffer[i+4], buffer[i+5])
		thing.type = to_short(buffer[i+6], buffer[i+7])
		thing.options = to_short(buffer[i+8], buffer[i+9])
		map.things.push_back(thing)
		i+=10
		
	if PrintDebugInfo:
		print("READING LINEDEFS...")
	file.seek(lump_linedefs.offset)
	buffer = file.get_buffer(lump_linedefs.size)
	i = 0
	while i < buffer.size():
		var linedef = Linedef.new()
		linedef.start = to_short(buffer[i],buffer[i+1])
		linedef.end = to_short(buffer[i+2],buffer[i+3])
		linedef.flags = to_short(buffer[i+4],buffer[i+5])
		linedef.type = to_short(buffer[i+6],buffer[i+7])
		linedef.trigger = to_short(buffer[i+8],buffer[i+9])
		linedef.front = to_short(buffer[i+10],buffer[i+11])
		linedef.back = to_short(buffer[i+12],buffer[i+13])
		map.linedefs.push_back(linedef)
		i+=14
	
	if PrintDebugInfo:
		print("READING SIDEDEFS...")
	file.seek(lump_sidedefs.offset)
	buffer = file.get_buffer(lump_sidedefs.size)
	i = 0
	while i < buffer.size():
		var sidedef = Sidedef.new()
		sidedef.x_offset = to_short(buffer[i], buffer[i+1])
		sidedef.y_offset = to_short(buffer[i+2], buffer[i+3])
		sidedef.upper_texture = combine_8_bytes_to_string(buffer[i+4], buffer[i+5], buffer[i+6], buffer[i+7], buffer[i+8], buffer[i+9], buffer[i+10], buffer[i+11])
		sidedef.lower_texture = combine_8_bytes_to_string(buffer[i+12], buffer[i+13], buffer[i+14], buffer[i+15], buffer[i+16], buffer[i+17], buffer[i+18], buffer[i+19])
		sidedef.middle_texture = combine_8_bytes_to_string(buffer[i+20], buffer[i+21], buffer[i+22], buffer[i+23], buffer[i+24], buffer[i+25], buffer[i+26], buffer[i+27])
		sidedef.sector = to_short(buffer[i+28], buffer[i+29])
		map.sidedefs.push_back(sidedef)
		i+=30
		
	if PrintDebugInfo:
		print("READING VERTEXES...")
	file.seek(lump_vertexes.offset)
	buffer = file.get_buffer(lump_vertexes.size)
	i = 0
	while i < buffer.size():
		var x = to_short(buffer[i], buffer[i+1]) * Scale
		var y = to_short(buffer[i+2], buffer[i+3]) * Scale
		var vertex = Vertex.new()
		vertex.x = float(x)
		vertex.y = float(y)	
		map.vertexes.push_back(vertex)
		i+=4
	
	if PrintDebugInfo:
		print("READING SUB-SECTORS...")
	file.seek(lump_subsectors.offset)
	buffer = file.get_buffer(lump_subsectors.size)
	i = 0
	while i < buffer.size():
		var subsector = SubSector.new()
		subsector.seg_num = to_short(buffer[i],buffer[i+1])
		subsector.seg_first = to_short(buffer[i+2],buffer[i+3])
		map.subsectors.push_back(subsector)
		i+=4
	
	if PrintDebugInfo:
		print("READING NODES...")
	file.seek(lump_nodes.offset)
	buffer = file.get_buffer(lump_nodes.size)
	i = 0
	while i < buffer.size():
		var node = Node.new()
		node.x = to_short(buffer[i],buffer[i+1])
		node.y = to_short(buffer[i+2],buffer[i+3])
		node.dx = to_short(buffer[i+4],buffer[i+5])
		node.dy = to_short(buffer[i+6],buffer[i+7])		
		node.y_upper_right = to_short(buffer[i+8],buffer[i+9])
		node.y_lower_right = to_short(buffer[i+10],buffer[i+11])
		node.x_lower_right = to_short(buffer[i+12],buffer[i+13])
		node.x_upper_right = to_short(buffer[i+14],buffer[i+15])
		node.y_upper_left = to_short(buffer[i+16],buffer[i+17])
		node.y_lower_left = to_short(buffer[i+18],buffer[i+19])
		node.x_lower_left = to_short(buffer[i+20],buffer[i+21])
		node.x_upper_left = to_short(buffer[i+22],buffer[i+23])
		node.node_right = to_short(buffer[i+24],buffer[i+25])
		node.node_left = to_short(buffer[i+26],buffer[i+27])
		map.nodes.push_back(node)
		i+=28
	
	if PrintDebugInfo:
		print("READING SECTORS...")
	file.seek(lump_sectors.offset)
	buffer = file.get_buffer(lump_sectors.size)
	i = 0
	while i < buffer.size():
		var sector = Sector.new()
		sector.floor_height = to_short(buffer[i],buffer[i+1])
		sector.ceil_height = to_short(buffer[i+2],buffer[i+3])
		sector.floor_texture = combine_8_bytes_to_string(buffer[i+4], buffer[i+5], buffer[i+6], buffer[i+7], buffer[i+8], buffer[i+9], buffer[i+10], buffer[i+11])
		sector.ceil_texture = combine_8_bytes_to_string(buffer[i+12], buffer[i+13], buffer[i+14], buffer[i+15], buffer[i+16], buffer[i+17], buffer[i+18], buffer[i+19])
		sector.light_level = to_short(buffer[i+20], buffer[i+21])
		sector.special = to_short(buffer[i+22], buffer[i+23])
		sector.tag = to_short(buffer[i+24], buffer[i+25])
		map.sectors.push_back(sector)
		i+=26
	file.close()
	
	if PrintDebugInfo:
		print("BUILDING GEOMETRY")
	
	map_material = SpatialMaterial.new()
	map_material.flags_unshaded = true
	map_material.flags_vertex_lighting = true
	map_material.vertex_color_use_as_albedo = true
	
	match mode:
		0:
			build_map_geometry()
		1:
			build_level_geometry()
		2:
			build_map_geometry()
			build_level_geometry()
				
#	if mode == 1 or mode == 2: # Geometry mode or Overlay mode	
#		var polycount = polygons.size()
#		for sector in sectors:
#			var geometry = ImmediateGeometry.new()
#			geometry.material_override = DefaultWallMaterial
#			for s in sector.faceset_floor.segments:
#				geometry.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
#				geometry.set_color(Color(1,1,1))
#				var height = sector.floor_height / 3 # (sector.ceil_height - sector.floor_height) / 10
#				geometry.set_uv(Vector2(0,0))
#				geometry.add_vertex(Vector3(s.v1.x, 0, s.v1.y))
#				geometry.set_uv(Vector2(1,0))
#				geometry.add_vertex(Vector3(s.v2.x, 0, s.v2.y))
#				geometry.set_uv(Vector2(0,1))
#				geometry.add_vertex(Vector3(s.v1.x, height, s.v1.y))			
#				geometry.set_uv(Vector2(1,1))
#				geometry.add_vertex(Vector3(s.v2.x, height, s.v2.y))
#				geometry.end()		
#			add_child(geometry)


class SectorPolygon:
	var points = []
	var triangles = []
	
	func get_offset_triangles(offset):
		var output = []
		for t in triangles:
			output.append(t + offset)
		return output
	
	func points_to_v3(z):
		var vectors = []
		for p in points:
			vectors.append(Vector3(p.x, z, p.y))
		return vectors

# <unfinished>
func build_level_geometry():
	for i in range(map.sectors.size()):	
		var st = Triangulation.new(map)
		st.triangulate(i)
		
# <unfinished>
func create_material(texture_name, is_transparent):
	var material = SpatialMaterial.new()
	return material

# <almost_finished>
func build_map_geometry():
	var i = 0
	var map_spatial = Spatial.new()
	map_spatial.name = "Map"
	add_child(map_spatial)
	for ld in map.linedefs:
		var v1 = ld.start
		var v2 = ld.end
		
		var vertex1 = map.vertexes[v1]
		var vertex2 = map.vertexes[v2]
		var geometry = ImmediateGeometry.new()
		geometry.name = "mapline_" + str(i) 
		geometry.material_override = map_material
		geometry.begin(Mesh.PRIMITIVE_LINES)
		if ld.type != 0:
			geometry.set_color(ColorN("yellow"))
		else:
			geometry.set_color(ColorN("red"))
		geometry.add_vertex(Vector3(vertex1.x, 0, vertex1.y))
		geometry.add_vertex(Vector3(vertex2.x, 0, vertex2.y))
		geometry.end()			
		map_spatial.add_child(geometry)
		i+=1
func _ready():	
	load_wad(WADPath, LevelName, Mode)