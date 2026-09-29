local Util=require('modules/util')

-- Environment grammar. Reusable rules turn a box of space into a layout:
--   Corridor -> room + door every N m on both walls + ceiling lights + cable tray
-- A grammar is a set of named rules. A rule runs in a scope (an oriented box:
-- x along its length, y across, z up, origin at its min corner) and is a list
-- of operations. Structural operations cut the scope into child scopes and run
-- rules in them:
--   split   divide along an axis into absolute (expression) and relative (~w) parts
--   repeat  tiles along an axis: every (about N m, fitted), step (exactly N m) or count
--   place   a child box at a position/size (optional yaw)
--   walls   strips along the inside of chosen sides, facing inward
--   call / choose / chance / set  run a rule here, pick one (weighted, seeded), maybe, set variables
-- Terminal operations produce content:
--   room    a parametric room filling the scope (the scope becomes its interior)
--   door / window  an opening in the enclosing room's nearest wall (also cut into the room behind it)
--   geometry  procedural geometry; asset  a Project Asset; light  a static light
--   volume  a volume filling the scope; marker  a location
-- Expansion is pure and deterministic for a seed. The result is compiled into
-- one authoring plan (version 2) and executed by modules/authoring_plans.lua:
-- validated first, one undo step, full rollback on failure. A generation is an
-- EDL-style build (doc grammar_<build id>), so regenerating replaces it.
local Grammar={};Grammar.__index=Grammar

local MAX_DEPTH=32
local MAX_CALLS=5000
local MAX_ITEMS=1900
local MAX_ROOMS=200
local MAX_INCLUDE=4
local LIBRARY_PATH='grammars/library.json'
local ID='^[%a_][%w_%-]*$'
local RULE_NAME='^[%a_][%w_]*$'
local AXES={x=true,y=true,z=true}
local SIDES={'south','north','east','west'}
local SIDE_OK={south=true,north=true,east=true,west=true}
local OPPOSITE={south='north',north='south',east='west',west='east'}
local STRUCTURAL={split=true,['repeat']=true,place=true,walls=true,call=true,choose=true,chance=true,set=true}
local TERMINALS={room=true,door=true,window=true,geometry=true,asset=true,light=true,volume=true,marker=true}
local OP_META={['if']=true,name=true,comment=true}

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function round(v,p) local m=10^(p or 4);return math.floor(v*m+0.5)/m end

---------------------------------------------------------------------------
-- Expressions: numbers, 'strings', variables ($ optional), + - * / % ^,
-- comparisons, and/or/not (&& || !), c ? a : b, and functions.
---------------------------------------------------------------------------
local Expr={}
local CACHE={}

