import bpy
import json
import os

JSON_PATH = "C:/path/to/blender_manifest.json"  # <-- Update this path

def create_cyan_emission_material(name="M_Luminara_Glow"):
    """Creates a procedural cyan glowing material with emissive properties."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]

    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    # Clear default nodes
    nodes.clear()

    # Create Material Output and Emission Nodes
    output_node = nodes.new(type='ShaderNodeOutputMaterial')
    output_node.location = (400, 0)

    emission_node = nodes.new(type='ShaderNodeEmission')
    emission_node.location = (100, 0)
    
    # Set Color to Luminara Cyan (R: 0.0, G: 0.8, B: 1.0)
    emission_node.inputs['Color'].default_value = (0.0, 0.8, 1.0, 1.0)
    emission_node.inputs['Strength'].default_value = 12.0  # Bright glowing effect

    # Link Emission to Material Output
    links.new(emission_node.outputs['Emission'], output_node.inputs['Surface'])
    
    return mat

def create_base_material(name, color_rgba):
    """Creates a basic Principled BSDF material for set primitives."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]

    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs['Base Color'].default_value = color_rgba
    return mat

def build_scene_from_manifest(filepath):
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return

    with open(filepath, 'r') as f:
        data = json.load(f)

    scene = bpy.context.scene
    scene.name = data['scene_info']['name']

    # Pre-build key production materials
    glow_mat = create_cyan_emission_material("M_Luminara_Glow")
    metal_mat = create_base_material("M_Scrap_Metal", (0.15, 0.15, 0.18, 1.0))
    stone_mat = create_base_material("M_Ashgray_Stone", (0.05, 0.05, 0.06, 1.0))

    # Spawn and Materialize Nodes
    for node in data.get('blender_nodes', []):
        name = node.get('name', 'Object')
        loc = node.get('location', [0, 0, 0])

        if node['type'] == 'CAMERA':
            cam_data = bpy.data.cameras.new(name=name)
            cam_obj = bpy.data.objects.new(name, cam_data)
            cam_obj.location = loc
            cam_obj.rotation_euler = node.get('rotation', [0, 0, 0])
            scene.collection.objects.link(cam_obj)
            scene.camera = cam_obj

        elif node['type'] == 'LIGHT':
            light_data = bpy.data.lights.new(name=name, type=node.get('light_type', 'POINT'))
            
            # Check for bioluminescent lighting directives
            if "cyan" in data['environment_setup']['lighting_style'].lower() or "bioluminescence" in data['environment_setup']['lighting_style'].lower():
                light_data.color = (0.0, 0.8, 1.0)
                light_data.energy = node.get('energy', 1500)
            else:
                light_data.energy = node.get('energy', 500)

            light_obj = bpy.data.objects.new(name, light_data)
            light_obj.location = loc
            scene.collection.objects.link(light_obj)

        elif node['type'] == 'MESH':
            prim = node.get('primitive', 'CUBE')
            if prim == 'CUBE':
                bpy.ops.mesh.primitive_cube_add(location=loc)
            elif prim == 'CYLINDER':
                bpy.ops.mesh.primitive_cylinder_add(location=loc)
            
            obj = bpy.context.active_object
            obj.name = name

            # Assign materials based on object context
            if "conduit" in name.lower() or "pipe" in name.lower():
                obj.data.materials.append(metal_mat)
                # Assign glowing core to conduits
                obj.data.materials.append(glow_mat)
            else:
                obj.data.materials.append(stone_mat)

    # Add Dialogue Markers to Timeline
    fps = scene.render.fps
    frame_offset = fps * 2

    for i, line in enumerate(data.get('script_data', [])):
        target_frame = (i + 1) * frame_offset
        marker_text = f"{line['speaker']}: [{line['emotion']}] {line['text'][:20]}..."
        scene.timeline_markers.new(name=marker_text, frame=target_frame)

    print(f"Scene setup complete with materials assigned for: {data['scene_info']['name']}")

#JSON_PATH = "C:/path/to/blender_manifest.json"  # Update path

