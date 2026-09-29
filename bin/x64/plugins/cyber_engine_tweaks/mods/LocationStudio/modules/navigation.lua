-- Imported navigation graph authoring. This is never represented as a native REDengine query.
local Util=require('modules/util')
local Navigation={}
Navigation.__index=Navigation
local kinds={walk=true,door=true,stairs=true,elevator=true,jump=true,off_mesh=true,ramp=true,custom=true}
local function pos(p) return type(p)=='table' and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) end
local function distance(a,b) local x,y,z=a.x-b.x,a.y-b.y,a.z-b.z;return math.sqrt(x*x+y*y+z*z) end
local function heap_push(heap,item)
    local i=#heap+1;heap[i]=item
    while i>1 do local p=math.floor(i/2);if heap[p].cost<=item.cost then break end;heap[i]=heap[p];i=p;heap[i]=item end
end
local function heap_pop(heap)
    local root=heap[1];local last=table.remove(heap);if #heap==0 then return root end
    local i=1;heap[1]=last
    while true do local l=i*2;local r=l+1;local c=i;if l<=#heap and heap[l].cost<heap[c].cost then c=l end;if r<=#heap and heap[r].cost<heap[c].cost then c=r end;if c==i then break end;heap[i],heap[c]=heap[c],heap[i];i=c end
    return root
