local Util=require('modules/util')

local ProjectBrowser={}
ProjectBrowser.__index=ProjectBrowser

local KINDS={
    project={key='project',label='Project'},
    location={key='locations',label='Locations'},route={key='routes',label='Routes'},premise={key='premises',label='Premises'},
    room={key='rooms',label='Rooms'},object={key='objects',label='Objects'},group={key='object_groups',label='Object Groups'},
    prefab={key='object_prefabs',label='Prefabs'},volume={key='volumes',label='Volumes'},camera={key='cameras',label='Cameras'},
    scene={key='scenes',label='Scenes'},asset={key='assets',label='Assets'},layer={key='layers',label='Layers'},
}
local TYPE_ORDER={'location','route','premise','room','object','group','prefab','volume','camera','scene','asset','layer'}
local SEARCH_ORDER={'project','location','route','premise','room','object','group','prefab','volume','camera','scene','asset','layer'}

function ProjectBrowser.new(app) return setmetatable({app=app},ProjectBrowser) end

local function rows_for(data,kind)
    if kind=='project' then return data.project and {data.project} or {} end
    local descriptor=KINDS[kind];return descriptor and data[descriptor.key] or nil
end

local function summary(kind,row)
    return {id=row.id,type=kind,name=row.name or row.template or row.id,kind=row.kind,category=row.category,enabled=row.enabled}
end

local function find_row(data,id,kind)
    if kind then
        local rows=rows_for(data,kind);if not rows then return nil,nil,'unknown item type: '..tostring(kind) end
        for _,row in ipairs(rows) do if row.id==id then return row,kind end end
        return nil,nil,'item not found: '..tostring(id)
    end
    for _,candidate in ipairs(TYPE_ORDER) do
        for _,row in ipairs(rows_for(data,candidate) or {}) do if row.id==id then return row,candidate end
    end end
    if id==tostring((data.project or {}).id or '') then return data.project,'project' end
    return nil,nil,'item not found: '..tostring(id)
end

function ProjectBrowser:get(args)
    args=args or {};local row,kind,err=find_row(self.app.model.data,args.item_id or args.id,args.item_type or args.type)
    if not row then return nil,err end
    return {item=summary(kind,row),data=Util.deepcopy(row)}
end

local function append_searchable(value,out,depth)
    if depth>4 then return end
    local t=type(value)
    if t=='string' or t=='number' then table.insert(out,tostring(value))
    elseif t=='table' then for key,item in pairs(value) do
        if key~='runtime' and key~='created_at' and key~='updated_at' and key~='thumbnail_path' then append_searchable(item,out,depth+1) end
    end end
end