def apply_camera_shake(camera_obj, start_frame, shake_info):
    """Applies programmatic noise modifiers to the camera to mimic camera shake."""
    intensity = shake_info.get('intensity', 0.0)
    if intensity <= 0:
        return

    if not camera_obj.animation_data:
        camera_obj.animation_data_create()
    
    if not camera_obj.animation_data.action:
        camera_obj.animation_data.action = bpy.data.actions.new(name="CameraShakeAction")

    action = camera_obj.animation_data.action

    # Add keyframes on X, Y, Z locations to establish curves
    for axis_idx in range(3):
        fcurve = action.fcurves.find('location', index=axis_idx)
        if not fcurve:
            fcurve = action.fcurves.new(data_path='location', index=axis_idx)
        
        # Insert noise modifier for dynamic motion
        mod = fcurve.modifiers.new(type='NOISE')
        mod.strength = intensity
        mod.scale = shake_info.get('noise_scale', 0.2)
        mod.frame_start = start_frame
        mod.frame_end = start_frame + 48  # Shake for 2 seconds

def build_animation_from_manifest(filepath):
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return

    with open(filepath, 'r') as f:
        data = json.load(f)

    scene = bpy.context.scene
    camera = scene.camera

    for line in data.get('script_data', []):
        start_frame = line['start_frame']

        # 1. Apply Camera Shake per action beat
        if camera and 'shake_data' in line:
            apply_camera_shake(camera, start_frame, line['shake_data'])

        # 2. Keyframe Dialogue Phonemes onto Timeline Markers
        for p in line.get('phonemes', []):
            f_num = p['frame']
            shape_tag = p['shape']
            # Places viseme cues directly as timeline sub-markers
            scene.timeline_markers.new(name=f"{line['speaker']}:{shape_tag}", frame=f_num)

    print("Phonemes and camera shake modifiers successfully keyframed!")

# Execute animation pipeline
build_animation_from_manifest(JSON_PATH)

# Run the build
build_scene_from_manifest(JSON_PATH)


def import_audio_to_sequencer(filepath):
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return

    with open(filepath, 'r') as f:
        data = json.load(f)

    scene = bpy.context.scene

    # Ensure Sequence Editor exists on current scene
    if not scene.sequence_editor:
        scene.sequence_editor_create()

    sequencer = scene.sequence_editor

    # Import audio strips at specified frames
    for i, line in enumerate(data.get('script_data', [])):
        audio_file = line.get('audio_file')
        start_frame = line.get('start_frame', (i + 1) * 48)

        if audio_file and os.path.exists(audio_file):
            strip_name = f"Audio_{line['speaker']}_Line_{i}"
            
            # Place audio on Channel 1 in VSE
            sound_strip = sequencer.sequences.new_sound(
                name=strip_name,
                filepath=audio_file,
                channel=1,
                frame_start=start_frame
            )
            print(f"Loaded audio for {line['speaker']} at frame {start_frame}")
        else:
            print(f"Audio file missing for line {i}: {audio_file}")

    print("Audio synchronization complete!")

# Execute audio import
import_audio_to_sequencer(JSON_PATH)

def setup_multi_camera_cuts(script_data):
    """Spawns directional cameras and binds active camera cuts to timeline markers."""
    scene = bpy.context.scene
    cameras_created = {}

    for line in script_data:
        cam_info = line.get('camera_shot')
        if not cam_info:
            continue

        cam_name = cam_info['name']
        start_frame = line['start_frame']

        # 1. Instantiate Camera Object if it doesn't exist yet
        if cam_name not in cameras_created:
            cam_data = bpy.data.cameras.new(name=cam_name)
            cam_obj = bpy.data.objects.new(cam_name, cam_data)
            cam_obj.location = cam_info['location']
            cam_obj.rotation_euler = cam_info['rotation']
            scene.collection.objects.link(cam_obj)
            cameras_created[cam_name] = cam_obj
        else:
            cam_obj = cameras_created[cam_name]

        # 2. Add Timeline Marker for the camera cut
        marker_name = f"CUT_{cam_name}_F{start_frame}"
        marker = scene.timeline_markers.new(name=marker_name, frame=start_frame)
        
        # 3. Bind the Camera object to this specific marker frame
        marker.camera = cam_obj

    print(f"Successfully configured {len(cameras_created)} cameras across dialogue cuts!")

