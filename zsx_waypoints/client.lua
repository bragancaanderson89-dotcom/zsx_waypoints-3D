local C,G = WaypointConfig,WaypointGeometry
local settings = G.settings(nil,C.defaults)
local route, destination, custom = {},nil,nil
local menuOpen, suppressed = false,false
local routeGeneration, activeKey, lastSave = 0,nil,0
local warnedNative, markerVisible = false,false
local kvp = 'settings:v1'
local raw = GetResourceKvpString(kvp)
if raw then
    local ok,value = pcall(json.decode,raw)
    if ok then settings = G.settings(value,C.defaults) end
end

local function hideMarker()
    if markerVisible then SendNUIMessage({action='marker',visible=false}); markerVisible=false end
end
local function clearRoute()
    routeGeneration=routeGeneration+1
    route,destination,activeKey={},nil,nil
    hideMarker()
end
local function closeMenu()
    menuOpen=false
    SetNuiFocus(false,false)
    SendNUIMessage({action='close'})
end
local function openMenu()
    if IsNuiFocused() and not menuOpen then return false end
    menuOpen=true
    SetNuiFocus(true,true)
    SendNUIMessage({action='open',settings=settings,defaults=C.defaults})
    return true
end
RegisterCommand(C.command, function() if menuOpen then closeMenu() else openMenu() end end,false)
exports('OpenSettings',openMenu)
exports('SetVisible',function(value) suppressed=value==false; if suppressed then clearRoute() end end)

local function clearCustom()
    if custom and DoesBlipExist(custom.blip) then RemoveBlip(custom.blip) end
    custom=nil
    clearRoute()
end
exports('ClearDestination',clearCustom)
exports('SetDestination',function(coords,label)
    if not G.validPoint(coords) then return false end
    clearCustom()
    local blip=AddBlipForCoord(coords.x,coords.y,coords.z)
    SetBlipSprite(blip,1)
    SetBlipColour(blip,3)
    SetBlipRoute(blip,true)
    SetBlipRouteColour(blip,3)
    local name=tostring(label or 'DESTINO'):sub(1,64)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(name); EndTextCommandSetBlipName(blip)
    custom={blip=blip,coords={x=coords.x,y=coords.y,z=coords.z},label=name}
    return true
end)

RegisterNUICallback('ready',function(_,cb)
    cb({ok=true})
    if menuOpen then SendNUIMessage({action='open',settings=settings,defaults=C.defaults}) end
end)
RegisterNUICallback('close',function(_,cb) closeMenu(); cb({ok=true}) end)
RegisterNUICallback('settings',function(data,cb)
    if not menuOpen then cb({ok=false}); return end
    local geometryChanged = data.spacing~=settings.spacing or data.lift~=settings.lift or data.scale~=settings.scale
    settings=G.settings(data,C.defaults)
    if geometryChanged or not settings.road then routeGeneration=routeGeneration+1; route={} end
    lastSave=GetGameTimer()+650
    cb({ok=true,settings=settings})
end)

local function canRender()
    local ped=PlayerPedId()
    if suppressed or IsPauseMenuActive() or IsPlayerSwitchInProgress() or IsScreenFadedOut()
        or not DoesEntityExist(ped) or IsEntityDead(ped) then return false end
    if not menuOpen and (IsNuiFocused() or not IsPlayerControlOn(PlayerId())) then return false end
    if C.onlyInVehicles then
        local vehicle=GetVehiclePedIsIn(ped,false)
        if vehicle==0 then return false end
        local class=GetVehicleClass(vehicle)
        if class==14 or class==15 or class==16 or class==21 then return false end
    end
    return true
end

local function getTarget()
    if custom then
        if DoesBlipExist(custom.blip) then return custom.coords,1,custom.label,'custom:'..custom.blip end
        custom=nil
    end
    if not IsWaypointActive() then return end
    local blip=GetFirstBlipInfoId(8)
    if blip==0 or not DoesBlipExist(blip) then return end
    local p=GetBlipInfoIdCoord(blip)
    return p,0,'DESTINO',('%.1f:%.1f'):format(p.x,p.y)
end

local function sample(distance,slot)
    -- Older FiveM artifacts expose the same native under the previous name.
    local fn=GetPosAlongGpsTypeRoute or GetGpsWaypointRouteEnd
    if type(fn)~='function' then
        if not warnedNative then
            print('[zsx_waypoints] Native GPS indisponível neste artifact; atualize o FXServer. O marcador continua disponível.')
            warnedNative=true
        end
        return nil
    end
    local ok,found,p=pcall(fn,true,distance+0.0,slot)
    if not ok or not found or not G.validPoint(p) then return nil end
    if p.x==0 and p.y==0 and p.z==0 then return nil end
    return {x=p.x,y=p.y,z=p.z}
end

local function surface(p)
    local found,z=GetGroundZFor_3dCoord(p.x,p.y,p.z+2.0,false)
    -- Do not snap to the ground below a bridge or to a roof above the route.
    if found and math.abs(z-p.z)<2.5 then return {x=p.x,y=p.y,z=z} end
    return p
