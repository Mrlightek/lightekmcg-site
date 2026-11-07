"""Trusted Studio bridge loaded explicitly after an untrusted .blend opens.

Native file scripts stay disabled. Blender's full editors remain available
inside the isolated workstation, whose only persistent mount is its own work.
"""
import bpy
import hashlib
import json
import os
import tempfile
import zipfile

WORK = '/work'
if os.environ.get('LIGHTEK_WORKSTATION_TEST_ROOT'):
    WORK = os.environ['LIGHTEK_WORKSTATION_TEST_ROOT']
SOURCE = os.path.join(WORK, 'scene.blend')


def save_session():
    with open(os.path.join(WORK, '.studio-save-request.json'), encoding='utf-8') as stream:
        nonce = json.load(stream)['nonce']
    if not isinstance(nonce, str) or len(nonce) != 16 or any(c not in '0123456789abcdef' for c in nonce):
        raise ValueError('Invalid Studio save receipt')
    # Pack assets supported by Blender packing; dependency files that remain
    # external stay in the session's /work tree for the importer.
    bpy.ops.file.pack_all()
    if bpy.data.libraries:
        bpy.ops.file.pack_libraries()
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE, check_existing=False, compress=True)
    digest = hashlib.sha256()
    with open(SOURCE, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''): digest.update(chunk)
    bundle = os.path.join(WORK, 'project.zip')
    fd, temporary_bundle = tempfile.mkstemp(prefix='.bundle-', dir=WORK)
    os.close(fd)
    total = 0; count = 0
    excluded = {'project.zip','manifest.json','render_result.json','blender.log','native-source.blend','native-bundle.zip'}
    try:
        with zipfile.ZipFile(temporary_bundle, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for directory, folders, files in os.walk(WORK, followlinks=False):
                folders[:] = [f for f in folders if not f.startswith('.') and not os.path.islink(os.path.join(directory,f))]
                for name in files:
                    path = os.path.join(directory,name)
                    if name.startswith('.') or name in excluded or name.endswith(('.blend1','.blend2')): continue
                    if os.path.islink(path): raise ValueError('Session resource contains a symbolic link')
                    total += os.path.getsize(path); count += 1
                    if total > 2*1024**3 or count > 10000: raise ValueError('Native package exceeds the resource archive limit')
                    archive.write(path,os.path.relpath(path,WORK))
        os.replace(temporary_bundle,bundle)
    finally:
        if os.path.exists(temporary_bundle): os.unlink(temporary_bundle)
    bundle_digest = hashlib.sha256()
    with open(bundle, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''): bundle_digest.update(chunk)
    path = os.path.join(WORK, '.studio-save-receipt.json')
    fd, temporary = tempfile.mkstemp(prefix='.receipt-', dir=WORK)
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump({'nonce': nonce, 'sha256': digest.hexdigest(), 'blender_version': bpy.app.version_string, 'bundle_sha256': bundle_digest.hexdigest(), 'workspace': bpy.context.window.workspace.name if bpy.context.window else None}, stream)
    os.replace(temporary, path)


class LIGHTEK_OT_save_session(bpy.types.Operator):
    bl_idname = 'wm.lightek_save_session'
    bl_label = 'Save to Lightek Studio'
    bl_description = 'Save the complete native project for Studio Library and rendering'
    def execute(self, context):
        try:
            request_path = os.path.join(WORK, '.studio-workspace-request.json')
            if os.path.isfile(request_path):
                with open(request_path, encoding='utf-8') as stream: request = json.load(stream)
                os.unlink(request_path)
                if request.get('task') not in WORKSPACES: raise ValueError('Invalid production workspace')
                bpy.ops.wm.lightek_workspace(task=request['task'])
                # Workspace changes are applied by Blender's next UI event
                # cycle. A receipt from this operator would report the old one.
                window = context.window
                def confirm_workspace():
                    with open(os.path.join(WORK, '.studio-workspace-receipt.json'), 'w', encoding='utf-8') as stream:
                        json.dump({'task':request['task'],'workspace':window.workspace.name}, stream)
                    return None
                bpy.app.timers.register(confirm_workspace, first_interval=0.25)
                return {'FINISHED'}
            save_session()
            self.report({'INFO'}, 'Native project saved for Lightek Studio')
            return {'FINISHED'}
        except Exception as error:
            self.report({'ERROR'}, str(error))
            return {'CANCELLED'}


WORKSPACES = {
    'layout': ('Studio · Layout', 'VIEW_3D'),
    'model': ('Modeling', 'VIEW_3D'),
    'sculpt': ('Sculpting', 'VIEW_3D'),
    'uv': ('UV Editing', 'IMAGE_EDITOR'),
    'animate': ('Animation', 'DOPESHEET_EDITOR'),
    'shade': ('Shading', 'NODE_EDITOR'),
    'geometry': ('Geometry Nodes', 'NODE_EDITOR'),
    'composite': ('Compositing', 'NODE_EDITOR'),
    'sequence': ('Video Editing', 'SEQUENCE_EDITOR'),
    'render': ('Rendering', 'IMAGE_EDITOR'),
}


class LIGHTEK_OT_workspace(bpy.types.Operator):
    bl_idname = 'wm.lightek_workspace'
    bl_label = 'Lightek production workspace'
    task: bpy.props.StringProperty()
    def execute(self, context):
        name, editor = WORKSPACES[self.task]
        workspace = bpy.data.workspaces.get(name)
        if workspace:
            context.window.workspace = workspace
        else:
            # Imported .blend files can contain only a custom screen. Keep it
            # and switch its largest area to the requested native editor.
            area = max(context.window.screen.areas, key=lambda a:a.width*a.height)
            area.type = editor
            if editor == 'NODE_EDITOR':
                area.spaces.active.tree_type = {'geometry':'GeometryNodeTree','composite':'CompositorNodeTree'}.get(self.task,'ShaderNodeTree')
            if editor == 'IMAGE_EDITOR' and self.task == 'uv': area.ui_type = 'UV'
        return {'FINISHED'}


class LIGHTEK_PT_studio(bpy.types.Panel):
    bl_label = 'Lightek Production Studio'
    bl_idname = 'LIGHTEK_PT_studio'
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'Lightek'
    def draw(self, context):
        self.layout.label(text='Full native authoring')
        self.layout.operator('wm.lightek_save_session', icon='FILE_TICK')
        self.layout.label(text='Return to Studio to import your saved version.')


def register():
    bpy.context.preferences.filepaths.use_scripts_auto_execute = False
    bpy.context.preferences.view.show_splash = False
    for cls in (LIGHTEK_OT_save_session, LIGHTEK_OT_workspace, LIGHTEK_PT_studio):
        bpy.utils.register_class(cls)
    keymap = bpy.context.window_manager.keyconfigs.addon
    if keymap:
        mapping = keymap.keymaps.new(name='Window', space_type='EMPTY')
        mapping.keymap_items.new('wm.lightek_save_session', 'F8', 'PRESS')
        for task,key in zip(WORKSPACES,('ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','ZERO')):
            item=mapping.keymap_items.new('wm.lightek_workspace',key,'PRESS',ctrl=True,alt=True)
            item.properties.task=task
    # Put Blender's standard production workspaces one click away. We retain
    # imported screens/workspaces rather than replacing their data.
    for workspace in bpy.data.workspaces:
        if workspace.name == 'Layout': workspace.name = 'Studio · Layout'


register()