# Call this function during manifest import:
# setup_multi_camera_cuts(manifest_data['script_data'])

def apply_signature_camera_shot(cam_obj, shot_data, start_frame, duration_frames=48):
    """Animates complex cinematic camera moves like Vertigo zoom or Double Dolly."""
    lens_info = shot_data.get('lens', {})
    cam_data = cam_obj.data

    # Apply Lens Properties
    cam_data.lens = lens_info.get('focal_length', 50)
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = lens_info.get('f_stop', 2.8)

    shot_type = shot_data.get('type')

    # 1. SPIKE LEE DOUBLE DOLLY
    if shot_type == "DOUBLE_DOLLY":
        start_loc = shot_data['start_loc']
        end_loc = shot_data['end_loc']

        cam_obj.location = start_loc
        cam_obj.keyframe_insert(data_path="location", frame=start_frame)

        cam_obj.location = end_loc
        cam_obj.keyframe_insert(data_path="location", frame=start_frame + duration_frames)

    # 2. HITCHCOCK DOLLY ZOOM (VERTIGO EFFECT)
    elif shot_type == "VERTIGO_EFFECT":
        # Keyframe focal length zoom in opposite direction of camera dolly
        cam_data.lens = shot_data['start_focal']
        cam_data.keyframe_insert(data_path="lens", frame=start_frame)

        cam_data.lens = shot_data['end_focal']
        cam_data.keyframe_insert(data_path="lens", frame=start_frame + duration_frames)


def apply_dynamic_lighting_keyframes(lighting_data, start_frame, duration_frames=48):
    """Animates lights and Kess's skin emission strength across speaking beats."""
    
    # 1. Keyframe Ambient Environment Light
    env_light = bpy.data.objects.get("Key_Light")
    if env_light and env_light.type == 'LIGHT':
        light_data = env_light.data
        light_data.energy = lighting_data['environment_energy']
        light_data.color = lighting_data['light_color']
        
        light_data.keyframe_insert(data_path="energy", frame=start_frame)
        light_data.keyframe_insert(data_path="color", frame=start_frame)

    # 2. Keyframe Luminara Cyan Material Glow Strength
    glow_mat = bpy.data.materials.get("M_Luminara_Glow")
    if glow_mat and glow_mat.use_nodes:
        emission_node = glow_mat.node_tree.nodes.get("Emission")
        if emission_node:
            strength_input = emission_node.inputs['Strength']
            strength_input.default_value = lighting_data['kess_emission_energy']
            strength_input.keyframe_insert(data_path="default_value", frame=start_frame)


def build_cinematic_manifest(filepath):
    with open(filepath, 'r') as f:
        data = json.load(f)

    scene = bpy.context.scene
    main_cam = scene.camera

    for line in data.get('script_data', []):
        start_frame = line['start_frame']

        # Apply Lighting Triggers
        if 'lighting_state' in line:
            apply_dynamic_lighting_keyframes(line['lighting_state'], start_frame)

        # Apply Camera Signature Moves & Lens Specs
        if 'signature_shot' in line and main_cam:
            apply_signature_camera_shot(main_cam, line['signature_shot'], start_frame)

    print("Cinematography, lens attributes, and dynamic lighting successfully built!")

def setup_sci_fi_compositor(vfx_data):
    """Sets up sci-fi post-processing: Bloom/Glare, Chromatic Aberration, and Color Grading."""
    scene = bpy.context.scene
    scene.use_nodes = True
    tree = scene.node_tree
    nodes = tree.nodes
    links = tree.links

    nodes.clear()

    # Create Node Pipeline
    render_layers = nodes.new(type='CompositorNodeRLayers')
    render_layers.location = (0, 0)

    # 1. Glare Node (Sci-Fi Glow/Bloom)
    glare_node = nodes.new(type='CompositorNodeGlare')
    glare_node.glare_type = 'FOG_GLOW'
    glare_node.quality = 'HIGH'
    glare_node.size = 8
    glare_node.threshold = 0.5
    glare_node.location = (300, 0)

    # 2. Lens Distortion Node (Chromatic Aberration)
    distortion_node = nodes.new(type='CompositorNodeLensdist')
    distortion_node.inputs['Dispersion'].default_value = vfx_data.get('chromatic_aberration', 0.02)
    distortion_node.use_fit = True
    distortion_node.location = (600, 0)

    # 3. Output Composite Node
    composite_node = nodes.new(type='CompositorNodeComposite')
    composite_node.location = (900, 0)

    # Link Nodes Together
    links.new(render_layers.outputs['Image'], glare_node.inputs['Image'])
    links.new(glare_node.outputs['Image'], distortion_node.inputs['Image'])
    links.new(distortion_node.outputs['Image'], composite_node.inputs['Image'])


