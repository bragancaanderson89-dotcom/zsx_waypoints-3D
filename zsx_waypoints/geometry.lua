WaypointGeometry = {}
local G = WaypointGeometry
function G.finite(n)
    return type(n) == 'number' and n == n and n > -math.huge and n < math.huge
end
function G.clamp(n, lo, hi, fallback)
    if not G.finite(n) then return fallback end
    return math.max(lo, math.min(hi, n))
end
function G.settings(input, defaults)
    input = type(input) == 'table' and input or {}
    local function toggle(key)
        if type(input[key]) == 'boolean' then return input[key] end
        return defaults[key]
    end
    return {
        road = toggle('road'), destination = toggle('destination'),
        color = type(input.color) == 'string' and input.color:match('^#%x%x%x%x%x%x$') and input.color or defaults.color,
        spacing = G.clamp(input.spacing, 4.0, 20.0, defaults.spacing),
        opacity = G.clamp(input.opacity, 0.10, 1.0, defaults.opacity),
        lift = G.clamp(input.lift, 0.05, 1.5, defaults.lift),
        scale = G.clamp(input.scale, 0.5, 2.0, defaults.scale)
    }
end
function G.rgb(hex)
    return tonumber(hex:sub(2,3),16), tonumber(hex:sub(4,5),16), tonumber(hex:sub(6,7),16)
end
function G.distance(a,b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end
function G.validPoint(p)
    local kind=type(p)
    if kind~='table' and kind~='vector3' and kind~='vector4' then return false end
    return G.finite(p.x) and G.finite(p.y) and G.finite(p.z)
        and math.abs(p.x) < 20000 and math.abs(p.y) < 20000 and math.abs(p.z) < 2500
end
-- Two parallelograms form a V, oriented along the GPS route, including slopes.
function G.chevron(p, nextPoint, scale, lift)
    local dx,dy,dz = nextPoint.x-p.x,nextPoint.y-p.y,nextPoint.z-p.z
    local length = math.sqrt(dx*dx+dy*dy)
    if length < 0.1 or length > 35 or math.abs(dz) > length * 0.8 then return nil end
    local fx,fy,fz = dx/length,dy/length,dz/length
    local function point(side, forward)
        return {x=p.x+fy*side*scale+fx*forward*scale,
            y=p.y-fx*side*scale+fy*forward*scale,
            z=p.z+lift+fz*forward*scale}
    end
    return {point(-1.35,-0.70),point(0,0.75),point(1.35,-0.70),
        point(1.35,-1.25),point(0,0.20),point(-1.35,-1.25)}
end

-- Match in world space; blend from the currently rendered geometry, never from
-- the previous sample's target. This avoids jumps when a sample arrives mid-frame.
function G.prepareRoute(previous, pending, now, duration, spacing)
    local used = {}
    for _, entry in ipairs(pending) do
        local best, distance = nil, spacing * 0.8
        for index, old in ipairs(previous) do
            local d = G.distance(entry.p, old.p)
            if not used[index] and d < distance then best, distance = index, d end
        end
        entry.started, entry.duration = now, duration
        entry.targetVertices, entry.targetGlow = entry.vertices, entry.glow
        if best then
            local old = previous[best]
            used[best] = true
            entry.fromVertices, entry.fromGlow = old.vertices, old.glow
            entry.fromAlpha = old.alpha or 1
        else
            entry.fromVertices, entry.fromGlow = entry.vertices, entry.glow
            entry.fromAlpha = 0
        end
        entry.vertices, entry.glow = {}, {}
        for i=1,6 do entry.vertices[i]={}; entry.glow[i]={} end
        G.animateEntry(entry, now)
    end
    return pending
end
function G.animateEntry(entry, now)
    if entry.finished then return end
    local t = math.max(0, math.min(1, (now-entry.started)/entry.duration))
    entry.alpha = entry.fromAlpha + (1-entry.fromAlpha)*t
    for i=1,6 do
        for _,axis in ipairs({'x','y','z'}) do
            local a,b=entry.fromVertices[i][axis],entry.targetVertices[i][axis]
            entry.vertices[i][axis]=a+(b-a)*t
            a,b=entry.fromGlow[i][axis],entry.targetGlow[i][axis]
            entry.glow[i][axis]=a+(b-a)*t
        end
    end
    entry.finished = t >= 1
end
