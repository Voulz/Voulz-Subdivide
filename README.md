# Voulz-Subdivide
Sketchup Plugin to triangulate and subdivide faces. Can be used to subdivide until reaching a maximum edge length or to subdivide a certain number of times.

# Usage
Select Faces and Groups/Components and run the plugin through `Extensions > Vouz > Subdivide`

You are then prompt to enter a number.
- Enter a positive number to subdivide the selected faces based on a maximum edge length (ex: 12.5)
- Enter a negative number to subdivide the selected faces a fixed number of times (ex: -2 will subdivide all the faces 2 times)
- Enter 0 to just Triangulate the selected faces

Press Enter once to update the preview and press Enter again to actually process the algorithm.

# API
When the Plugin is loaded, you can access its public functions in the namespace `Voulz::Plugins::VoulzSubdivide`

The first set of functions are used for the preview of the algorithm, not making an actual change in the model:
```ruby
# Triangulate the given entities.
# This version will output an Array of Faces, each Face being an array of Triangles, each Triangle being an array of Point3d
# @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
# @param [ Geom::Transformation | nil ] tr The transformation of the current entities
# @return [ Array<Array<Array<Point3d>>> ] Triangles
def triangulate_to_a(entities, tr = nil)

# Triangulate and then subdivide entities the given number of times, independantly of their size
# This version will output an Array of Faces, each Face being an array of Triangles, each Triangle being an array of Point3d
# @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
# @param [ Fiznum ] nbtimes The number of times the entities will need to be subdivided
# @param [ Geom::Transformation | nil ] tr The transformation of the current entities
def subdivide_to_a(entities, nbtimes, tr = nil)

# Triangulate and then subdivide entities until each edge of each triangle has a maximum length of max_length.
# This version will output an Array of Faces, each Face being an array of Triangles, each Triangle being an array of Point3d
# @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
# @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
# @param [ Geom::Transformation | nil ] tr The transformation of the current entities
def subdivide_length_to_a(entities, max_length, tr = nil)


# Subdivide the face a given number of times, independantly of their size
# This version will output an Array Triangles, each Triangle being an array of Point3d
# @param [ Sketchup::Point3d ] p1
# @param [ Sketchup::Point3d ] p2
# @param [ Sketchup::Point3d ] p3
# @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
def subdivide_face_to_a(p1, p2, p3, nbtimes)

# Subdivide a triangle until each edge has a maximum length of max_length.
# This version will output an Array Triangles, each Triangle being an array of Point3d
# @param [ Sketchup::Point3d ] p1
# @param [ Sketchup::Point3d ] p2
# @param [ Sketchup::Point3d ] p3
# @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
def subdivide_length_face_to_a(p1, p2, p3, max_length)
```

The second set of functions are working on an existing mesh. It is advised to wrap these in an operation.
```ruby
# Triangulate the given entities.
# WRAP IN AN OPERATION !
# This version will directly triangulate the given entities
# @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
def triangulate!(entities)

# Triangulate and then subdivide entities the given number of times, independantly of their size
# WRAP IN AN OPERATION !
# This version will directly triangulate the given entities
# @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
# @param [ Fiznum ] nbtimes The number of times the entities will need to be subdivided
def subdivide_face!(entities, nbtimes)

# Triangulate and then subdivide entities until each edge of each triangle has a maximum length of max_length.
# @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
# @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
def subdivide_length_face!(entities, max_length)


# Subdivide the face a given number of times, independantly of their size
# @param [ Sketchup::Point3d ] p1
# @param [ Sketchup::Point3d ] p2
# @param [ Sketchup::Point3d ] p3
# @param [ Sketchup::Point3d ] uv1 Front UV of p1
# @param [ Sketchup::Point3d ] uv2 Front UV of p2
# @param [ Sketchup::Point3d ] uv3 Front UV of p3
# @param [ Sketchup::Point3d ] uv1 Back UV of p1
# @param [ Sketchup::Point3d ] uv2 Back UV of p2
# @param [ Sketchup::Point3d ] uv3 Back UV of p3
# @param [ Fiznum ] nbtimes The number of times the entities will need to be subdivided
def subdivide_mesh_face(mesh, p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3, nbtimes)

# Subdivide a triangle until each edge has a maximum length of max_length.
# @param [ Sketchup::Point3d ] p1
# @param [ Sketchup::Point3d ] p2
# @param [ Sketchup::Point3d ] p3
# @param [ Sketchup::Point3d ] uv1 Front UV of p1
# @param [ Sketchup::Point3d ] uv2 Front UV of p2
# @param [ Sketchup::Point3d ] uv3 Front UV of p3
# @param [ Sketchup::Point3d ] uv1 Back UV of p1
# @param [ Sketchup::Point3d ] uv2 Back UV of p2
# @param [ Sketchup::Point3d ] uv3 Back UV of p3
# @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
def subdivide_length_mesh_face(mesh, p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3, max_length)
```
# Known Bugs and Limitations

Passed tests:
- faces with textures ✔
- faces with hidden edges ✔
- faces with smooth edges ✔
- faces with soft edges ✔
- groups (it only affects the ones visible) ✔
- component (it only affects the ones visible) ✔
- locked entities ✔
- clean geometry ✔

Bugs:
- If the textures are distorted (perspective like), the distortion is lost in the subdivided mesh and the texture might be mapped differently. This is due to the way Sketchup handles the UVs of faces. There might be workarounds.

Limitations:
- Not all the new elements are added to the selection
- For now, all the new triangle edges are visible but it should be prompted to the user if they should be hidden, smoothed and soften.