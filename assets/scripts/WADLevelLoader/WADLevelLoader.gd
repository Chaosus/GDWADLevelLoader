extends Spatial

# v0.2.1 - Godot 3 script for generate levels from WAD files
# originally created by Chaosus in 2017-2018
# MIT license

# If you want to extend this script for your purposes, read
# http://www.gamers.org/dhs/helpdocs/dmsp1666.html

export(String) var WADPath = "e1m1.wad"

export(String) var LevelName = "E1M1"

export(float) var Scale = 0.05

export(bool) var PrintDebugInfo = true

var SurfaceMaterial

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

class Linedef:
	var start_vertex
	var end_vertex
	var flags
	var type
	var trigger
	var right_sidedef
	var left_sidedef

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
	
class Segment:
	var from
	var to
	var angle
	var linedef
	var direction
	var offset

class SubSector:
	var seg_count
	var seg_num

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

func load_wad(wad_path, level_name):
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
	
	print(wad_path," is ", header.type)
	
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
	
	var first = true
	var breakAfter = false
	file.seek(header.dirOffset)
	for i in range(header.lumpNum):
		var lump = read_lump(file)
		if first:
			lump_mapname = lump
			first = false
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
					break
			level_name:
				breakAfter = true
	if PrintDebugInfo:
		print("Internal map name: " + lump_mapname.name)
	
	if PrintDebugInfo:
		print("READING THINGS...")
	file.seek(lump_things.offset)
	var things = []
	buffer = file.get_buffer(lump_things.size)
	i = 0
	while i < buffer.size():
		var thing = Thing.new()
		thing.x = to_short(buffer[i], buffer[i+1])
		thing.y = to_short(buffer[i+2], buffer[i+3])
		thing.angle = to_short(buffer[i+4], buffer[i+5])
		thing.type = to_short(buffer[i+6], buffer[i+7])
		thing.options = to_short(buffer[i+8], buffer[i+9])
		things.push_back(thing)
		i+=10
		
	if PrintDebugInfo:
		print("READING LINEDEFS...")
	file.seek(lump_linedefs.offset)
	var linedefs = []
	buffer = file.get_buffer(lump_linedefs.size)
	i = 0
	while i < buffer.size():
		var linedef = Linedef.new()
		linedef.start_vertex = to_short(buffer[i],buffer[i+1])
		linedef.end_vertex = to_short(buffer[i+2],buffer[i+3])
		linedef.flags = to_short(buffer[i+4],buffer[i+5])
		linedef.type = to_short(buffer[i+6],buffer[i+7])
		linedef.trigger = to_short(buffer[i+8],buffer[i+9])
		linedef.right_sidedef = to_short(buffer[i+10],buffer[i+11])
		linedef.left_sidedef = to_short(buffer[i+12],buffer[i+13])
		linedefs.push_back(linedef)
		i+=14
	
	if PrintDebugInfo:
		print("READING SIDEDEFS...")
	file.seek(lump_sidedefs.offset)
	var sidedefs = []
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
		sidedefs.push_back(sidedef)
		i+=30
		
	if PrintDebugInfo:
		print("READING VERTEXES...")
	file.seek(lump_vertexes.offset)
	var vertexes = []
	buffer = file.get_buffer(lump_vertexes.size)
	i = 0
	while i < buffer.size():
		var x = to_short(buffer[i], buffer[i+1]) * Scale
		var y = to_short(buffer[i+2], buffer[i+3]) * Scale
		var vertex = Vertex.new()
		vertex.x = float(x)
		vertex.y = float(y)	
		vertexes.push_back(vertex)
		i+=4
	
	if PrintDebugInfo:
		print("READING SUB-SECTORS...")
	file.seek(lump_subsectors.offset)
	var sub_sectors = []
	buffer = file.get_buffer(lump_subsectors.size)
	i = 0
	while i < buffer.size():
		var subsector = SubSector.new()
		subsector.seg_count = to_short(buffer[i],buffer[i+1])
		subsector.seg_num = to_short(buffer[i+2],buffer[i+3])
		sub_sectors.push_back(subsector)
		i+=4
	
	if PrintDebugInfo:
		print("READING NODES...")
	file.seek(lump_nodes.offset)
	var nodes = []
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
		nodes.push_back(node)
		i+=28
	
	if PrintDebugInfo:
		print("READING SECTORS...")
	file.seek(lump_sectors.offset)
	var sectors = []
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
		sectors.push_back(sector)
		i+=26
	file.close()
	
	if PrintDebugInfo:
		print("BUILDING GEOMETRY")
	for ld in linedefs:
		var vertex1 = vertexes[ld.start_vertex]
		var vertex2 = vertexes[ld.end_vertex]
		var geometry = ImmediateGeometry.new()
		geometry.material_override = SurfaceMaterial
		geometry.begin(Mesh.PRIMITIVE_LINES)
		if ld.type != 0:
			geometry.set_color(Color(1,1,0))
		else:
			geometry.set_color(Color(1,0,0))
		geometry.add_vertex(Vector3(vertex1.x,0,vertex1.y))
		geometry.add_vertex(Vector3(vertex2.x,0,vertex2.y))
		geometry.end()
		add_child(geometry)
	
func _ready():
	
	if SurfaceMaterial == null:
		SurfaceMaterial = SpatialMaterial.new()
		SurfaceMaterial.flags_unshaded = true
		SurfaceMaterial.flags_vertex_lighting = true
		SurfaceMaterial.vertex_color_use_as_albedo = true
		
	load_wad(WADPath, LevelName)
