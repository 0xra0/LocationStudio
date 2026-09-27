local Util=require('modules/util')

-- Streaming/performance analyzer for the saved project. It estimates what each
-- room and premise asks the engine to stream: node counts, lights, audio
-- emitters, decals, VFX, dynamic entities and known-expensive resources, a
-- weighted relative cost, budget overruns, distance from V, and unusually dense
-- clusters. Costs are heuristics for comparing areas, not measured frame time.
local Performance={};Performance.__index=Performance

-- World Builder definition -> category and relative cost weight.
local CLASSES={
    mesh_static={category='static',cost=1},mesh_proxy={category='static',cost=0.5},
    mesh_rotating={category='dynamic',cost=3,expensive='animated rotating mesh'},
    mesh_cloth={category='dynamic',cost=6,expensive='cloth simulation'},
    mesh_dynamic={category='dynamic',cost=5,expensive='physics-simulated mesh'},
    entity_template={category='dynamic',cost=3},entity_amm={category='dynamic',cost=3},
    entity_record={category='dynamic',cost=6,expensive='NPC/character record'},
    device={category='dynamic',cost=3},
    light_static={category='lights',cost=4},light_probe={category='lights',cost=6,expensive='reflection probe'},
    light_channel={category='meta',cost=0.5},
    fog={category='vfx',cost=5,expensive='volumetric fog volume'},
    decal={category='decals',cost=1.5},
    particle={category='vfx',cost=4},effect={category='vfx',cost=4},
    audio={category='audio',cost=2},area_ambient={category='audio',cost=1},
    water={category='vfx',cost=6,expensive='water patch'},
    collision_shape={category='collision',cost=0.5},collision_mesh={category='collision',cost=1},
    occluder={category='meta',cost=0.2},static_marker={category='meta',cost=0.1},spline_point={category='meta',cost=0.1},
    spline={category='meta',cost=0.2},area_outline={category='meta',cost=0.1},area_trigger={category='meta',cost=0.3},
    area_kill={category='meta',cost=0.3},area_prevention={category='meta',cost=0.3},area_water_null={category='meta',cost=0.3},
    area_dummy={category='meta',cost=0.1},area_conversation={category='meta',cost=0.3},area_crowd_null={category='meta',cost=0.3},
    area_guard={category='meta',cost=0.3},ai_spot={category='meta',cost=0.5},ai_community={category='dynamic',cost=4,expensive='AI community'},
}
local CATEGORIES={'static','lights','audio','decals','vfx','dynamic','collision','meta'}
local BUDGET_KEYS={nodes='nodes',lights='lights',audio='audio',decals='decals',vfx='vfx',dynamic='dynamic',cost='cost'}

local function classify(object)
    local md=object.metadata or {}
    local wb=md.world_builder
    local info
    if type(wb)=='table' and CLASSES[wb.definition_key] then info=Util.deepcopy(CLASSES[wb.definition_key]);info.definition=wb.definition_key
    elseif md.npc_population then info={category='dynamic',cost=6,expensive='NPC population spawner',definition='npc_population'}
    elseif type(object.template)=='string' and object.template:lower():find('%.ent$') then info={category='dynamic',cost=3,definition='cet_entity'}
    elseif object.kind=='light' then info={category='lights',cost=4,definition='light'}
    else info={category='meta',cost=0.2,definition=object.kind or 'unknown'} end
    -- Resource-specific upgrades: big or flickering lights and large decals.
    if info.category=='lights' and md.lighting then
        local radius=tonumber(md.lighting.radius) or 0
        if radius>15 then info.cost=info.cost+radius/5;info.expensive='light radius '..radius..' m' end
        if (tonumber(md.lighting.flickerStrength) or 0)>0 then info.cost=info.cost+1 end
    end
    if info.category=='vfx' and md.vfx and md.vfx.emission_rate and md.vfx.emission_rate>5 then
        info.cost=info.cost+md.vfx.emission_rate/5;info.expensive='particle emission rate '..md.vfx.emission_rate
    end
    if info.category=='decals' and object.size and (tonumber(object.size.x) or 1)*(tonumber(object.size.y) or 1)>16 then
        info.cost=info.cost+2;info.expensive='large decal'
    end
    return info
