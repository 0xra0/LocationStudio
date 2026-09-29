local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.80.0')
local premise=assert(app.actions:create_premise_from_player('Prop Validator','interior'))
local bounds={min={x=-0.5,y=-0.5,z=0},max={x=0.5,y=0.5,z=1},units='m',source='validator-test'}
local function place(name,x)
    return assert(app.builder:place_object({premise_id=premise.id,name=name,kind='mesh',template='base\\prop_validator.mesh',
        transform={position={x=x,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata={asset_bounds=bounds}}))
end
local a=place('Validator A',0);local b=place('Validator B',0.75)
local clip=assert(app.bridge:handle({id='clip',op='wb_clipcheck',args={object_ids={a.id,b.id}}}))
assert(clip.validator=='clipcheck' and clip.tested==2 and clip.collision_count==1)
assert(clip.collisions[1].approximate and clip.method:find('oriented rectangular',1,true))

env.offline=true
local fixture,fixture_err=app.bridge:handle({id='fixture-offline',op='wb_fixturecheck',args={object_ids={a.id}}})
assert(not fixture and tostring(fixture_err):find('live game',1,true),tostring(fixture_err))
env.offline=false
app.game.is_ready=function() return true end
app.game.raycast=function(_,from,to,groups)
    assert(groups[1]=='Static')
    if from.z>to.z then return {position={x=from.x,y=from.y,z=0.25},group='Static'} end
    return nil,'no hit'
end
local live=assert(app.bridge:handle({id='fixture-live',op='wb_fixturecheck',args={object_ids={a.id},cell_size=0.5}}))
assert(live.live and live.tested==1 and live.results[1].fixture_hits>0)
local fit=assert(app.bridge:handle({id='fit-live',op='wb_fitcheck',args={object_ids={a.id},mode='live'}}))
assert(fit.live and fit.mode=='live' and #fit.results[1].hits==5)
local wall=assert(app.bridge:handle({id='fit-wall',op='wb_fitcheck',args={object_ids={a.id},mode='wall'}}))
assert(wall.mode=='wall' and #wall.results[1].hits==4)
local invalid,invalid_err=app.bridge:handle({id='fit-invalid',op='wb_fitcheck',args={object_ids={a.id},mode='sideways'}})
assert(not invalid and invalid_err:find('mode must',1,true))
print('LocationStudio Prop Validators: OK')