end
function Navigation.new(app) return setmetatable({app=app},Navigation) end
function Navigation:list() return self.app.model.data.navigation_graphs or {} end
function Navigation:import_graph(raw)
    if type(raw)~='table' then return nil,'graph must be an object' end
    local nodes=raw.nodes;local edges=raw.edges;local polygons=raw.polygons or {}
    if type(nodes)~='table' or type(edges)~='table' then return nil,'graph requires nodes[] and edges[]' end
    if #nodes<1 or #nodes>50000 or #edges>100000 or type(polygons)~='table' or #polygons>25000 then return nil,'graph exceeds supported node/edge/polygon limits' end
    local ids={};local clean_nodes={}
    for i,n in ipairs(nodes) do
        if type(n)~='table' or type(n.id)~='string' or n.id=='' or ids[n.id] or not pos(n.position) then return nil,'invalid/duplicate node at index '..i end
        ids[n.id]=true;clean_nodes[i]={id=n.id,name=tostring(n.name or n.id),position={x=n.position.x,y=n.position.y,z=n.position.z},surface=tostring(n.surface or ''),source=tostring(n.source or 'imported')}
    end
    local clean_edges={}
    for i,e in ipairs(edges) do
        if type(e)~='table' or not ids[e.from] or not ids[e.to] or e.from==e.to then return nil,'edge '..i..' references missing or identical nodes' end
        local kind=kinds[e.kind] and e.kind or nil;if not kind then return nil,'edge '..i..' has unsupported kind' end
        clean_edges[i]={id=tostring(e.id or ('edge_'..i)),from=e.from,to=e.to,kind=kind,enabled=e.enabled~=false,one_way=e.one_way==true,cost=math.max(0.01,math.min(100000,tonumber(e.cost) or 1)),notes=tostring(e.notes or '')}
    end
    local clean_polygons={}
    for i,poly in ipairs(polygons) do
        if type(poly)~='table' or type(poly.vertices)~='table' or #poly.vertices<3 or #poly.vertices>64 then return nil,'polygon '..i..' must contain 3 to 64 vertices' end
        local vertices={};for j,v in ipairs(poly.vertices) do if not pos(v) then return nil,'polygon '..i..' has an invalid vertex' end;vertices[j]={x=tonumber(v.x),y=tonumber(v.y),z=tonumber(v.z)} end
        clean_polygons[i]={id=tostring(poly.id or ('poly_'..i)),vertices=vertices,surface=tostring(poly.surface or 'walkable'),source=tostring(poly.source or 'imported')}
    end
    local graph={id=Util.make_id('nav'),name=tostring(raw.name or 'Imported navigation graph'),format='locationstudio.navigation-graph.v1',source_format=tostring(raw.source_format or 'json-interchange'),source=tostring(raw.source or 'user-import'),coordinate_space='world',native_redengine=false,nodes=clean_nodes,edges=clean_edges,polygons=clean_polygons,imported_at=Util.now_iso()}
    self.app.model:snapshot('Import navigation graph');table.insert(self.app.model.data.navigation_graphs,graph);self.app.model:touch();self.app:mark_dirty()
    return {id=graph.id,name=graph.name,node_count=#clean_nodes,edge_count=#clean_edges,polygon_count=#clean_polygons,native_redengine=false,notice='Imported graph/polygon data only; not a native REDengine navmesh query.'}
end
function Navigation:query(a)
    a=a or {};local graph
    for _,g in ipairs(self:list()) do if g.id==a.graph_id or (not a.graph_id and g.id==self.app.model.data.active_navigation_graph_id) then graph=g end end
    if not graph and not a.graph_id then graph=self:list()[1] end
    if not graph then return {status='unavailable',native_redengine=false,reason='No imported navigation graph is selected.'} end
    if not pos(a.start) or not pos(a.goal) then return nil,'start and goal require world x/y/z' end
    local snap=math.max(0.1,math.min(100,tonumber(a.snap_distance) or 3));local byid,adj={},{}
    for _,n in ipairs(graph.nodes) do byid[n.id]=n;adj[n.id]={} end
    local function nearest(p)
        local best,d=nil,math.huge;for _,n in ipairs(graph.nodes) do local v=distance(p,n.position);if v<d then best,d=n,v end end
        return best,d
    end
    local s,sd=nearest(a.start);local t,td=nearest(a.goal)
    if not s or sd>snap or td>snap then return {status='unmapped',native_redengine=false,graph_id=graph.id,start_snap_distance=sd,goal_snap_distance=td,snap_distance=snap,reason='Endpoint is farther than snap_distance from an imported graph node.'} end
    for _,e in ipairs(graph.edges) do if e.enabled and byid[e.from] and byid[e.to] then
        adj[e.from][#adj[e.from]+1]={to=e.to,edge=e,cost=e.cost};if not e.one_way then adj[e.to][#adj[e.to]+1]={to=e.from,edge=e,cost=e.cost} end
    end end
    local dist,prev,done={[s.id]=0},{},{};local heap={{id=s.id,cost=0}}
    while #heap>0 do
        local current=heap_pop(heap);local u,best=current.id,current.cost
        if not done[u] and best==dist[u] then
            if u==t.id then break end;done[u]=true
            for _,link in ipairs(adj[u]) do local nd=best+link.cost;if dist[link.to]==nil or nd<dist[link.to] then dist[link.to]=nd;prev[link.to]={from=u,edge=link.edge};heap_push(heap,{id=link.to,cost=nd}) end end
        end
    end
    local reachable=dist[t.id]~=nil;local path,transitions={},{}
    if reachable then local cursor=t.id;while cursor do table.insert(path,1,cursor);local p=prev[cursor];if p then if p.edge.kind~='walk' then table.insert(transitions,1,{edge_id=p.edge.id,kind=p.edge.kind,from=p.from,to=cursor,notes=p.edge.notes}) end;cursor=p.from else cursor=nil end end end
    return {status=reachable and 'reachable_in_imported_graph' or 'unreachable_in_imported_graph',native_redengine=false,graph_id=graph.id,method='Dijkstra over imported graph edges',start_node=s.id,goal_node=t.id,start_snap_distance=sd,goal_snap_distance=td,snap_distance=snap,cost=reachable and dist[t.id] or nil,path=path,transitions=transitions,node_count=#graph.nodes,edge_count=#graph.edges,caveat='This result describes only the imported graph. It does not query or prove REDengine AI navigation.'}
end
function Navigation:workspot_report(a)
    a=a or {};local results={};local start=a.start
    if not pos(start) then return nil,'start world x/y/z is required' end
    for _,loc in ipairs(self.app.model.data.locations or {}) do if loc.metadata and loc.metadata.workspot then
        local p=loc.transform.position;local q,err=self:query({graph_id=a.graph_id,start=start,goal=p,snap_distance=a.snap_distance})
        results[#results+1]={location_id=loc.id,name=loc.name,status=q and q.status or 'error',native_redengine=false,detail=err or (q and q.reason),path=q and q.path,transitions=q and q.transitions}
    end end
    return {status='imported_graph_assessment',native_redengine=false,workspots=results,count=#results,caveat='Unreachable means disconnected in the selected imported graph only; engine navmesh, doors, AI archetype and schedules are not queried.'}
end
return Navigation