end
local function targetHeight(p)
    local found,z=GetGroundZFor_3dCoord(p.x,p.y,p.z+35.0,false)
    if found then return z end
    if math.abs(p.z)>0.5 then return p.z end
    local ok,node=GetClosestVehicleNode(p.x,p.y,p.z,1,3.0,0)
    if ok and node and math.abs(node.x-p.x)<50 and math.abs(node.y-p.y)<50 then return node.z end
    return p.z
end

CreateThread(function()
    while true do
        if lastSave>0 and GetGameTimer()>=lastSave then
            SetResourceKvp(kvp,json.encode(settings)); lastSave=0
        end
        if not canRender() then
            clearRoute()
            Wait(300)
        else
            local target,slot,label,key=getTarget()
            if not target then clearRoute(); Wait(300)
            else
                if key~=activeKey then clearRoute(); activeKey=key end
                local origin=GetEntityCoords(PlayerPedId())
                local dist=math.sqrt((origin.x-target.x)^2+(origin.y-target.y)^2)
                local groundZ=(destination and destination.z) or targetHeight(target)
                if dist<150 then groundZ=targetHeight(target) end
                destination={x=target.x,y=target.y,z=groundZ,label=label,distance=dist}
                if dist<C.arrivalDistance and math.abs(origin.z-groundZ)<10 then
                    route={}; hideMarker()
                    if custom then clearCustom() end
                    Wait(300)
                else
                    local generation=routeGeneration
                    local pending={}
                    if settings.road then
                        local distance=5.0
                        while distance<C.renderDistance and #pending<C.maximumChevrons do
                            local p=sample(distance,slot)
                            local nextPoint=sample(distance+2.5,slot)
                            if not p or not nextPoint then break end
                            if G.distance(origin,p)>C.renderDistance+40 then break end
                            p,nextPoint=surface(p),surface(nextPoint)
                            local vertices=G.chevron(p,nextPoint,settings.scale,settings.lift)
                            if vertices then
                                pending[#pending+1]={p=p,vertices=vertices,
                                    glow=G.chevron(p,nextPoint,settings.scale*1.12,settings.lift-0.015)}
                            end
                            distance=distance+settings.spacing
                            if #pending%8==0 then Wait(0) end
                            if generation~=routeGeneration then break end
                        end
                    end
                    if generation==routeGeneration then
                        route=G.prepareRoute(route,pending,GetGameTimer(),C.sampleInterval+50,settings.spacing)
                    end
                    Wait(C.sampleInterval)
                end
            end
        end
    end
end)

local function triangle(a,b,c,r,g,blue,alpha)
    DrawPoly(c.x,c.y,c.z,b.x,b.y,b.z,a.x,a.y,a.z,r,g,blue,alpha)
end
local function chevron(v,r,g,b,a)
    if not v then return end
    triangle(v[1],v[2],v[5],r,g,b,a); triangle(v[1],v[5],v[6],r,g,b,a)
    triangle(v[2],v[3],v[4],r,g,b,a); triangle(v[2],v[4],v[5],r,g,b,a)
end
CreateThread(function()
    while true do
        if #route>0 and settings.road and canRender() then
            local origin=GetEntityCoords(PlayerPedId())
            local r,g,b=G.rgb(settings.color)
            local now=GetGameTimer()
            for _,entry in ipairs(route) do
                G.animateEntry(entry,now)
                local d=G.distance(origin,entry.p)
                local fade=math.min(1,math.max(0,(d-2)/7),math.max(0,(C.renderDistance-d)/35))
                local a=math.floor(255*settings.opacity*fade*entry.alpha)
                if a>1 then chevron(entry.glow,r,g,b,math.floor(a*0.12)); chevron(entry.vertices,r,g,b,a) end
            end
            Wait(0)
        else Wait(120) end
    end
end)
CreateThread(function()
    while true do
        local d=destination
        if d and settings.destination and canRender() and d.distance>=C.arrivalDistance and d.distance<C.markerDistance then
            local onScreen,x,y=GetScreenCoordFromWorldCoord(d.x,d.y,d.z+C.markerHeight)
            local baseVisible,bx,by=GetScreenCoordFromWorldCoord(d.x,d.y,d.z+0.5)
            if onScreen and x>0.03 and x<0.97 and y>0.04 and y<0.88 then
                SendNUIMessage({action='marker',visible=true,x=x,y=y,
                    bottom=baseVisible and math.min(by,0.94) or y+0.12,
                    distance=d.distance,label=d.label,color=settings.color})
                markerVisible=true
            else hideMarker() end
            Wait(0)
        else hideMarker(); Wait(150) end
    end
end)
CreateThread(function()
    while true do
        if menuOpen then
            DisableControlAction(0,1,true); DisableControlAction(0,2,true)
            DisableControlAction(0,24,true); DisableControlAction(0,25,true)
            DisableControlAction(0,75,true); DisableControlAction(0,200,true)
            if IsPauseMenuActive() or IsEntityDead(PlayerPedId()) then closeMenu() end
            Wait(0)
        else Wait(200) end
    end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    SetResourceKvp(kvp,json.encode(settings))
    if menuOpen then SetNuiFocus(false,false) end
    if custom and DoesBlipExist(custom.blip) then RemoveBlip(custom.blip) end
end)
