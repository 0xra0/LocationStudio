local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local room=assert(app.model:add_room({name='Clinic',premise_id=app.model.data.premises[1] and app.model.data.premises[1].id,
    transform={position={x=10,y=20,z=30},rotation={roll=0,pitch=0,yaw=45}},size={width=8,depth=4,height=3.5}}))
app.selected_room_id=room.id
local catalog={
    audio={name='amb_int_roomtone_office_med_01_aircon',path='base\audio\amb_int_roomtone_office_med_01_aircon'},
    area_ambient={name='Interior Muffling Area',path=''},area_outline={name='Outline Marker',path=''},
}
function app.world_builder:search(key,query)
    local item=catalog[key];if not item then return nil,'missing fake catalog' end
    return {items={{name=item.name,path=item.path}}}
end
function app.world_builder:prepare_favorite_record(record,name)
    local key=record.category=='Deco' and 'audio' or record.variant=='Ambient Area' and 'area_ambient' or 'area_outline'
    local saved
    if key=='audio' then saved={spawnData=catalog[key].path,radius=5,useDoppler=true,usePhysicsObstruction=true,emitterMetadataName=''}
    elseif key=='area_ambient' then saved={outlinePath='',markers={},height=0,trigger={Notifier={['$type']='audioAmbientAreaNotifier'},Settings={Data={['$type']='audioAmbientAreaSettings',EventsOnActive={},EventsOnEnter={},EventsOnExit={},outerDistance=10,verticalOuterDistance=1,Priority=16,Reverb={['$type']='CName',['$value']='revb_interior_room_medium'},Parameters={},isMusic=false}}}}
    else saved={height=3} end
    local d={name=name,modulePath='modules/classes/editor/spawnableElement',spawnable=saved}
    return {name=name,data=d}
end
function app.placement:spawn(object)
    object.runtime={spawned=true,backend='world_builder',entity_id='mock'}
    return 'mock'
end
local emitter=assert(app.ambient_audio:create_emitter({query='amb_',name='Aircon',source='player',radius=7.5,room_id=room.id}))
assert(emitter.spawned and emitter.object.metadata.world_builder.definition_key=='audio')
assert(emitter.object.metadata.world_builder.entry.data.radius==7.5)
assert(emitter.object.metadata.ambient_audio.event==catalog.audio.path)
local zone=assert(app.ambient_audio:create_reverb_zone({room_id=room.id,name='Clinic Reverb',reverb='revb_interior_room_medium'}))
assert(#zone.outline==4 and #zone.outline_points==4 and zone.spawned==5)
assert(zone.zone.metadata.world_builder.definition_key=='area_ambient')
local settings=zone.zone.metadata.world_builder.entry.data.trigger.Settings.Data
assert(settings.Reverb['$value']=='revb_interior_room_medium' and settings.Priority==16)
assert(zone.zone.metadata.world_builder.entry.data.outlinePath==zone.outline_group)
local dx=zone.outline[2].transform.position.x-zone.outline[1].transform.position.x
local dy=zone.outline[2].transform.position.y-zone.outline[1].transform.position.y
assert(math.abs(math.sqrt(dx*dx+dy*dy)-8)<0.0001,'rotated room edges should preserve room width')
local no_room,no_room_err=app.ambient_audio:create_reverb_zone({room_id='missing'})
assert(not no_room and no_room_err:find('select an existing room',1,true))
local invalid,invalid_err=app.ambient_audio:create_reverb_zone({room_id=room.id,width=0.1})
assert(not invalid and invalid_err:find('width must be between',1,true))
print('ambient_audio_runtime_test: OK')
