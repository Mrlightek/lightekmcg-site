"""Bounded rehearsal blocking on a fork of the saved scene."""
import heapq
import math

def route(start, goal, blocked, *, step=0.5, extent=32, limit=4096):
    cell=lambda p:(round(p[0]/step),round(p[1]/step))
    start,goal=cell(start),cell(goal)
    def available(point):
        return abs(point[0])<=extent and abs(point[1])<=extent and not blocked(point[0]*step,point[1]*step)
    def nearest(point):
        for radius in range(11):
            candidates=[(point[0]+x,point[1]+y) for x in range(-radius,radius+1) for y in range(-radius,radius+1) if max(abs(x),abs(y))==radius]
            for candidate in sorted(candidates,key=lambda c:((c[0]-point[0])**2+(c[1]-point[1])**2,c)):
                if available(candidate):return candidate
        return None
    start,goal=nearest(start),nearest(goal)
    if start is None or goal is None:return None
    frontier=[(0,start)];cost={start:0};previous={};visited=0
    while frontier and visited<limit:
        _,point=heapq.heappop(frontier);visited+=1
        if point==goal:
            path=[point]
            while point in previous:point=previous[point];path.append(point)
            path.reverse()
            # Keep corners while removing redundant collinear grid points.
            reduced=[]
            for p in path:
                if len(reduced)>1 and (reduced[-1][0]-reduced[-2][0],reduced[-1][1]-reduced[-2][1])==(p[0]-reduced[-1][0],p[1]-reduced[-1][1]):reduced[-1]=p
                else:reduced.append(p)
            return [[x*step,y*step] for x,y in reduced] if len(reduced)<=64 else None
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            neighbour=(point[0]+dx,point[1]+dy)
            new=cost[point]+1
            if available(neighbour) and new<cost.get(neighbour,math.inf):
                previous[neighbour]=point;cost[neighbour]=new
                heapq.heappush(frontier,(new+abs(neighbour[0]-goal[0])+abs(neighbour[1]-goal[1]),neighbour))
    return None

def plan(objects, created, settings):
    import bpy
    import spatial_checks
    scene=bpy.context.scene;first,last=scene.frame_start,scene.frame_end
    if not 1<=last-first+1<=2400:raise RuntimeError('Rehearsal supports 1–2400 source frames')
    data=settings['_director_rehearsal'];goals=data.get('goals',{})
    cast=[item for item in objects if item.get('definition',{}).get('character_profile') or (item.get('definition',{}).get('director_speaker') or item.get('definition',{}).get('blocking_actor'))]
    report={'version':1,'status':'ready','corrections':[],'unresolved':[],'checked_frames':last-first+1,'method':'bounded_grid_root_blocking','preview_only':True}
    if len(cast)>16:raise RuntimeError('Rehearse at most sixteen Cast members')
    scene.frame_set(first);bpy.context.view_layer.update()
    positions={str(item['id']):created[str(item['id'])].matrix_world.translation.copy() for item in cast}
    scene.frame_set(last);bpy.context.view_layer.update()
    endpoints={str(item['id']):created[str(item['id'])].matrix_world.translation.copy() for item in cast}
    scene.frame_set(first);bpy.context.view_layer.update();depsgraph=bpy.context.evaluated_depsgraph_get()
    colliders=[item for item in objects if item not in cast and str(item['id']) in created]
    reserved=[]
    for item in cast:
        key=str(item['id']);root=created[key];definition=item.get('definition',{})
        if root.parent or definition.get('story_relation',{}).get('relative_to') is not None:
            report['unresolved'].append('Parented character '+item['name']+' needs manual blocking');continue
        mesh=spatial_checks.geometry(root,depsgraph)
        radius=max(0.3,float(settings.get('spatial_direction',{}).get('personal_space',0.9))/2)
        if mesh:radius=max(radius,(mesh[2][0][1]-mesh[2][0][0])/2,(mesh[2][1][1]-mesh[2][1][0])/2)
        if radius>3:
            report['unresolved'].append('Check the scene scale of '+item['name']);continue
        foot=mesh[2][2][0] if mesh else positions[key].z
        head=mesh[2][2][1] if mesh else foot+1.8
        rectangles=[]
        for collider in colliders:
            shape=spatial_checks.geometry(created[str(collider['id'])],depsgraph)
            if not shape:continue
            for triangle in shape[1]:
                vertices=[shape[0][index] for index in triangle]
                low,high=min(v.z for v in vertices),max(v.z for v in vertices)
                if high<=foot+0.02 or low>=head:continue
                rectangles.append((min(v.x for v in vertices)-radius-0.1,max(v.x for v in vertices)+radius+0.1,min(v.y for v in vertices)-radius-0.1,max(v.y for v in vertices)+radius+0.1))
                if len(rectangles)>5000:break
            if len(rectangles)>5000:break
        if len(rectangles)>5000:
            report['unresolved'].append('Use simpler collision proxies for '+item['name']);continue
        clearance=max(radius*2,float(definition.get('story_relation',{}).get('personal_space',0.9)))
        other=[p for other_key,p in positions.items() if other_key!=key]
        def blocked(x,y):
            return any(a<=x<=b and c<=y<=d for a,b,c,d in rectangles) or any(math.hypot(x-p.x,y-p.y)<clearance for p in other) or any(math.hypot(x-p[0],y-p[1])<clearance for p in reserved)
        start=positions[key];goal=goals.get(key,list(endpoints[key]))
        path=route(start,goal,blocked)
        if not path:
            report['unresolved'].append('No bounded collision-free route found for '+item['name']);continue
        z=max(start.z,start.z-foot) if foot<0 else start.z
        lengths=[0.0]
        for a,b in zip(path,path[1:]):lengths.append(lengths[-1]+math.dist(a,b))
        elapsed=(last-first)/(scene.render.fps/scene.render.fps_base)
        if lengths[-1]>0 and (elapsed<=0 or lengths[-1]/elapsed>2.5):
            report['unresolved'].append('Extend the scene or shorten the walking route for '+item['name']+' (maximum 2.5 metres per second)');continue
        frames=[]
        for point,distance in zip(path,lengths):
            frame=first+round((last-first)*distance/lengths[-1]) if lengths[-1]>0 else first
            frames.append({'frame':frame,'location':[point[0],point[1],z]})
        if len(frames)==1:frames.append({'frame':last,'location':frames[0]['location'][:]})
        if root.animation_data and root.animation_data.action:
            root.animation_data.action=root.animation_data.action.copy()
            for curve in list(root.animation_data.action.fcurves):
                if curve.data_path=='location':root.animation_data.action.fcurves.remove(curve)
        for frame in frames:
            root.location=frame['location'];root.keyframe_insert(data_path='location',frame=frame['frame'])
        for curve in root.animation_data.action.fcurves:
            if curve.data_path=='location':
                for point in curve.keyframe_points:point.interpolation='LINEAR'
        reserved.extend(path)
        report['corrections'].append({'object_id':item['id'],'name':item['name'],'before':list(start),'location':frames[0]['location'],'frames':frames,'kind':'root_path','requires_walk_cycle':len(path)>1})
    scene.frame_set(first);bpy.context.view_layer.update()
    return report