def setup_volumetric_fog(vfx_data):
    """Generates atmospheric subterranean fog volume in the scene."""
    world = bpy.context.scene.world
    if not world:
        world = bpy.data.worlds.new("SciFiWorld")
        bpy.context.scene.world = world

    world.use_nodes = True
    nodes = world.node_tree.nodes
    links = world.node_tree.links

    # Clear world nodes and build volume scatter
    nodes.clear()
    output_node = nodes.new(type='ShaderNodeOutputWorld')
    
    volume_scatter = nodes.new(type='ShaderNodeVolumeScatter')
    volume_scatter.inputs['Density'].default_value = vfx_data.get('volumetric_density', 0.05)
    volume_scatter.inputs['Color'].default_value = (*vfx_data.get('fog_color', [0.0, 0.0, 0.0]), 1.0)

    links.new(volume_scatter.outputs['Volume'], output_node.inputs['Volume'])


def configure_social_formatting(social_data):
    """Sets resolution, aspect ratio, and auto-adjusts camera FOV for 9:16 or 16:9."""
    scene = bpy.context.scene
    res_x, res_y = social_data['resolution']

    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.fps = social_data['target_fps']

    camera = scene.camera
    if camera and social_data['aspect_ratio'] == "9:16":
        # Adjust sensor fit to vertical so characters stay framed in 9:16
        camera.data.sensor_fit = 'VERTICAL'
        camera.data.sensor_height = 36


def apply_sci_fi_and_social_pipeline(manifest_path, platform_key="tiktok_reels"):
    with open(manifest_path, 'r') as f:
        data = json.load(f)

    # 1. Apply Social Media Output Settings
    social_cfg = data.get('social_media', {})
    configure_social_formatting(social_cfg)

    # 2. Build Sci-Fi Atmosphere and Compositor Glows
    vfx_cfg = data.get('sci_fi_vfx', {})
    setup_sci_fi_compositor(vfx_cfg)
    setup_volumetric_fog(vfx_cfg)

    print(f"Configured for platform: {platform_key} with full Sci-Fi VFX stack!")


def apply_arkit_facial_keyframes(char_mesh_name, facial_data):
    """Keyframes ARKit Shape Keys on the designated character head mesh."""
    char_obj = bpy.data.objects.get(char_mesh_name)
    if not char_obj or not char_obj.data.shape_keys:
        print(f"Mesh '{char_mesh_name}' or Shape Keys not found. Skipping facial pass.")
        return

    key_blocks = char_obj.data.shape_keys.key_blocks

    start_f = facial_data['start_frame']
    peak_f = facial_data['peak_frame']
    end_f = facial_data['end_frame']
    shapes = facial_data['blendshapes']

    for shape_name, target_value in shapes.items():
        if shape_name in key_blocks:
            kb = key_blocks[shape_name]

            # 1. Keyframe baseline (0.0) right before speech starts
            kb.value = 0.0
            kb.keyframe_insert(data_path="value", frame=max(1, start_f - 6))

            # 2. Keyframe emotional peak
            kb.value = target_value
            kb.keyframe_insert(data_path="value", frame=peak_f)

            # 3. Keyframe return to neutral after speech beat
            kb.value = 0.0
            kb.keyframe_insert(data_path="value", frame=end_f + 12)

def build_facial_animation_pipeline(manifest_path, char_mesh_name="Kess_Head"):
    with open(manifest_path, 'r') as f:
        data = json.load(f)

    for line in data.get('script_data', []):
        if 'facial_expression' in line:
            apply_arkit_facial_keyframes(char_mesh_name, line['facial_expression'])

    print("ARKit facial shape keys successfully keyframed across all performance beats!")