function ProjectBrowser:find(args)
    args=args or {};local query=Util.trim(args.query or args.text or ''):lower()
    if query=='' then return nil,'query must contain at least one character' end
    if #query>200 then return nil,'query is limited to 200 characters' end
    local limit=math.floor(tonumber(args.limit) or 50);if limit<1 or limit>200 then return nil,'limit must be between 1 and 200' end
    local offset=math.floor(tonumber(args.offset) or 0);if offset<0 or offset>100000 then return nil,'offset must be between 0 and 100000' end
    local filter={};for _,kind in ipairs(args.types or {}) do if not KINDS[kind] then return nil,'unknown item type: '..tostring(kind) end;filter[kind]=true end
    local matches={}
    for _,kind in ipairs(SEARCH_ORDER) do
        if next(filter)==nil or filter[kind] then for _,row in ipairs(rows_for(self.app.model.data,kind) or {}) do
            local text={};append_searchable(row,text,0);local haystack=table.concat(text,'\n'):lower()
            if haystack:find(query,1,true) then
                local name=tostring(row.name or row.template or '');local score=row.id==query and 100 or (name:lower()==query and 50 or 10)
                local hit=summary(kind,row);hit.score=score;hit.matched_fields={}
                for _,field in ipairs({'id','name','template','category','kind','notes','purpose','layer'}) do
                    local value=row[field];if type(value)=='string' and value:lower():find(query,1,true) then table.insert(hit.matched_fields,field) end
                end
                local wb=row.metadata and row.metadata.world_builder
                if type(wb)=='table' and ((wb.resource_path or ''):lower():find(query,1,true) or (wb.resource_name or ''):lower():find(query,1,true)) then table.insert(hit.matched_fields,'metadata.world_builder') end
                table.insert(matches,hit)
            end
        end end
    end
    table.sort(matches,function(a,b) if a.score~=b.score then return a.score>b.score end;if a.name~=b.name then return tostring(a.name):lower()<tostring(b.name):lower() end;return tostring(a.id)<tostring(b.id) end)
    local result={};for i=offset+1,math.min(#matches,offset+limit) do table.insert(result,matches[i]) end
    return {query=args.query or args.text,total=#matches,offset=offset,limit=limit,results=result,has_more=offset+#result<#matches}
end

local function refs_for(data)
    local edges={}
    local function add(from_kind,from,id,to_kind,relation)
        if id==nil or tostring(id)=='' then return end
        table.insert(edges,{from={id=from.id,type=from_kind,name=from.name},to={id=tostring(id),type=to_kind},relation=relation})
    end
    for _,row in ipairs(data.rooms or {}) do add('room',row,row.premise_id,'premise','premise_id');for _,id in ipairs(row.shell_object_ids or {}) do add('room',row,id,'object','shell_object_ids') end end
    for _,row in ipairs(data.objects or {}) do
        add('object',row,row.premise_id,'premise','premise_id');add('object',row,row.room_id,'room','room_id')
        if row.parent_id then
            local _,kind=find_row(data,row.parent_id)
            if kind=='group' then add('object',row,row.parent_id,'group','parent_id') else add('object',row,row.parent_id,'object','parent_id') end
        end
    end
    for _,row in ipairs(data.object_groups or {}) do
        add('group',row,row.premise_id,'premise','premise_id');add('group',row,row.room_id,'room','room_id');add('group',row,row.parent_id,'group','parent_id')
        for _,id in ipairs(row.object_ids or {}) do add('group',row,id,'object','object_ids') end
    end
    for _,row in ipairs(data.object_prefabs or {}) do add('prefab',row,row.source_group_id,'group','source_group_id') end
    for _,row in ipairs(data.volumes or {}) do add('volume',row,row.premise_id,'premise','premise_id');add('volume',row,row.room_id,'room','room_id') end
    for _,row in ipairs(data.cameras or {}) do
        add('camera',row,row.premise_id,'premise','premise_id');add('camera',row,row.room_id,'room','room_id')
        if row.look_at then add('camera',row,row.look_at.location_id,'location','look_at.location_id') end
    end
    for _,row in ipairs(data.routes or {}) do for _,id in ipairs(row.location_ids or {}) do add('route',row,id,'location','location_ids') end end
    for _,row in ipairs(data.scenes or {}) do
        add('scene',row,row.premise_id,'premise','premise_id')
        for _,kind in ipairs({'room','object','location','volume','camera','route'}) do
            local field=kind..'_ids';for _,id in ipairs(row[field] or {}) do add('scene',row,id,kind,field) end
        end
    end
    return edges
end

function ProjectBrowser:refs(args)
    args=args or {};local id=args.item_id or args.id
    if type(id)~='string' or id=='' then return nil,'item_id is required' end
    local row,kind,err=find_row(self.app.model.data,id,args.item_type or args.type);if not row then return nil,err end
    local direction=args.direction or 'both';if direction~='both' and direction~='inbound' and direction~='outbound' then return nil,'direction must be both, inbound or outbound' end
    local limit=math.floor(tonumber(args.limit) or 200);if limit<1 or limit>1000 then return nil,'limit must be between 1 and 1000' end
    local edges={};local all=refs_for(self.app.model.data)
    for _,edge in ipairs(all) do
        local outgoing=edge.from.id==id and edge.from.type==kind
        local incoming=edge.to.id==id and (edge.to.type==kind or edge.to.type==nil)
        if (direction=='both' and (outgoing or incoming)) or (direction=='outbound' and outgoing) or (direction=='inbound' and incoming) then
            local value=Util.deepcopy(edge);local target,target_kind=find_row(self.app.model.data,value.to.id,value.to.type)
            if target then value.to=summary(target_kind,target) else value.to.missing=true end
            if incoming then value.direction='inbound' else value.direction='outbound' end
            table.insert(edges,value)
        end
    end
    local result={item=summary(kind,row),direction=direction,total=#edges,edges={}}
    for i=1,math.min(limit,#edges) do table.insert(result.edges,edges[i]) end
    result.truncated=#edges>limit
    return result
end

local function direct_children(data,kind,row)
    local children={};local function push(child_kind,child) if child then table.insert(children,{kind=child_kind,row=child}) end end
    local id=row and row.id
    if not kind then return children end
    if kind=='project' then
        for _,child_kind in ipairs(TYPE_ORDER) do table.insert(children,{collection=child_kind}) end
    elseif KINDS[kind] and not row then
        for _,child in ipairs(rows_for(data,kind) or {}) do push(kind,child) end
    elseif kind=='premise' then
        for _,room in ipairs(data.rooms or {}) do if room.premise_id==id then push('room',room) end end
        local grouped={};for _,group in ipairs(data.object_groups or {}) do for _,object_id in ipairs(group.object_ids or {}) do grouped[object_id]=true end end
        for _,child_kind in ipairs({'object','group','volume','camera','scene'}) do for _,child in ipairs(rows_for(data,child_kind) or {}) do
            if child.premise_id==id and not (child.room_id and child.room_id~='') and not (child_kind=='object' and (child.parent_id or grouped[child.id])) and not (child_kind=='group' and child.parent_id) then push(child_kind,child) end
        end end
    elseif kind=='room' then
        local grouped={};for _,group in ipairs(data.object_groups or {}) do for _,object_id in ipairs(group.object_ids or {}) do grouped[object_id]=true end end
        for _,child_kind in ipairs({'object','group','volume','camera'}) do for _,child in ipairs(rows_for(data,child_kind) or {}) do
            if child.room_id==id and not (child_kind=='object' and (child.parent_id or grouped[child.id])) and not (child_kind=='group' and child.parent_id) then push(child_kind,child) end
        end end
    elseif kind=='group' then
        for _,group in ipairs(data.object_groups or {}) do if group.parent_id==id then push('group',group) end end
        local members={};for _,group in ipairs(data.object_groups or {}) do if group.id==id then for _,object_id in ipairs(group.object_ids or {}) do members[object_id]=true end;break end end
        for _,object in ipairs(data.objects or {}) do if members[object.id] then push('object',object) end end
    elseif kind=='scene' and row then
        for _,child_kind in ipairs({'room','object','location','volume','camera','route'}) do
            for _,id_value in ipairs(row[child_kind..'_ids'] or {}) do local child=find_row(data,id_value,child_kind);push(child_kind,child) end
        end
    elseif kind=='route' and row then
        for _,location_id in ipairs(row.location_ids or {}) do local location=find_row(data,location_id,'location');push('location',location) end
    else
        local rows=rows_for(data,kind)
        for _,child in ipairs(rows or {}) do
            local parent=child.parent_id
            if parent==id then push(kind,child) end
        end
    end
    table.sort(children,function(a,b)
        local name_a=a.collection and KINDS[a.collection].label or tostring(a.row.name or a.row.id)
        local name_b=b.collection and KINDS[b.collection].label or tostring(b.row.name or b.row.id)
        if name_a:lower()~=name_b:lower() then return name_a:lower()<name_b:lower() end
        return tostring((a.row or {}).id or a.collection)<tostring((b.row or {}).id or b.collection)
    end)
    return children
end

function ProjectBrowser:tree(args)
    args=args or {};local data=self.app.model.data;local limit=math.floor(tonumber(args.limit) or 250)
    local depth=math.floor(tonumber(args.max_depth) or 2)
    if limit<1 or limit>1000 then return nil,'limit must be between 1 and 1000' end
    if depth<1 or depth>8 then return nil,'max_depth must be between 1 and 8' end
    local root_id=args.root_id or args.id;local root_kind,root_row
    if root_id and root_id~='' then
        if type(root_id)~='string' then return nil,'root_id must be a string' end
        if root_id:sub(1,11)=='collection:' then
            root_kind=root_id:sub(12);if not KINDS[root_kind] then return nil,'unknown collection root: '..root_kind end
        else
            root_row,root_kind=find_row(data,root_id,args.root_type);if not root_row then return nil,root_kind or 'tree root not found' end
        end
    else root_kind='project' end
    local emitted=0;local truncated=false
    local function build(kind,row,collection,level)
        if emitted>=limit then truncated=true;return nil end
        emitted=emitted+1
        local node
        if collection then
            local count=#(rows_for(data,collection) or {})
            node={id='collection:'..collection,type='collection',item_type=collection,name=KINDS[collection].label,count=count,children={}}
        else node=summary(kind,row);node.children={} end
        if level<depth and emitted<limit then
            local children=direct_children(data,collection and collection or kind,row)
            node.total_children=#children
            for _,child in ipairs(children) do
                local item=build(child.kind,child.row,child.collection,level+1)
                if item then table.insert(node.children,item) end
                if emitted>=limit and #node.children<#children then node.children_truncated=true;truncated=true;break end
            end
        else node.total_children=#direct_children(data,collection and collection or kind,row);node.expandable=node.total_children>0 end
        return node
    end
    local roots
    if root_kind=='project' then roots=direct_children(data,'project',nil)
    elseif rows_for(data,root_kind) and not root_row then roots={{collection=root_kind}}
    else roots=direct_children(data,root_kind,root_row) end
    local nodes={};for _,child in ipairs(roots) do
        local node=build(child.kind,child.row,child.collection,1);if node then table.insert(nodes,node) end
        if emitted>=limit and #nodes<#roots then truncated=true;break end
    end
    return {root=root_id or 'project',max_depth=depth,limit=limit,node_count=emitted,truncated=truncated,nodes=nodes}
end

return ProjectBrowser
