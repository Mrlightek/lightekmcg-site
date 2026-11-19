"""Original profile drawings share the source rig; physical geometry stays separate."""
import bpy
import math
from mathutils import Matrix, Vector

def build(rig):
    scene=bpy.context.scene
    originals=[obj for obj in scene.objects if obj.type=='MESH']
    for original in originals:
        original['lightek_view']='front'
        if original.name in ('FaceEyes','FaceBrows','Shirt'):continue
        side=original.copy();side.data=original.data.copy();side.name='Side '+original.name;scene.collection.objects.link(side)
        ratio=.55 if original.name=='Jacket body' else .8 if original.name in ('Head','Hair cap') else 1
        matrix=original.matrix_world.copy() @ Matrix.Rotation(-math.pi/2,4,'Z') @ Matrix.Diagonal((ratio,1,1,1))
        if original.name=='FaceMouth':
            if side.data.shape_keys:
                for key in side.data.shape_keys.key_blocks:
                    for point in key.data:point.co.y=0
            for vertex in side.data.vertices:vertex.co.y=0
            matrix=Matrix.Translation(Vector((-.12,-.23,0))) @ Matrix.Rotation(-math.pi/2,4,'Z') @ Matrix.Diagonal((.55,1,1,1))
            side['lightek_mirror_source']='FaceMouth'
        if original.name in ('Head','Nose','Close cut','High top','Hair cap'):matrix.translation.x=-.06
        if original.name.startswith(('Boot ','Hand ')):
            side.parent=original;side.parent_type='OBJECT';side.parent_bone=''
        if len(side.data.polygons)==2:side.data.polygons[1].material_index=0
        side.matrix_world=matrix;side['lightek_view']='side';side.hide_render=True;side.hide_viewport=True
    def ellipse(name,location,width,height,material,control=None,source=None):
        points=[(0,width*math.cos(i*math.tau/32),height*math.sin(i*math.tau/32)) for i in range(32)]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(points,[],[list(range(32))]);mesh.materials.append(bpy.data.materials[material])
        obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj);obj.location=location
        if control:
            obj.shape_key_add(name='Basis');key=obj.shape_key_add(name=control)
            for point in key.data:
                if control=='blink':point.co.z*=.05
                else:point.co.z+=.045
            obj['lightek_mirror_source']=source
        bpy.context.view_layer.update();world=obj.matrix_world.copy();obj.parent=rig;obj.parent_type='BONE';obj.parent_bone='Head';bpy.context.view_layer.update();obj.matrix_world=world
        obj['lightek_view']='side';obj.hide_render=True;obj.hide_viewport=True
    # Use the actual material identities rather than hardcoded palette values.
    def material_of(name):return bpy.data.objects[name].data.materials[0].name
    eye=bpy.data.objects['FaceEyes'];white=next(mat.name for mat in eye.data.materials if 'white' in mat.name.lower())
    black=material_of('FaceMouth');hair=material_of('Brow') if 'Brow' in bpy.data.objects else bpy.data.objects['FaceBrows'].data.materials[0].name
    ellipse('Side eye',(-.14,-.16,1.99),.065,.055,white,'blink','FaceEyes')
    ellipse('Side pupil',(-.145,-.19,1.99),.025,.038,black,'blink','FaceEyes')
    ellipse('Side brow',(-.15,-.16,2.08),.075,.012,hair,'brow_raise','FaceBrows')

    # Both side directions need an eye/mouth on the camera-facing surface.
    for name in ('Side eye','Side pupil','Side brow','Side FaceMouth'):
        original=bpy.data.objects[name];obj=original.copy();obj.data=original.data.copy();obj.name=name+' reverse';scene.collection.objects.link(obj)
        matrix=original.matrix_world.copy();matrix.translation.x=-matrix.translation.x;obj.matrix_world=matrix