local function tokenize(src)
    local toks,i,n={},1,#src
    while i<=n do
        local c=src:sub(i,i)
        if c:match('%s') then i=i+1
        elseif c:match('%d') or (c=='.' and src:sub(i+1,i+1):match('%d')) then
            local s,e=src:find('^%d*%.?%d*[eE][%+%-]?%d+',i);if not s then s,e=src:find('^%d*%.?%d*',i) end
            toks[#toks+1]={t='num',v=tonumber(src:sub(s,e))};i=e+1
        elseif c:match('[%a_%$]') then
            local s,e=src:find('^%$?[%a_][%w_]*',i);if not s then error('bad name at "'..src:sub(i)..'"',0) end
            local w=src:sub(s,e):gsub('^%$','')
            if w=='and' or w=='or' or w=='not' then toks[#toks+1]={t='op',v=w}
            elseif w=='true' or w=='false' then toks[#toks+1]={t='bool',v=w=='true'}
            else toks[#toks+1]={t='id',v=w} end
            i=e+1
        elseif c=="'" or c=='"' then
            local e=src:find(c,i+1,true);if not e then error('unterminated string',0) end
            toks[#toks+1]={t='str',v=src:sub(i+1,e-1)};i=e+1
        else
            local two=src:sub(i,i+1)
            if two=='<=' or two=='>=' or two=='==' or two=='!=' or two=='~=' or two=='&&' or two=='||' then
                toks[#toks+1]={t='op',v=(two=='&&' and 'and') or (two=='||' and 'or') or (two=='~=' and '!=') or two};i=i+2
            elseif c:match('[%+%-%*/%%%^%(%),<>!%?:]') then toks[#toks+1]={t='op',v=c=='!' and 'not' or c};i=i+1
            else error('unexpected "'..c..'"',0) end
        end
    end
    return toks
end

local function parse(src)
    local toks=tokenize(src);local pos=1
    local function peek() return toks[pos] end
    local function isop(v) local t=toks[pos];return t and t.t=='op' and t.v==v end
    local function take(v) if not isop(v) then error('expected "'..v..'"',0) end;pos=pos+1 end
    local expr
    local function atom()
        local t=toks[pos];if not t then error('unexpected end',0) end
        pos=pos+1
        if t.t=='num' then return {k='lit',v=t.v} end
        if t.t=='str' or t.t=='bool' then return {k='lit',v=t.v} end
        if t.t=='id' then
            if isop('(') then
                pos=pos+1;local args={}
                if not isop(')') then repeat args[#args+1]=expr() until not (isop(',') and take(',')==nil) end
                take(')');return {k='call',name=t.v,args=args}
            end
            return {k='var',name=t.v}
        end
        if t.t=='op' and t.v=='(' then local e=expr();take(')');return e end
        error('unexpected "'..tostring(t.v)..'"',0)
    end
    local unary
    local function pow() local a=atom();if isop('^') then pos=pos+1;return {k='bin',op='^',a=a,b=unary()} end;return a end
    unary=function() if isop('-') then pos=pos+1;return {k='un',op='-',a=unary()} end;if isop('+') then pos=pos+1;return unary() end;return pow() end
    local function mul() local a=unary();while isop('*') or isop('/') or isop('%') do local op=peek().v;pos=pos+1;a={k='bin',op=op,a=a,b=unary()} end;return a end
    local function add() local a=mul();while isop('+') or isop('-') do local op=peek().v;pos=pos+1;a={k='bin',op=op,a=a,b=mul()} end;return a end
    local CMP={['<']=true,['<=']=true,['>']=true,['>=']=true,['==']=true,['!=']=true}
    local function cmp() local a=add();local t=peek();if t and t.t=='op' and CMP[t.v] then pos=pos+1;return {k='bin',op=t.v,a=a,b=add()} end;return a end
    local function lnot() if isop('not') then pos=pos+1;return {k='un',op='not',a=lnot()} end;return cmp() end
    local function land() local a=lnot();while isop('and') do pos=pos+1;a={k='and',a=a,b=lnot()} end;return a end
    local function lor() local a=land();while isop('or') do pos=pos+1;a={k='or',a=a,b=land()} end;return a end
    expr=function() local c=lor();if isop('?') then pos=pos+1;local a=expr();take(':');return {k='tern',c=c,a=a,b=expr()} end;return c end
    local tree=expr()
    if pos<=#toks then error('unexpected "'..tostring(toks[pos].v)..'"',0) end
    return tree
end

local function truth(v) return v~=nil and v~=false and v~=0 end
Grammar.truth=truth

local FN={
    min=function(_,a) local m=a[1];for i=2,#a do m=math.min(m,a[i]) end;return m end,
    max=function(_,a) local m=a[1];for i=2,#a do m=math.max(m,a[i]) end;return m end,
    floor=function(_,a) return math.floor(a[1]) end,ceil=function(_,a) return math.ceil(a[1]) end,
    round=function(_,a) local m=10^(a[2] or 0);return math.floor(a[1]*m+0.5)/m end,
    abs=function(_,a) return math.abs(a[1]) end,sqrt=function(_,a) return math.sqrt(a[1]) end,
    sin=function(_,a) return math.sin(math.rad(a[1])) end,cos=function(_,a) return math.cos(math.rad(a[1])) end,
    clamp=function(_,a) return math.max(a[2],math.min(a[3],a[1])) end,
    ['if']=function(_,a) if truth(a[1]) then return a[2] end;return a[3] end,
    rand=function(ctx,a) local r=ctx.rng();if a[1] and a[2] then return a[1]+(a[2]-a[1])*r end;return r end,
    randint=function(ctx,a) return math.floor(a[1]+(a[2]-a[1]+1)*ctx.rng()) end,
    opposite=function(_,a) return OPPOSITE[a[1]] or error('opposite() needs north, south, east or west',0) end,
}
local ARITY={min=-1,max=-1,floor=1,ceil=1,round=-1,abs=1,sqrt=1,sin=1,cos=1,clamp=3,['if']=3,rand=-1,randint=2,opposite=1}

local function eval_node(node,ctx)
    local k=node.k
    if k=='lit' then return node.v end
    if k=='var' then
        local v=ctx.vars[node.name]
        if v==nil then error('unknown variable '..node.name,0) end
        return v
    end
    if k=='un' then local a=eval_node(node.a,ctx);if node.op=='not' then return not truth(a) end;if type(a)~='number' then error('- needs a number',0) end;return -a end
    if k=='and' then local a=eval_node(node.a,ctx);if not truth(a) then return a end;return eval_node(node.b,ctx) end
    if k=='or' then local a=eval_node(node.a,ctx);if truth(a) then return a end;return eval_node(node.b,ctx) end
    if k=='tern' then if truth(eval_node(node.c,ctx)) then return eval_node(node.a,ctx) end;return eval_node(node.b,ctx) end
    if k=='call' then
        local f=FN[node.name];if not f then error('unknown function '..node.name..'()',0) end
        local args={};for i,a in ipairs(node.args) do args[i]=eval_node(a,ctx) end
        local ar=ARITY[node.name]
        if ar>=0 and #args~=ar then error(node.name..'() takes '..ar..' argument(s)',0) end
        if ar<0 and #args==0 and node.name~='rand' then error(node.name..'() needs arguments',0) end
        if node.name~='if' and node.name~='opposite' then for _,v in ipairs(args) do if type(v)~='number' then error(node.name..'() needs numbers',0) end end end
        return f(ctx,args)
    end
    local a,b=eval_node(node.a,ctx),eval_node(node.b,ctx)
    local op=node.op
    if op=='==' then return a==b end
    if op=='!=' then return a~=b end
    if type(a)~='number' or type(b)~='number' then error('"'..op..'" needs numbers',0) end
    if op=='+' then return a+b elseif op=='-' then return a-b elseif op=='*' then return a*b
    elseif op=='/' then if b==0 then error('division by zero',0) end;return a/b
    elseif op=='%' then if b==0 then error('modulo by zero',0) end;return a%b
    elseif op=='^' then return a^b
    elseif op=='<' then return a<b elseif op=='<=' then return a<=b elseif op=='>' then return a>b elseif op=='>=' then return a>=b end
    error('bad operator '..tostring(op),0)
end

function Expr.compile(src)
    local tree=CACHE[src]
    if not tree then
        local ok,res=pcall(parse,src);if not ok then return nil,res end
        tree=res;CACHE[src]=tree
    end
    return tree
end

-- Evaluate an expression with variables (and rand() from rng).
function Grammar.eval(src,vars,rng)
    local tree,err=Expr.compile(tostring(src));if not tree then return nil,err end
    local ok,res=pcall(eval_node,tree,{vars=vars or {},rng=rng or function() return 0.5 end})
    if not ok then return nil,res end
    return res
end

---------------------------------------------------------------------------
-- Validation of grammar documents
---------------------------------------------------------------------------
local function op_kind(op)
    if type(op)=='string' then return 'call' end
    if type(op)~='table' then return nil,'an operation must be a rule name or an object' end
    local kind
    for key in pairs(op) do
        if STRUCTURAL[key] or TERMINALS[key] then
            if kind then return nil,'an operation has both '..kind..' and '..key end
            kind=key
        elseif not OP_META[key] then return nil,'unknown operation "'..tostring(key)..'"' end
    end
    if not kind then return nil,'an operation needs one of split, repeat, place, walls, call, choose, chance, set, room, door, window, geometry, asset, light, volume, marker' end
    return kind
end
Grammar.op_kind=op_kind

local check_ops
local function check_child(spec,rules,where,errors)
    if type(spec)~='table' then errors[#errors+1]=where..' must be an object';return end
    if spec.symbol~=nil then
        if type(spec.symbol)~='string' or not rules[spec.symbol] then errors[#errors+1]=where..': unknown rule '..tostring(spec.symbol) end
    elseif spec['do']~=nil then check_ops(spec['do'],rules,where,errors)
    end
    if spec.params~=nil and type(spec.params)~='table' then errors[#errors+1]=where..': params must be an object' end
end

check_ops=function(ops,rules,where,errors)
    if type(ops)~='table' then errors[#errors+1]=where..': do must be a list';return end
    for i,op in ipairs(ops) do
        local w=where..' op '..i
        local kind,err=op_kind(op)
        if not kind then errors[#errors+1]=w..': '..err
        elseif type(op)=='string' then if not rules[op] then errors[#errors+1]=w..': unknown rule '..op end
        else
            local body=op[kind]
            if kind=='call' then
                if type(body)=='string' then if not rules[body] then errors[#errors+1]=w..': unknown rule '..body end else check_child(body,rules,w..' call',errors) end
            elseif kind=='split' then
                if type(body)~='table' or not AXES[body.axis] or type(body.parts)~='table' or #body.parts==0 then errors[#errors+1]=w..': split needs axis x|y|z and parts'
                else for j,p in ipairs(body.parts) do if type(p)~='table' or p.size==nil then errors[#errors+1]=w..' part '..j..' needs a size' else check_child(p,rules,w..' part '..j,errors) end end end
            elseif kind=='repeat' then
                if type(body)~='table' or not AXES[body.axis] then errors[#errors+1]=w..': repeat needs axis x|y|z'
                elseif body.every==nil and body.step==nil and body.count==nil then errors[#errors+1]=w..': repeat needs every, step or count'
                else check_child(body,rules,w..' repeat',errors) end
            elseif kind=='place' or kind=='walls' then check_child(body,rules,w..' '..kind,errors)
            elseif kind=='choose' then
                local options=type(body)=='table' and (body.options or body) or nil
                if type(options)~='table' or #options==0 then errors[#errors+1]=w..': choose needs options'
                else for j,o in ipairs(options) do check_child(o,rules,w..' option '..j,errors) end end
            elseif kind=='chance' then
                check_child(body,rules,w..' chance',errors)
                if type(body)=='table' and body['else']~=nil then check_child(body['else'],rules,w..' chance else',errors) end
            elseif kind=='set' then if type(body)~='table' then errors[#errors+1]=w..': set needs an object of variables' end
            elseif kind=='geometry' then
                if type(body)~='table' or type(body.generator)~='string' then errors[#errors+1]=w..': geometry needs a generator'
                else
                    local P=package.loaded['modules/procedural']
                    if P and not P.GENERATORS[body.generator] then errors[#errors+1]=w..': unknown generator '..body.generator end
                end
            elseif kind=='asset' then if type(body)~='table' or (body.asset_id==nil and body.asset_query==nil) then errors[#errors+1]=w..': asset needs asset_id or asset_query' end
            elseif type(body)~='table' then errors[#errors+1]=w..': '..kind..' needs an object' end
        end
    end
end

local function check_rule(name,rule,rules,errors)
    local where='rule '..name
    if rule.variants then
        if type(rule.variants)~='table' or #rule.variants==0 then errors[#errors+1]=where..': variants must be a non-empty list';return end
        for j,v in ipairs(rule.variants) do
            if type(v)~='table' or type(v['do'])~='table' then errors[#errors+1]=where..' variant '..j..' needs do'
            else check_ops(v['do'],rules,where..' variant '..j,errors) end
        end
    else check_ops(rule['do'],rules,where,errors) end
    if rule.params~=nil and type(rule.params)~='table' then errors[#errors+1]=where..': params must be an object' end
end

-- Normalize a grammar document. `resolve(id)` returns another grammar for include.
function Grammar.normalize(doc,resolve,seen)
    if type(doc)~='table' then return nil,'a grammar must be an object' end
    local g={id=doc.id,name=doc.name,description=doc.description or '',start=doc.start,params={},rules={},include={}}
    if g.id~=nil and (type(g.id)~='string' or not g.id:match(ID)) then return nil,'id must start with a letter and use letters, digits, _ or -' end
    g.id=g.id or 'inline';g.name=type(g.name)=='string' and g.name~='' and g.name or g.id
    seen=seen or {};if seen[g.id] then return nil,'include cycle through '..g.id end
    -- Included grammars first; this document's params and rules override theirs.
    local includes=doc.include;if type(includes)=='string' then includes={includes} end
    if includes~=nil and type(includes)~='table' then return nil,'include must be a grammar id or a list of ids' end
    local depth=0;for _ in pairs(seen) do depth=depth+1 end
    for _,inc in ipairs(includes or {}) do
        if depth>=MAX_INCLUDE then return nil,'includes nest deeper than '..MAX_INCLUDE end
        local other=resolve and resolve(inc);if not other then return nil,'included grammar not found: '..tostring(inc) end
        local s2=Util.deepcopy(seen);s2[g.id]=true
        local og,err=Grammar.normalize(other,resolve,s2);if not og then return nil,'include '..tostring(inc)..': '..err end
        for k,v in pairs(og.params) do g.params[k]=v end
        for k,v in pairs(og.rules) do g.rules[k]=v end
        g.include[#g.include+1]=inc
        g.size=g.size or og.size
    end
    for k,v in pairs(type(doc.params)=='table' and doc.params or {}) do
        if type(k)~='string' or not k:match(RULE_NAME) then return nil,'param names must be identifiers: '..tostring(k) end
        g.params[k]=Util.deepcopy(v)
    end
    if doc.rules~=nil and type(doc.rules)~='table' then return nil,'rules must be an object of named rules' end
    for name,rule in pairs(doc.rules or {}) do
        if type(name)~='string' or not name:match(RULE_NAME) then return nil,'rule names must be identifiers: '..tostring(name) end
        if type(rule)~='table' then return nil,'rule '..name..' must be a list of operations or an object' end
        if rule[1]~=nil or next(rule)==nil then rule={['do']=rule} end
        g.rules[name]=Util.deepcopy(rule)
    end
    if next(g.rules)==nil then return nil,'a grammar needs at least one rule' end
    if doc.size~=nil then
        local s=doc.size;local x,y,z=num(s.x or s[1]),num(s.y or s[2]),num(s.z or s[3])
        if not x or not y or not z or x<=0 or y<=0 or z<=0 then return nil,'size must be [x, y, z] in metres' end
        g.size={x,y,z}
    end
    if g.start~=nil and (type(g.start)~='string' or not g.rules[g.start]) then return nil,'start rule not found: '..tostring(g.start) end
    local errors={}
    for name,rule in pairs(g.rules) do check_rule(name,rule,g.rules,errors) end
    table.sort(errors)
    if #errors>0 then return nil,table.concat(errors,'; '),errors end
    return g
end

---------------------------------------------------------------------------
-- Scopes
---------------------------------------------------------------------------
local function rot(yaw,x,y) local r=math.rad(yaw);local c,s=math.cos(r),math.sin(r);return x*c-y*s,x*s+y*c end
local function wrap(yaw) yaw=yaw%360;if yaw>180 then yaw=yaw-360 end;return round(yaw,6) end
local function to_layout(scope,p) local x,y=rot(scope.yaw,p.x,p.y);return {x=scope.o.x+x,y=scope.o.y+y,z=scope.o.z+p.z} end
-- Child scope of size d whose footprint centre is c (scope-local, c.z = bottom), turned r degrees about that centre.
local function child_scope(scope,c,d,r)
    local C=to_layout(scope,c);local Y=wrap(scope.yaw+(r or 0))
    local hx,hy=rot(Y,d.x/2,d.y/2)
    return {o={x=C.x-hx,y=C.y-hy,z=C.z},yaw=Y,s={x=d.x,y=d.y,z=d.z}}
end
Grammar.child_scope=child_scope
Grammar.to_layout=to_layout

---------------------------------------------------------------------------
-- Expansion
---------------------------------------------------------------------------
local function hash(s) local h=5381;for i=1,#s do h=(h*33+s:byte(i))%2147483647 end;if h==0 then h=1 end;return h end

local function fail(ctx,msg) error({grammar_error=(ctx and ctx.path or 'grammar')..': '..msg},0) end

local function new_ctx(state,parent,scope,label)
    local vars=setmetatable({},{__index=parent and parent.vars or state.globals})
    local ctx={state=state,parent=parent,scope=scope,vars=vars,depth=parent and parent.depth+1 or 0,room=parent and parent.room or nil,
        path=parent and (parent.path..'/'..label) or label}
    vars.sx,vars.sy,vars.sz=round(scope.s.x,6),round(scope.s.y,6),round(scope.s.z,6);vars.depth=ctx.depth
    local seedv=hash(tostring(state.seed)..'|'..ctx.path)
    ctx.rng=function() seedv=(seedv*16807)%2147483647;return seedv/2147483647 end
    if ctx.depth>MAX_DEPTH then fail(ctx,'rules nest deeper than '..MAX_DEPTH..' (does a rule always call itself?)') end
    return ctx
end

local function set_scope(ctx,scope) ctx.scope=scope;ctx.vars.sx,ctx.vars.sy,ctx.vars.sz=round(scope.s.x,6),round(scope.s.y,6),round(scope.s.z,6) end

local function expr(ctx,v,what)
    if type(v)=='number' or type(v)=='boolean' then return v end
    if type(v)~='string' then fail(ctx,what..' must be a number or an expression') end
    local tree,err=Expr.compile((v:gsub('^%s*=','')))
    if not tree then fail(ctx,what..': '..err) end
    local ok,res=pcall(eval_node,tree,ctx)
    if not ok then fail(ctx,what..': '..tostring(res)) end
    return res
end
local function number(ctx,v,what)
    local r=expr(ctx,v,what)
    if type(r)~='number' or r~=r or r==math.huge or r==-math.huge then fail(ctx,what..' is not a number ('..tostring(r)..')') end
    return r
end
-- Generic value: '=expr' evaluates, '$name' is a variable, tables recurse, others are literal.
local function value(ctx,v,what)
    if type(v)=='string' then
        if v:match('^%s*=') then return expr(ctx,v,what) end
        if v:sub(1,1)=='$' then
            local name=v:sub(2);if not name:match(RULE_NAME) then fail(ctx,what..': "'..v..'" is not a variable (use =expression)') end
            local r=ctx.vars[name];if r==nil then fail(ctx,what..': unknown variable '..name) end
            return Util.deepcopy(r)
        end
        return v
    end
    if type(v)=='table' then local out={};for k,x in pairs(v) do out[k]=value(ctx,x,what..'.'..tostring(k)) end;return out end
    return v
end
local function vec3(ctx,v,what,default)
    if v==nil then return default end
    if type(v)~='table' then fail(ctx,what..' must be [x, y, z]') end
    return {x=number(ctx,v.x or v[1] or 0,what..'.x'),y=number(ctx,v.y or v[2] or 0,what..'.y'),z=number(ctx,v.z or v[3] or 0,what..'.z')}
end
local function cond(ctx,op) if op['if']==nil then return true end;return truth(expr(ctx,op['if'],'if')) end
local function interpolate(ctx,s)
    if type(s)~='string' then return nil end
    return (s:gsub('{([^}]+)}',function(e) local r=expr(ctx,e,'name');if type(r)=='number' and r==math.floor(r) then return string.format('%d',r) end;return tostring(r) end))
end

local run_ops,run_rule,run_inline

-- Run a child (symbol or inline do) in a new scope; params are evaluated in the child.
local function run_child(ctx,spec,scope,extra,label)
    local state=ctx.state
    if type(spec)=='string' then spec={symbol=spec} end
    local child=new_ctx(state,ctx,scope,label..(spec.symbol and (':'..spec.symbol) or ''))
    for k,v in pairs(extra or {}) do child.vars[k]=v end
    for k,v in pairs(spec.params or {}) do child.vars[k]=value(child,v,'params.'..tostring(k)) end
    if spec.symbol then return run_rule(child,spec.symbol) end
    if spec['do'] then return run_ops(child,spec['do']) end
end

-- Run a rule (or inline do) in this same scope: a room it makes, its variables
-- and its narrowed scope stay in effect for the caller's later operations.
run_inline=function(ctx,spec)
    if type(spec)=='string' then spec={symbol=spec} end
    for k,v in pairs(spec.params or {}) do ctx.vars[k]=value(ctx,v,'params.'..tostring(k)) end
    if spec.symbol then local prev=ctx.rule;run_rule(ctx,spec.symbol);ctx.rule=prev
    elseif spec['do'] then run_ops(ctx,spec['do']) end
end

run_rule=function(ctx,name)
    local state=ctx.state;local rule=state.g.rules[name]
    if not rule then fail(ctx,'unknown rule '..tostring(name)) end
    state.calls=state.calls+1
    if state.calls>MAX_CALLS then fail(ctx,'more than '..MAX_CALLS..' rule calls; the grammar does not terminate or the layout is too large') end
    state.rule_counts[name]=(state.rule_counts[name] or 0)+1
    state.level=state.level+1
    if state.level>MAX_DEPTH*2 then fail(ctx,'rules nest deeper than '..(MAX_DEPTH*2)..' (does a rule always call itself?)') end
    ctx.rule=name
    for k,v in pairs(rule.params or {}) do if rawget(ctx.vars,k)==nil then ctx.vars[k]=value(ctx,v,'params.'..tostring(k)) end end
    local ops=rule['do']
    if rule.variants then
        local eligible,total={},0
        for _,v in ipairs(rule.variants) do
            if cond(ctx,v) then local w=number(ctx,v.weight or 1,'weight');if w>0 then eligible[#eligible+1]={v=v,w=w};total=total+w end end
        end
        if total==0 then state.level=state.level-1;return end
        local r=ctx.rng()*total;ops=eligible[#eligible].v['do']
        for _,e in ipairs(eligible) do if r<e.w then ops=e.v['do'];break end;r=r-e.w end
    elseif rule['if']~=nil and not cond(ctx,rule) then state.level=state.level-1;return end
    run_ops(ctx,ops)
    state.level=state.level-1
end

-- Tile positions along a length: centres and the tile size.
local function tiles(ctx,body,L)
    local margin=number(ctx,body.margin or 0,'margin')
    local usable=L-2*margin
    if usable<=1e-6 then return {},0 end
    local count=body.count~=nil and math.floor(number(ctx,body.count,'count')+1e-9) or nil
    local out,size={},nil
    if body.step~=nil then
        local step=number(ctx,body.step,'step');if step<=0.01 then fail(ctx,'step must be greater than 0.01 m') end
        size=body.size~=nil and number(ctx,body.size,'size') or step
        local n=count or math.floor((usable-size)/step+1e-6)+1
        if n<1 then return {},size end
        local first
        if body.offset~=nil then first=margin+number(ctx,body.offset,'offset')
            if not count then n=math.floor((L-margin-size/2-first)/step+1e-6)+1 end
        else first=margin+(usable-(n-1)*step)/2 end
        for k=0,n-1 do out[#out+1]=first+k*step end
    else
        local n
        if count then n=count
        else
            local every=number(ctx,body.every,'every');if every<=0.01 then fail(ctx,'every must be greater than 0.01 m') end
            n=math.max(1,math.floor(usable/every+0.5))
        end
        if n<1 then return {},0 end
        local spacing=usable/n
        size=body.size~=nil and number(ctx,body.size,'size') or spacing
        for k=0,n-1 do out[#out+1]=margin+(k+0.5)*spacing end
    end
    if #out>MAX_ITEMS then fail(ctx,'repeat makes '..#out..' tiles; the limit is '..MAX_ITEMS) end
    if size<=0 then fail(ctx,'tile size must be positive') end
    return out,size
end

local function emit(ctx,item)
    local state=ctx.state
    if #state.items>=MAX_ITEMS then fail(ctx,'the layout has more than '..MAX_ITEMS..' items') end
    item.path=ctx.path;item.rule=ctx.rule
    item.room=ctx.room
    state.items[#state.items+1]=item
    state.kind_counts[item.kind]=(state.kind_counts[item.kind] or 0)+1
    return item
end

local function unique_name(state,name)
    local base=name;local n=state.names[base] or 0
    state.names[base]=n+1
    if n==0 then return base end
    return base..' '..(n+1)
end

-- Place transform of a point in the scope (layout frame).
local function point_item(ctx,body,default_at)
    local at=vec3(ctx,body.at,'at',default_at)
    local p=to_layout(ctx.scope,at)
    return {offset={x=round(p.x),y=round(p.y),z=round(p.z)},yaw=wrap(ctx.scope.yaw+number(ctx,body.yaw or 0,'yaw')),
        pitch=body.pitch~=nil and number(ctx,body.pitch,'pitch') or nil,roll=body.roll~=nil and number(ctx,body.roll,'roll') or nil}
end

-- Room frame helpers: layout point -> room-local (x across, y along, from the floor centre).
local function room_local(room,p)
    local x,y=rot(-room.yaw,p.x-room.center.x,p.y-room.center.y)
    return x,y
end
local function nearest_wall(room,x,y)
    local W,L=room.width,room.length
    local d={north=math.abs(L/2-y),south=math.abs(y+L/2),east=math.abs(W/2-x),west=math.abs(x+W/2)}
    local best,second
    for _,s in ipairs(SIDES) do if not best or d[s]<d[best] then second=best;best=s elseif not second or d[s]<d[second] then second=s end end
    return best,d[best],d[second]
end

local function opening(ctx,kind,body)
    local room=ctx.room;if not room then fail(ctx,kind..' needs an enclosing room (run it after a room operation)') end
    local c=to_layout(ctx.scope,{x=ctx.scope.s.x/2,y=ctx.scope.s.y/2,z=0})
    local x,y=room_local(room,c)
    local wall=value(ctx,body.wall,'wall')
    if wall==nil or wall=='auto' then
        local best,d1,d2=nearest_wall(room,x,y)
        if math.abs(d1-d2)<1e-3 then fail(ctx,kind..' is as close to the '..best..' wall as to another; set wall') end
        wall=best
    end
    if not SIDE_OK[wall] then fail(ctx,kind..' wall must be north, south, east, west or auto') end
    local o={wall=wall,offset=round((wall=='north' or wall=='south') and x or y,4)}
    o.offset=o.offset+number(ctx,body.shift or 0,'shift')
    o.width=number(ctx,body.width or (kind=='door' and 1 or 1.5),'width');o.height=number(ctx,body.height or (kind=='door' and 2.1 or 1.2),'height')
    if kind=='window' then o.sill=number(ctx,body.sill or 1,'sill');o.mullions_x=body.mullions_x and number(ctx,body.mullions_x,'mullions_x') or nil;o.mullions_y=body.mullions_y and number(ctx,body.mullions_y,'mullions_y') or nil
        if body.glass~=nil then o.glass=truth(value(ctx,body.glass,'glass')) end end
    if body.frame~=nil then o.frame=truth(value(ctx,body.frame,'frame')) end
    if body.frame_width~=nil then o.frame_width=number(ctx,body.frame_width,'frame_width') end
    local list=kind=='door' and room.doors or room.windows
    list[#list+1]=o
    room.connect[o]=body.connect==nil or truth(value(ctx,body.connect,'connect'))
    ctx.state.kind_counts[kind]=(ctx.state.kind_counts[kind] or 0)+1
    -- An optional door leaf asset stands in the opening.
    if kind=='door' and (body.asset_id or body.asset_query) then
        local T=room.T;local lx,ly
        if wall=='north' then lx,ly=o.offset,room.length/2+T/2 elseif wall=='south' then lx,ly=o.offset,-(room.length/2+T/2)
        elseif wall=='east' then lx,ly=room.width/2+T/2,o.offset else lx,ly=-(room.width/2+T/2),o.offset end
        local wx,wy=rot(room.yaw,lx,ly)
        local facing={north=0,south=180,east=-90,west=90}
        emit(ctx,{kind='asset',name=unique_name(ctx.state,interpolate(ctx,body.name) or 'Door'),asset_id=value(ctx,body.asset_id,'asset_id'),asset_query=value(ctx,body.asset_query,'asset_query'),
            offset={x=round(room.center.x+wx),y=round(room.center.y+wy),z=round(room.center.z+room.floor_top)},yaw=wrap(room.yaw+facing[wall]+number(ctx,body.asset_yaw or 0,'asset_yaw'))})
    end
    return o
end

local function room_op(ctx,body)
    local state=ctx.state
    if #state.rooms>=MAX_ROOMS then fail(ctx,'more than '..MAX_ROOMS..' rooms') end
    local RG=package.loaded['modules/room_generator'] or require('modules/room_generator')
    local spec=value(ctx,body,'room')
    spec.name=nil;spec.doors=type(spec.doors)=='table' and spec.doors or {};spec.windows=type(spec.windows)=='table' and spec.windows or {}
    local T=num(spec.wall_thickness,0.15);spec.wall_thickness=T
    local s=ctx.scope.s
    spec.width=round(s.x-2*T,4);spec.length=round(s.y-2*T,4);spec.height=round(num(spec.height,s.z),4)
    if spec.width<1 or spec.length<1 then fail(ctx,string.format('room needs at least 1 m inside its walls; the scope is %.2f x %.2f m',s.x,s.y)) end
    local base=Util.deepcopy(spec);base.doors={};base.windows={}
    local norm,err=RG.normalize(base);if not norm then fail(ctx,'room: '..err) end
    local name=unique_name(state,interpolate(ctx,body.name) or ctx.rule or 'Room')
    local center=to_layout(ctx.scope,{x=s.x/2,y=s.y/2,z=0})
    local floor_top=norm.floor.type=='raised' and norm.floor.raise or 0
    local room={index=#state.rooms+1,name=name,spec=spec,T=T,width=spec.width,length=spec.length,height=spec.height,yaw=ctx.scope.yaw,
        center={x=round(center.x),y=round(center.y),z=round(center.z)},floor_top=floor_top,doors={},windows={},connect={},path=ctx.path,rule=ctx.rule}
    -- Explicit openings from the spec keep their own positions.
    for _,d in ipairs(spec.doors) do room.doors[#room.doors+1]=d end
    for _,w in ipairs(spec.windows) do room.windows[#room.windows+1]=w end
    spec.doors=nil;spec.windows=nil
    room.alias='room_'..room.index
    state.rooms[#state.rooms+1]=room
    state.kind_counts.room=(state.kind_counts.room or 0)+1
    ctx.room=room
    -- The rest of this rule runs in the room's interior.
    set_scope(ctx,child_scope(ctx.scope,{x=s.x/2,y=s.y/2,z=floor_top},{x=spec.width,y=spec.length,z=spec.height-floor_top},0))
    ctx.vars.t=T
    return room
end

local function terminal(ctx,kind,body)
    local state=ctx.state;local s=ctx.scope.s
    if kind=='room' then return room_op(ctx,body) end
    if kind=='door' or kind=='window' then return opening(ctx,kind,body) end
    local label=interpolate(ctx,body.name)
    if kind=='geometry' then
        local params=value(ctx,body.params or {},'params')
        if body.generator=='compound' and type(params.parts)=='table' then
            -- Parts may use [x, y, z] arrays; the generator wants {x, y, z}.
            for _,p in ipairs(params.parts) do
                for _,k in ipairs({'center','size'}) do if type(p[k])=='table' and p[k][1]~=nil then p[k]={x=p[k][1],y=p[k][2],z=p[k][3]} end end
                if type(p.rotation)=='table' and p.rotation[1]~=nil then p.rotation={roll=p.rotation[1],pitch=p.rotation[2],yaw=p.rotation[3]} end
            end
        end
        local P=package.loaded['modules/procedural'] or require('modules/procedural')
        local info,err=P.generate(body.generator,params);if not info then fail(ctx,'geometry '..body.generator..': '..tostring(err)) end
        local item=point_item(ctx,body,{x=s.x/2,y=s.y/2,z=0})
        item.kind='geometry';item.name=unique_name(state,label or ctx.rule or body.generator);item.generator=body.generator;item.params=params
        item.material=body.material~=nil and value(ctx,body.material,'material') or nil
        item.collision=body.collision==nil and true or truth(value(ctx,body.collision,'collision'))
        item.collision_rules=body.collision_rules~=nil and value(ctx,body.collision_rules,'collision_rules') or nil
        item.layer=body.layer and value(ctx,body.layer,'layer') or 'decoration'
        item.stream_range=body.stream_range~=nil and number(ctx,body.stream_range,'stream_range') or nil
        item.parts=#info.parts
        return emit(ctx,item)
    elseif kind=='asset' then
        local item=point_item(ctx,body,{x=s.x/2,y=s.y/2,z=0})
        item.kind='asset';item.name=unique_name(state,label or ctx.rule or 'Asset')
        item.asset_id=body.asset_id~=nil and value(ctx,body.asset_id,'asset_id') or nil
        item.asset_query=body.asset_query~=nil and value(ctx,body.asset_query,'asset_query') or nil
        item.spawn=body.spawn==nil and true or truth(value(ctx,body.spawn,'spawn'))
        return emit(ctx,item)
    elseif kind=='light' then
        local item=point_item(ctx,body,{x=s.x/2,y=s.y/2,z=s.z-0.15})
        item.kind='light';item.name=unique_name(state,label or ctx.rule or 'Light')
        local config=body.config~=nil and value(ctx,body.config,'config') or {}
        for _,k in ipairs({'color','intensity','radius'}) do if body[k]~=nil then config[k]=value(ctx,body[k],k) end end
        if next(config) then
            config.color=config.color or {1,0.95,0.85};config.intensity=num(config.intensity,60);config.radius=num(config.radius,8)
            config.flickerStrength=num(config.flickerStrength,0);config.flickerPeriod=num(config.flickerPeriod,0.2);config.flickerOffset=num(config.flickerOffset,0)
            item.config=config
        end
        item.preset_id=body.preset_id~=nil and value(ctx,body.preset_id,'preset_id') or nil
        return emit(ctx,item)
    elseif kind=='volume' then
        local size=vec3(ctx,body.size,'size',{x=s.x,y=s.y,z=s.z})
        local item=point_item(ctx,body,{x=s.x/2,y=s.y/2,z=0})
        item.kind='volume';item.name=unique_name(state,label or ctx.rule or 'Volume')
        item.shape=body.shape and value(ctx,body.shape,'shape') or 'box';item.purpose=body.purpose and value(ctx,body.purpose,'purpose') or nil
        item.size=size
        return emit(ctx,item)
    elseif kind=='marker' then
        local item=point_item(ctx,body,{x=s.x/2,y=s.y/2,z=0})
        item.kind='marker';item.name=unique_name(state,label or ctx.rule or 'Marker')
        item.type=body.type and value(ctx,body.type,'type') or 'marker';item.category=body.category and value(ctx,body.category,'category') or 'Grammar'
        return emit(ctx,item)
    end
end

local function axis_box(scope,axis,a,len)
    local s=scope.s
    local m={x=0,y=0,z=0};local d={x=s.x,y=s.y,z=s.z}
    m[axis]=a;d[axis]=len
    return child_scope(scope,{x=m.x+d.x/2,y=m.y+d.y/2,z=m.z},d,0)
end

run_ops=function(ctx,ops)
    for i,op in ipairs(ops or {}) do
        if type(op)=='string' then run_inline(ctx,op)
        elseif cond(ctx,op) then
            local kind=op_kind(op);local body=op[kind]
            local label=tostring(i)
            if kind=='set' then
                for k,v in pairs(body) do
                    if type(k)~='string' or not k:match(RULE_NAME) then fail(ctx,'set: bad variable name '..tostring(k)) end
                    if type(v)=='string' then ctx.vars[k]=expr(ctx,v,'set '..k) else ctx.vars[k]=value(ctx,v,'set '..k) end
                end
            elseif kind=='call' then run_inline(ctx,body)
            elseif kind=='split' then
                local axis=body.axis;local L=ctx.scope.s[axis]
                local abs,weights,wsum={}, {},0
                for j,p in ipairs(body.parts) do
                    if type(p.size)=='string' and p.size:match('^%s*~') then
                        local w=p.size:gsub('^%s*~','');weights[j]=w=='' and 1 or number(ctx,w,'split weight');if weights[j]<0 then fail(ctx,'split weights must be positive') end;wsum=wsum+weights[j]
                    else abs[j]=number(ctx,p.size,'split size');if abs[j]<0 then fail(ctx,'split sizes must be positive') end end
                end
                local total=0;for _,a in pairs(abs) do total=total+a end
                if total>L+1e-6 then fail(ctx,string.format('split sizes add up to %.2f m but the scope is %.2f m along %s',total,L,axis)) end
                local rest=L-total;local cursor=0
                for j,p in ipairs(body.parts) do
                    local len=abs[j] or (wsum>0 and rest*weights[j]/wsum or 0)
                    if len>1e-6 and (p.symbol or p['do']) then run_child(ctx,p,axis_box(ctx.scope,axis,cursor,len),{i=j-1,n=#body.parts},label..'.'..j) end
                    cursor=cursor+len
                end
            elseif kind=='repeat' then
                local axis=body.axis;local L=ctx.scope.s[axis]
                local centres,size=tiles(ctx,body,L)
                for j,c in ipairs(centres) do run_child(ctx,body,axis_box(ctx.scope,axis,c-size/2,size),{i=j-1,n=#centres},label..'.'..j) end
            elseif kind=='place' then
                local s=ctx.scope.s
                local d=vec3(ctx,body.size,'size',nil)
                local m
                if body.center~=nil then local c=vec3(ctx,body.center,'center');d=d or {x=s.x,y=s.y,z=s.z};m={x=c.x-d.x/2,y=c.y-d.y/2,z=c.z-d.z/2}
                else m=vec3(ctx,body.at,'at',{x=0,y=0,z=0});d=d or {x=s.x-m.x,y=s.y-m.y,z=s.z-m.z} end
                if d.x<=0 or d.y<=0 or d.z<=0 then fail(ctx,'place size must be positive') end
                run_child(ctx,body,child_scope(ctx.scope,{x=m.x+d.x/2,y=m.y+d.y/2,z=m.z},d,number(ctx,body.yaw or 0,'yaw')),nil,label)
            elseif kind=='walls' then
                local s=ctx.scope.s
                local depth=number(ctx,body.depth or 0.6,'depth');local inset=number(ctx,body.inset or 0,'inset')
                local sides=body.sides~=nil and value(ctx,body.sides,'sides') or SIDES
                if type(sides)=='string' then sides={sides} end
                for j,side in ipairs(sides) do
                    if not SIDE_OK[side] then fail(ctx,'walls sides must be north, south, east or west: '..tostring(side)) end
                    local c,d,r
                    if side=='south' then c,d,r={x=s.x/2,y=inset+depth/2,z=0},{x=s.x,y=depth,z=s.z},0
                    elseif side=='north' then c,d,r={x=s.x/2,y=s.y-inset-depth/2,z=0},{x=s.x,y=depth,z=s.z},180
                    elseif side=='east' then c,d,r={x=s.x-inset-depth/2,y=s.y/2,z=0},{x=s.y,y=depth,z=s.z},90
                    else c,d,r={x=inset+depth/2,y=s.y/2,z=0},{x=s.y,y=depth,z=s.z},-90 end
                    if depth>((side=='north' or side=='south') and s.y or s.x)+1e-6 then fail(ctx,'walls depth is deeper than the scope') end
                    run_child(ctx,body,child_scope(ctx.scope,c,d,r),{side=side,i=j-1,n=#sides},label..'.'..side)
                end
            elseif kind=='choose' then
                local options=body.options or body
                local eligible,total={},0
                for _,o in ipairs(options) do if cond(ctx,o) then local w=number(ctx,o.weight or 1,'weight');if w>0 then eligible[#eligible+1]={o=o,w=w};total=total+w end end end
                if total>0 then
                    local r=ctx.rng()*total;local pick=eligible[#eligible].o
                    for _,e in ipairs(eligible) do if r<e.w then pick=e.o;break end;r=r-e.w end
                    run_inline(ctx,pick)
                end
            elseif kind=='chance' then
                local p=number(ctx,body.p or 0.5,'p')
                if ctx.rng()<p then run_inline(ctx,body)
                elseif body['else'] then run_inline(ctx,body['else']) end
            else terminal(ctx,kind,body) end
        end
    end
end

-- Doors (and windows) with connect cut the same opening into the room behind the wall.
local function connect_openings(state)
    local added=0
    for _,a in ipairs(state.rooms) do
        for _,list in ipairs({{a.doors,'door'},{a.windows,'window'}}) do
            local own={};for _,o in ipairs(list[1]) do if a.connect[o] then own[#own+1]=o end end
            for _,o in ipairs(own) do
                local out=a.T+0.05
                local lx,ly
                if o.wall=='north' then lx,ly=o.offset,a.length/2+out elseif o.wall=='south' then lx,ly=o.offset,-(a.length/2+out)
                elseif o.wall=='east' then lx,ly=a.width/2+out,o.offset else lx,ly=-(a.width/2+out),o.offset end
                local wx,wy=rot(a.yaw,lx,ly);local p={x=a.center.x+wx,y=a.center.y+wy}
                for _,b in ipairs(state.rooms) do
                    if b~=a and math.abs(b.center.z-a.center.z)<math.max(a.height,b.height) then
                        local bx,by=room_local(b,p)
                        if math.abs(bx)<=b.width/2+b.T+1e-3 and math.abs(by)<=b.length/2+b.T+1e-3 then
                            local wall=nearest_wall(b,bx,by)
                            local offset=round((wall=='north' or wall=='south') and bx or by,4)
                            local target=list[2]=='door' and b.doors or b.windows
                            local clash=false
                            for _,q in ipairs(target) do if q.wall==wall and math.abs(q.offset-offset)<((q.width or 1)+o.width)/2 then clash=true end end
                            if not clash then
                                local c=Util.deepcopy(o);c.wall=wall;c.offset=offset;c.connected_from=a.name
                                target[#target+1]=c;added=added+1
                            end
                        end
                    end
                end
            end
        end
    end
    return added
end

local function footprint(room)
    local pts={}
    local hw,hl=room.width/2+room.T,room.length/2+room.T
    for _,c in ipairs({{-hw,-hl},{hw,-hl},{hw,hl},{-hw,hl}}) do local x,y=rot(room.yaw,c[1],c[2]);pts[#pts+1]={x=room.center.x+x,y=room.center.y+y} end
    return pts
end

-- Separating-axis overlap of two room footprints (shared walls touching is fine).
local function overlap(a,b)
    if math.abs(a.center.z-b.center.z)>=math.max(a.height,b.height) then return false end
    local pa,pb=footprint(a),footprint(b)
    for _,poly in ipairs({pa,pb}) do
        for i=1,4 do
            local p,q=poly[i],poly[i%4+1];local nx,ny=-(q.y-p.y),q.x-p.x;local len=math.sqrt(nx*nx+ny*ny);nx,ny=nx/len,ny/len
            local amin,amax,bmin,bmax=math.huge,-math.huge,math.huge,-math.huge
            for _,v in ipairs(pa) do local d=v.x*nx+v.y*ny;amin=math.min(amin,d);amax=math.max(amax,d) end
            for _,v in ipairs(pb) do local d=v.x*nx+v.y*ny;bmin=math.min(bmin,d);bmax=math.max(bmax,d) end
            if amax<=bmin+0.01 or bmax<=amin+0.01 then return false end
        end
    end
    return true
end

-- Expand a normalized grammar. args: start, params, seed, size.
function Grammar.expand(g,args)
    args=args or {}
    local start=args.start or g.start
    if type(start)~='string' or not g.rules[start] then return nil,'start rule not found: '..tostring(start) end
    local size=args.size or g.size
    if type(size)~='table' then return nil,'give a size [x, y, z] (the grammar has none)' end
    local sx,sy,sz=num(size.x or size[1]),num(size.y or size[2]),num(size.z or size[3])
    if not sx or not sy or not sz or sx<=0 or sy<=0 or sz<=0 or sx>2000 or sy>2000 or sz>500 then return nil,'size must be [x, y, z] with positive metres (at most 2000 x 2000 x 500)' end
    local seed=math.floor(num(args.seed,1))
    local globals={pi=math.pi}
    for k,v in pairs(g.params) do globals[k]=Util.deepcopy(v) end
    local unknown={}
    for k,v in pairs(type(args.params)=='table' and args.params or {}) do
        if type(k)~='string' or not k:match(RULE_NAME) then return nil,'param names must be identifiers: '..tostring(k) end
        if g.params[k]==nil then unknown[#unknown+1]=k end
        globals[k]=Util.deepcopy(v)
    end
    local state={g=g,seed=seed,globals=globals,items={},rooms={},calls=0,level=0,rule_counts={},kind_counts={},names={},warnings={}}
    for _,k in ipairs(unknown) do state.warnings[#state.warnings+1]='param '..k..' is not declared by the grammar' end
    local root={o={x=-sx/2,y=-sy/2,z=0},yaw=0,s={x=sx,y=sy,z=sz}}
    local ok,err=pcall(function()
        local ctx=new_ctx(state,nil,root,start)
        run_rule(ctx,start)
    end)
    if not ok then return nil,type(err)=='table' and err.grammar_error or ('grammar expansion failed: '..tostring(err)) end
    state.connected=connect_openings(state)
    -- Final room specs, validated with their openings.
    local RG=package.loaded['modules/room_generator'] or require('modules/room_generator')
    for _,room in ipairs(state.rooms) do
        local spec=Util.deepcopy(room.spec);spec.name=room.name;spec.doors={};spec.windows={}
        for _,d in ipairs(room.doors) do local c=Util.deepcopy(d);c.connected_from=nil;spec.doors[#spec.doors+1]=c end
        for _,w in ipairs(room.windows) do local c=Util.deepcopy(w);c.connected_from=nil;spec.windows[#spec.windows+1]=c end
        local _,rerr=RG.normalize(spec)
        if rerr then
            local from,seen={},{}
            for _,list in ipairs({room.doors,room.windows}) do for _,o in ipairs(list) do if o.connected_from and not seen[o.connected_from] then seen[o.connected_from]=true;from[#from+1]=o.connected_from end end end
            if #from>0 then rerr=rerr..' (openings 1-'..(#spec.doors)..' include ones connected from '..table.concat(from,', ')..'; set connect=false or move them)' end
            return nil,room.path..': room '..room.name..': '..rerr
        end
        room.final=spec
    end
    for i=1,#state.rooms do for j=i+1,#state.rooms do
        if overlap(state.rooms[i],state.rooms[j]) then state.warnings[#state.warnings+1]='rooms '..state.rooms[i].name..' and '..state.rooms[j].name..' overlap' end
    end end
    local lo,hi={x=math.huge,y=math.huge,z=math.huge},{x=-math.huge,y=-math.huge,z=-math.huge}
    local function grow(x,y,z) lo.x=math.min(lo.x,x);lo.y=math.min(lo.y,y);lo.z=math.min(lo.z,z);hi.x=math.max(hi.x,x);hi.y=math.max(hi.y,y);hi.z=math.max(hi.z,z) end
    for _,room in ipairs(state.rooms) do for _,p in ipairs(footprint(room)) do grow(p.x,p.y,room.center.z);grow(p.x,p.y,room.center.z+room.height) end end
    for _,item in ipairs(state.items) do grow(item.offset.x,item.offset.y,item.offset.z) end
    return {grammar=g.id,name=g.name,start=start,seed=seed,size={sx,sy,sz},rooms=state.rooms,items=state.items,
        stats={calls=state.calls,rules=state.rule_counts,kinds=state.kind_counts,rooms=#state.rooms,items=#state.items,connected_openings=state.connected},
        warnings=state.warnings,bounds=lo.x<math.huge and {min=lo,max=hi} or nil}
end

-- Compile an expansion into a version 2 authoring plan.
-- opts: doc (EDL doc id), premise_id | premise_name/premise_kind, origin.
function Grammar.compile(exp,opts)
    opts=opts or {}
    local steps={{op='edl_begin',doc=opts.doc,name=opts.label or ('Grammar: '..exp.name),source='grammar',hash=opts.hash}}
    local premise=opts.premise_id
    if not premise then
        steps[#steps+1]={op='create_premise',as='premise',name=opts.premise_name or exp.name,kind=opts.premise_kind or 'interior'}
        premise='$premise'
    end
    local function room_ref(item) return item.room and ('$'..item.room.alias) or nil end
    for _,room in ipairs(exp.rooms) do
        steps[#steps+1]={op='create_parametric_room',as=room.alias,premise_id=premise,spec=room.final,offset=Util.deepcopy(room.center),yaw=room.yaw}
    end
    local n=0
    for _,item in ipairs(exp.items) do
        n=n+1;local alias=item.kind..'_'..n
        local base={as=alias,premise_id=premise,room_id=room_ref(item),name=item.name,offset=Util.deepcopy(item.offset),yaw=item.yaw,pitch=item.pitch,roll=item.roll}
        if item.kind=='geometry' then
            base.op='create_procedural';base.generator=item.generator;base.params=item.params;base.material=item.material;base.collision=item.collision
            base.collision_rules=item.collision_rules;base.layer=item.layer;base.stream_range=item.stream_range
        elseif item.kind=='asset' then base.op='place_asset';base.asset_id=item.asset_id;base.asset_query=item.asset_query;base.spawn=item.spawn
        elseif item.kind=='light' then base.op='create_light';base.config=item.config;base.preset_id=item.preset_id
        elseif item.kind=='volume' then
            base.op='create_volume';base.shape=item.shape;base.purpose=item.purpose;base.size_x=item.size.x;base.size_y=item.size.y;base.size_z=item.size.z
            base.offset.z=base.offset.z+item.size.z/2
        elseif item.kind=='marker' then base.op='create_location';base.premise_id=nil;base.room_id=nil;base.type=item.type;base.category=item.category end
        steps[#steps+1]=base
    end
    return {format='locationstudio-authoring-plan',version=2,name=opts.label or ('Grammar: '..exp.name),origin=opts.origin or 'player',steps=steps}
end

---------------------------------------------------------------------------
-- Library, generation and builds (instance methods)
---------------------------------------------------------------------------
function Grammar.new(app) return setmetatable({app=app,shipped=nil},Grammar) end

function Grammar:_shipped()
    if self.shipped then return self.shipped end
    local out={schema=nil,grammars={}}
    local file=io.open(LIBRARY_PATH,'r')
    if file then
        local text=file:read('*a');file:close()
        local ok,doc=pcall(json.decode,text)
        if ok and type(doc)=='table' then
            out.schema=doc.schema
            for id,g in pairs(type(doc.grammars)=='table' and doc.grammars or {}) do if type(g)=='table' then g.id=g.id or id;out.grammars[g.id]=g end end
        end
    end
    self.shipped=out
    return out
end

local function project_list(model) model.data.grammars=type(model.data.grammars)=='table' and model.data.grammars or {};return model.data.grammars end

function Grammar:find(id)
    for i,g in ipairs(project_list(self.app.model)) do if g.id==id then return g,'project',i end end
    local s=self:_shipped().grammars[id];if s then return s,'builtin' end
end

function Grammar:_resolver() return function(id) return (self:find(id)) end end

function Grammar:schema() return Util.deepcopy(self:_shipped().schema or {}) end

function Grammar:library()
    local rows,seen={},{}
    local function add(g,source)
        if seen[g.id] then return end;seen[g.id]=true
        local rules=0;for _ in pairs(type(g.rules)=='table' and g.rules or {}) do rules=rules+1 end
        local params={};for k,v in pairs(type(g.params)=='table' and g.params or {}) do params[k]=Util.deepcopy(v) end
        rows[#rows+1]={id=g.id,name=g.name or g.id,description=g.description or '',source=source,start=g.start,size=Util.deepcopy(g.size),rules=rules,params=params,include=Util.deepcopy(g.include)}
    end
    for _,g in ipairs(project_list(self.app.model)) do add(g,'project') end
    local ids={};for id in pairs(self:_shipped().grammars) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do add(self:_shipped().grammars[id],'builtin') end
    return {items=rows,count=#rows}
end

function Grammar:get(id)
    local g,source=self:find(id);if not g then return nil,'grammar not found: '..tostring(id) end
    local out=Util.deepcopy(g);out.source=source
    return out
end

local function busy(app)
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and (app.authoring_plans.running or app.authoring_plans:status().recovery_required) then return 'Resolve the running or failed authoring plan first' end
end

-- Save a grammar to the project library (validated). One undo step.
function Grammar:save(doc)
    local b=busy(self.app);if b then return nil,b end
    if type(doc)~='table' or type(doc.id)~='string' or not doc.id:match(ID) then return nil,'a saved grammar needs an id (letters, digits, _ or -)' end
    local g,err=Grammar.normalize(doc,self:_resolver());if not g then return nil,err end
    local check
    if g.start and g.size then local exp,xerr=Grammar.expand(g,{});check={ok=exp~=nil,error=xerr,rooms=exp and exp.stats.rooms,items=exp and exp.stats.items} end
    local model=self.app.model
    model:snapshot('Save grammar '..doc.id)
    local copy=Util.deepcopy(doc);copy.source=nil;copy.updated_at=Util.now_iso()
    local _,_,index=self:find(doc.id)
    local list=project_list(model)
    if index then list[index]=copy else list[#list+1]=copy end
    model:touch();self.app:mark_dirty()
    return {id=doc.id,saved=true,replaced=index~=nil,check=check}
end

function Grammar:delete(id)
    local b=busy(self.app);if b then return nil,b end
    local _,source,index=self:find(id)
    if source~='project' then return nil,source=='builtin' and 'built-in grammars cannot be deleted' or 'grammar not found: '..tostring(id) end
    self.app.model:snapshot('Delete grammar '..id)
    table.remove(project_list(self.app.model),index)
    self.app.model:touch();self.app:mark_dirty()
    return {deleted=id}
end

-- Resolve a grammar from args (grammar id or inline doc).
function Grammar:_grammar(args)
    local doc=args.doc or args.grammar_doc
    if type(args.grammar)=='table' then doc=args.grammar end
    if not doc then
        if type(args.grammar)~='string' then return nil,'give grammar (a library id) or doc' end
        doc=self:find(args.grammar);if not doc then return nil,'grammar not found: '..args.grammar end
    end
    return Grammar.normalize(doc,self:_resolver())
end

local function summary(exp)
    local rooms={}
    for _,r in ipairs(exp.rooms) do
        rooms[#rooms+1]={name=r.name,rule=r.rule,path=r.path,center=Util.deepcopy(r.center),yaw=r.yaw,width=r.width,length=r.length,height=r.height,
            doors=#r.final.doors,windows=#r.final.windows}
    end
    local items={}
    for _,it in ipairs(exp.items) do
        items[#items+1]={kind=it.kind,name=it.name,rule=it.rule,path=it.path,room=it.room and it.room.name or nil,offset=Util.deepcopy(it.offset),yaw=it.yaw,
            generator=it.generator,asset_id=it.asset_id,asset_query=it.asset_query}
    end
    return {grammar=exp.grammar,name=exp.name,start=exp.start,seed=exp.seed,size=Util.deepcopy(exp.size),rooms=rooms,items=items,stats=Util.deepcopy(exp.stats),
        warnings=Util.deepcopy(exp.warnings),bounds=Util.deepcopy(exp.bounds)}
end

local function slug(s) return (tostring(s or 'x'):lower():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')) end

-- Origin transform from args.
local function origin_of(args)
    if type(args.transform)=='table' and type(args.transform.position)=='table' then return Util.deepcopy(args.transform) end
    if type(args.position)=='table' then
        local p=args.position
        return {position={x=num(p.x or p[1],0),y=num(p.y or p[2],0),z=num(p.z or p[3],0),w=1},rotation={roll=0,pitch=0,yaw=num(args.yaw,0)}}
    end
    if args.origin=='camera' then return 'camera' end
    if type(args.origin)=='table' then return Util.deepcopy(args.origin) end
    return 'player'
end

-- Expand and compile without changing the project.
function Grammar:plan(args)
    args=args or {}
    local g,err=self:_grammar(args);if not g then return nil,err end
    local exp;exp,err=Grammar.expand(g,args);if not exp then return nil,err end
    if args.premise_id and not self.app.model:get_premise(args.premise_id) then return nil,'premise not found: '..tostring(args.premise_id) end
    local build_id=args.build_id or (slug(g.id)..'_'..Util.make_id('b'))
    if not tostring(build_id):match(ID) then return nil,'build_id must use letters, digits, _ or -' end
    local plan=Grammar.compile(exp,{doc='grammar_'..build_id,premise_id=args.premise_id,premise_name=args.premise_name,premise_kind=args.premise_kind,
        origin=origin_of(args),label='Grammar '..g.name..' ('..exp.start..', seed '..exp.seed..')'})
    if #plan.steps>2000 then return nil,'this layout needs '..#plan.steps..' plan steps; the limit is 2000' end
    return {grammar=g,expansion=exp,plan=plan,build_id=build_id}
end

function Grammar:preview(args)
    local p,err=self:plan(args);if not p then return nil,err end
    local out=summary(p.expansion);out.build_id=p.build_id;out.steps=#p.plan.steps
    if self.app.authoring_plans then
        local v=self.app.authoring_plans:validate(p.plan)
        out.valid=v.valid;out.errors=v.errors
    end
    if args and args.include_plan then out.plan=p.plan end
    return out
end

local function builds(model) model.data.grammar_builds=type(model.data.grammar_builds)=='table' and model.data.grammar_builds or {};return model.data.grammar_builds end
function Grammar:build(id) for i,b in ipairs(builds(self.app.model)) do if b.id==id then return b,i end end end

-- Generate: expand, compile and run as one authoring plan (one undo step).
function Grammar:generate(args)
    args=args or {}
    local b=busy(self.app);if b then return nil,b end
    if not self.app.authoring_plans then return nil,'authoring plans are unavailable' end
    local p,err=self:plan(args);if not p then return nil,err end
    local result;result,err=self.app.authoring_plans:execute(p.plan)
    if not result then return nil,err end
    local model=self.app.model
    local premise_id=result.edl and result.edl.premise_id or args.premise_id
    local rec={id=p.build_id,doc='grammar_'..p.build_id,grammar=p.grammar.id,grammar_doc=args.doc and Util.deepcopy(args.doc) or nil,start=p.expansion.start,seed=p.expansion.seed,
        size=Util.deepcopy(p.expansion.size),params=Util.deepcopy(args.params or {}),premise_id=premise_id,own_premise=args.premise_id==nil,premise_name=args.premise_name,premise_kind=args.premise_kind,
        origin=Util.deepcopy(result.origin),stats=Util.deepcopy(p.expansion.stats),generated_at=Util.now_iso(),mod_version=self.app.version}
    local _,index=self:build(p.build_id)
    if index then builds(model)[index]=rec else table.insert(builds(model),rec) end
    local out=summary(p.expansion)
    out.build_id=p.build_id;out.premise_id=premise_id;out.steps=result.step_count;out.one_undo=true;out.replaced=result.edl and result.edl.replaced or false
    local warnings={};for _,o in ipairs(result.outputs or {}) do if o.warning then warnings[#warnings+1]='step '..o.index..' ('..o.op..'): '..tostring(o.warning) end end
    out.runtime_warnings=warnings
    return out
end

-- Regenerate a build in place (same origin; params/seed/size/start may change).
function Grammar:regenerate(build_id,patch)
    patch=patch or {}
    local rec=self:build(build_id);if not rec then return nil,'no grammar build with id '..tostring(build_id) end
    local args={build_id=rec.id,grammar=rec.grammar_doc or rec.grammar,start=patch.start or rec.start,seed=patch.seed or rec.seed,size=patch.size or rec.size,
        params=Util.deepcopy(rec.params or {}),transform=Util.deepcopy(rec.origin),premise_name=rec.premise_name,premise_kind=rec.premise_kind}
    if type(rec.grammar_doc)=='table' then args.doc=rec.grammar_doc;args.grammar=nil end
    for k,v in pairs(type(patch.params)=='table' and patch.params or {}) do args.params[k]=Util.deepcopy(v) end
    if not rec.own_premise then
        if not rec.premise_id or not self.app.model:get_premise(rec.premise_id) then return nil,'the premise of this build no longer exists' end
        args.premise_id=rec.premise_id
    end
    return self:generate(args)
end

function Grammar:remove(build_id)
    local b=busy(self.app);if b then return nil,b end
    local rec,index=self:build(build_id);if not rec then return nil,'no grammar build with id '..tostring(build_id) end
    local plans=self.app.authoring_plans
    local edl=plans:edl_get(rec.doc)
    if edl then local r,err=plans:edl_remove(rec.doc);if not r then return nil,err end end
    table.remove(builds(self.app.model),index)
    return {removed=build_id,premise_id=rec.premise_id}
end

function Grammar:builds()
    local rows={}
    for _,b in ipairs(builds(self.app.model)) do
        local edl=self.app.authoring_plans and self.app.authoring_plans:edl_get(b.doc)
        rows[#rows+1]={id=b.id,grammar=b.grammar,start=b.start,seed=b.seed,size=Util.deepcopy(b.size),params=Util.deepcopy(b.params),premise_id=b.premise_id,
            rooms=b.stats and b.stats.rooms,items=b.stats and b.stats.items,generated_at=b.generated_at,present=edl~=nil}
    end
    return {items=rows,count=#rows}
end

return Grammar