end

local function blank_counts()
    local c={nodes=0,cost=0,expensive=0};for _,k in ipairs(CATEGORIES) do c[k]=0 end;return c
end

local function add(counts,info)
    counts.nodes=counts.nodes+1;counts[info.category]=counts[info.category]+1;counts.cost=counts.cost+info.cost
    if info.expensive then counts.expensive=counts.expensive+1 end
end

local function round(n) return math.floor(n*10+0.5)/10 end

function Performance.new(app) return setmetatable({app=app,last_report=nil},Performance) end

function Performance:settings() return self.app.model.data.settings.performance end
function Performance:classes() return Util.deepcopy(CLASSES) end

function Performance:_player()
    local t=self.app.game and self.app.game:capture_transform()
    return t and t.position or nil
end

local function over_budget(counts,budget)
    local out={}
    for key,field in pairs(BUDGET_KEYS) do
        local limit=tonumber(budget and budget[key])
        if limit and counts[field]>limit then out[#out+1]={metric=key,value=round(counts[field]),limit=limit} end
    end
    table.sort(out,function(a,b) return a.metric<b.metric end)
    return out
end

-- Grid clustering in XY: occupied cells whose cost is above both a floor and
-- median + sigma * robust spread (MAD * 1.4826) are dense; touching dense cells
-- merge into a cluster. Median/MAD keep one huge cell from hiding itself by
-- inflating the mean and standard deviation.
function Performance:_clusters(rows,cfg)
    local size=math.max(1,tonumber(cfg.cell_size) or 5)
    local cells={}
    for _,row in ipairs(rows) do
        local p=row.position;local i,j=math.floor(p.x/size),math.floor(p.y/size);local key=i..':'..j
        local cell=cells[key];if not cell then cell={i=i,j=j,cost=0,rows={}};cells[key]=cell end
        cell.cost=cell.cost+row.info.cost;cell.rows[#cell.rows+1]=row
    end
    local list,costs={}, {}
    for _,cell in pairs(cells) do list[#list+1]=cell;costs[#costs+1]=cell.cost end
    if #list==0 then return {},{median=0,robust_spread=0,threshold=0,cells=0,cell_size=size} end
    local function median(values) table.sort(values);local n=#values;if n%2==1 then return values[(n+1)/2] end;return (values[n/2]+values[n/2+1])/2 end
    local med=median(costs);local deviations={};for i,c in ipairs(costs) do deviations[i]=math.abs(c-med) end
    local spread=median(deviations)*1.4826
    local threshold=math.max(tonumber(cfg.cluster_min_cost) or 40,med+(tonumber(cfg.cluster_sigma) or 3)*spread)
    local dense={};for key,cell in pairs(cells) do if cell.cost>=threshold then dense[key]=cell end end
    local seen,clusters={}, {}
    for key,cell in pairs(dense) do if not seen[key] then
        local members,queue={}, {cell};seen[key]=true
        while #queue>0 do
            local c=table.remove(queue);members[#members+1]=c
            for di=-1,1 do for dj=-1,1 do local k=(c.i+di)..':'..(c.j+dj);if dense[k] and not seen[k] then seen[k]=true;queue[#queue+1]=dense[k] end end end
        end
        local counts=blank_counts();local cx,cy,cz,n=0,0,0,0;local contributors={};local rooms={}
        for _,m in ipairs(members) do for _,row in ipairs(m.rows) do
            add(counts,row.info);cx=cx+row.position.x;cy=cy+row.position.y;cz=cz+row.position.z;n=n+1
            contributors[#contributors+1]={id=row.id,name=row.name,category=row.info.category,cost=round(row.info.cost),expensive=row.info.expensive}
            if row.room_id then rooms[row.room_id]=true end
        end end
        table.sort(contributors,function(a,b) return a.cost>b.cost end)
        while #contributors>8 do table.remove(contributors) end
        local center={x=cx/n,y=cy/n,z=cz/n};local radius=0
        for _,m in ipairs(members) do for _,row in ipairs(m.rows) do radius=math.max(radius,math.sqrt((row.position.x-center.x)^2+(row.position.y-center.y)^2)) end end
        local room_ids={};for id in pairs(rooms) do room_ids[#room_ids+1]=id end;table.sort(room_ids)
        counts.cost=round(counts.cost)
        clusters[#clusters+1]={center=center,radius=round(radius),cells=#members,counts=counts,top_contributors=contributors,room_ids=room_ids}
    end end
    table.sort(clusters,function(a,b) return a.counts.cost>b.counts.cost end)
    return clusters,{median=round(med),robust_spread=round(spread),threshold=round(threshold),cells=#list,cell_size=size}
end

-- Lights whose radius covers many other lights overdraw the same pixels.
function Performance:_light_overlaps(rows,cfg)
    local lights={};for _,row in ipairs(rows) do if row.info.category=='lights' then lights[#lights+1]=row end end
    local limit=tonumber(cfg.light_overlap_limit) or 4;local out={}
    for _,a in ipairs(lights) do
        local radius=tonumber(a.radius) or 8;local overlapping=0
        for _,b in ipairs(lights) do if a~=b then
            local d=math.sqrt((a.position.x-b.position.x)^2+(a.position.y-b.position.y)^2+(a.position.z-b.position.z)^2)
            if d<radius+(tonumber(b.radius) or 8) then overlapping=overlapping+1 end
        end end
        if overlapping>limit then out[#out+1]={id=a.id,name=a.name,overlapping=overlapping,limit=limit,radius=radius} end
    end
    table.sort(out,function(x,y) return x.overlapping>y.overlapping end)
    return out
end

function Performance:analyze(args)
    args=args or {}
    local cfg=self:settings();local model=self.app.model
    local player=args.player_position or self:_player()
    local rows={}
    for _,o in ipairs(model.data.objects or {}) do
        if o.enabled~=false and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) and o.transform and o.transform.position then
            local info=classify(o)
            if not (args.include_meta==false and info.category=='meta') then
                rows[#rows+1]={id=o.id,name=o.name,premise_id=o.premise_id,room_id=o.room_id,position=o.transform.position,info=info,
                    radius=o.metadata and o.metadata.lighting and o.metadata.lighting.radius or nil,spawned=o.runtime and o.runtime.spawned==true}
            end
        end
    end
    local function distance(p) if not player or not p then return nil end;return round(math.sqrt((p.x-player.x)^2+(p.y-player.y)^2+(p.z-player.z)^2)) end
    -- Rooms (objects without a room are grouped per premise).
    local groups,order={}, {}
    local function group(key,label,kind,center,premise_id)
        local g=groups[key];if not g then g={key=key,name=label,kind=kind,premise_id=premise_id,counts=blank_counts(),expensive={},center=center,live=0};groups[key]=g;order[#order+1]=g end
        return g
    end
    for _,row in ipairs(rows) do
        local room=row.room_id and model:get_room(row.room_id)
        local g
        if room then g=group('room:'..room.id,room.name,'room',room.transform.position,room.premise_id);g.room_id=room.id
        else
            local premise=row.premise_id and model:get_premise(row.premise_id)
            g=group('loose:'..tostring(row.premise_id),(premise and premise.name or 'No premise')..' (outside rooms)','unassigned',premise and premise.transform.position or nil,row.premise_id)
        end
        add(g.counts,row.info);if row.spawned then g.live=g.live+1 end
        if row.info.expensive then g.expensive[#g.expensive+1]={id=row.id,name=row.name,reason=row.info.expensive} end
        g.sum=g.sum or {x=0,y=0,z=0,n=0};g.sum.x=g.sum.x+row.position.x;g.sum.y=g.sum.y+row.position.y;g.sum.z=g.sum.z+row.position.z;g.sum.n=g.sum.n+1
    end
    local rooms={}
    for _,g in ipairs(order) do
        local center=g.center or {x=g.sum.x/g.sum.n,y=g.sum.y/g.sum.n,z=g.sum.z/g.sum.n}
        g.counts.cost=round(g.counts.cost)
        rooms[#rooms+1]={key=g.key,name=g.name,kind=g.kind,room_id=g.room_id,premise_id=g.premise_id,counts=g.counts,live_objects=g.live,
            expensive=g.expensive,center={x=center.x,y=center.y,z=center.z},distance_from_player=distance(center),
            over_budget=over_budget(g.counts,cfg.room_budget)}
    end
    table.sort(rooms,function(a,b) return a.counts.cost>b.counts.cost end)
    -- Premises.
    local premises={}
    for _,premise in ipairs(model.data.premises or {}) do
        if not args.premise_id or args.premise_id=='' or premise.id==args.premise_id then
            local counts=blank_counts()
            for _,row in ipairs(rows) do if row.premise_id==premise.id then add(counts,row.info) end end
            counts.cost=round(counts.cost)
            premises[#premises+1]={id=premise.id,name=premise.name,counts=counts,distance_from_player=distance(premise.transform.position),over_budget=over_budget(counts,cfg.premise_budget)}
        end
    end
    local clusters,stats=self:_clusters(rows,cfg)
    for _,c in ipairs(clusters) do c.distance_from_player=distance(c.center) end
    local totals=blank_counts();for _,row in ipairs(rows) do add(totals,row.info) end;totals.cost=round(totals.cost)
    local overlaps=self:_light_overlaps(rows,cfg)
    local warnings={}
    for _,r in ipairs(rooms) do for _,o in ipairs(r.over_budget) do warnings[#warnings+1]={scope=r.kind,name=r.name,key=r.key,metric=o.metric,value=o.value,limit=o.limit} end end
    for _,p in ipairs(premises) do for _,o in ipairs(p.over_budget) do warnings[#warnings+1]={scope='premise',name=p.name,key='premise:'..p.id,metric=o.metric,value=o.value,limit=o.limit} end end
    local report={totals=totals,rooms=rooms,premises=premises,clusters=clusters,cluster_stats=stats,light_overlaps=overlaps,warnings=warnings,
        player_position=player and {x=player.x,y=player.y,z=player.z} or nil,analyzed_objects=#rows,
        budgets={room=Util.deepcopy(cfg.room_budget),premise=Util.deepcopy(cfg.premise_budget)},
        note='Relative cost estimate from resource types (not measured frame time). Vanilla world content is not included; use the sector report for exported sectors.'}
    self.last_report=report
    return report
end

function Performance:set_budget(scope,values)
    local cfg=self:settings();local key=scope=='premise' and 'premise_budget' or 'room_budget'
    if type(values)~='table' then return nil,'values must be a table of metric limits' end
    for metric,value in pairs(values) do
        if not BUDGET_KEYS[metric] then return nil,'unknown budget metric: '..tostring(metric) end
        local n=tonumber(value);if not n or n<0 then return nil,metric..' must be a non-negative number' end
    end
    for metric,value in pairs(values) do cfg[key][metric]=tonumber(value) end
    self.app:mark_dirty()
    return Util.deepcopy(cfg[key])
end

-- Select every object in a cluster for inspection or transform tools.
function Performance:select_cluster(index)
    local report=self.last_report;if not report then return nil,'run the analysis first' end
    local cluster=report.clusters[tonumber(index) or 0];if not cluster then return nil,'cluster not found' end
    local cfg=self:settings();local size=math.max(1,tonumber(cfg.cell_size) or 5)
    local ids={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local p=o.transform and o.transform.position
        if p and math.sqrt((p.x-cluster.center.x)^2+(p.y-cluster.center.y)^2)<=cluster.radius+size*0.5 and o.enabled~=false then ids[#ids+1]=o.id end
    end
    if #ids==0 then return nil,'no objects remain in that cluster' end
    local ok,err=self.app.selection:set_object_group(ids,ids[1],'performance_cluster')
    if ok==nil and err then return nil,err end
    return {selected=#ids,object_ids=ids}
end

Performance.CATEGORIES=CATEGORIES
return Performance
