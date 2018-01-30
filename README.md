# GDWadLevelLoader
WAD level loader-script(from DOOM-alike games) for Godot.

# Current version
v0.2 - some improvements for future development..

# Previous versions
v0.1 - present simple line mesh of level without any details, floor height or textures. In future I will add walls, floors, and maybe texture loading support. 

# How to use
This is very simple - push your WAD file into main directory of your project, create Spatial and attach WADLevelLoader.gd to it, push the path to WAD file into <b>Wad path</b> parameter, if the WAD have multiple levels you can target specific in <b>Level Name</b> parameter, if the result is too large - control the scale using <b>Scale</b> parameter. 

# Misc
You can test current version with e1m1.wad from Freedoom project(included).
