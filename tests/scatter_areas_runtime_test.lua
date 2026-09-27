local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.61.0')
local premise=assert(app.model:add_premise({name='Scatter Area Test'}))
local asset=app.model:add_asset({name='Area Scatter Asset',kind='mesh',template='base\\props\\area_scatter.mesh',size={x=1,y=1,z=1}})
env.aim_x=40;env.aim_y=50;env.aim_z=30;env.ground_z=5;env.aim_normal={x=0,y=0,z=1}

local polygon={{x=0,y=0},{x=8,y=0},{x=8,y=8},{x=0,y=8}}
local first=assert(app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=30,seed=8123,scatter_area='polygon',polygon=polygon,z=14,drop_to_ground=false,spawn=false}))
assert(first.creation.scatter_area=='polygon' and first.creation.seed==8123 and #first.creation.points==30)
local positions={}
for index,point in ipairs(first.creation.points) do
    assert(point.x>=0 and point.x<=8 and point.y>=0 and point.y<=8 and point.z==14)
    positions[index]={x=point.x,y=point.y}
end
assert(app.transform_session:cancel())
local repeat_result=assert(app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=30,seed=8123,scatter_area='polygon',polygon=polygon,z=14,drop_to_ground=false,spawn=false}))
for index,point in ipairs(repeat_result.creation.points) do assert(point.x==positions[index].x and point.y==positions[index].y,'same seed must reproduce polygon points') end
assert(app.transform_session:cancel())
local crossed,cross_err=app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=2,scatter_area='polygon',polygon={{x=0,y=0},{x=5,y=5},{x=0,y=5},{x=5,y=0}},spawn=false})
assert(not crossed and cross_err:find('cross',1,true))

local volume=app.model:add_volume({premise_id=premise.id,name='Scatter Box',shape='box',transform={position={x=100,y=200,z=300},rotation={yaw=90}},size={x=4,y=6,z=8}})
local inside=assert(app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=40,seed=29,scatter_area='volume',volume_id=volume.id,spawn=false}))
assert(inside.creation.scatter_area=='volume' and inside.creation.volume_id==volume.id)
for _,point in ipairs(inside.creation.points) do
    assert(point.x>=97 and point.x<=103 and point.y>=198 and point.y<=202 and point.z>=296 and point.z<=304)
end
assert(app.transform_session:cancel())

volume=app.model:add_volume({premise_id=premise.id,name='Scatter Sphere',shape='sphere',transform={position={x=0,y=0,z=0}},radius=3})
inside=assert(app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=25,seed=30,scatter_area='volume',volume_id=volume.id,spawn=false}))
for _,point in ipairs(inside.creation.points) do assert(point.x*point.x+point.y*point.y+point.z*point.z<=9.00001) end
assert(app.transform_session:cancel())

volume=app.model:add_volume({premise_id=premise.id,name='Scatter Cylinder',shape='cylinder',transform={position={x=0,y=0,z=0}},radius=2,height=6})
inside=assert(app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=25,seed=31,scatter_area='volume',volume_id=volume.id,spawn=false}))
for _,point in ipairs(inside.creation.points) do assert(point.x*point.x+point.y*point.y<=4.00001 and math.abs(point.z)<=3.00001) end
assert(app.transform_session:cancel())

local surface=assert(app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=8,seed=19,radius=2,scatter_area='live_surface',distance=20,spawn=false}))
assert(surface.creation.scatter_area=='live_surface' and surface.creation.align_surface==true)
for _,point in ipairs(surface.creation.points) do assert(point.ground_source=='live_surface_raycast' and math.abs(point.z-5.02)<0.001 and point.normal.z==1) end
assert(app.transform_session:cancel())
env.aim_normal={x=0,y=0,z=0}
local no_normal,normal_err=app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=1,scatter_area='live_surface',spawn=false})
assert(not no_normal and normal_err:find('normal',1,true))

print('LocationStudio polygon, volume, live-surface scatter: OK')
