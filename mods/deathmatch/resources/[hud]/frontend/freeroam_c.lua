-- The 8 x 8 PS2 radar tiles each cover 500 world units, north at the top.
function createViceCityMapImage(x, y, width, height, parent)
    return guiCreateStaticImage(x, y, width, height, ":frontend/res/vice_city_map.png", true, parent)
end

function viceCityMapToWorld(u, v)
    return (u - 0.5) * 4000, (0.5 - v) * 4000
end

function worldToViceCityMap(x, y)
    return x / 4000 + 0.5, 0.5 - y / 4000
end

function createMenuTabPanel(x, y, width, height, parent)
    return guiCreateTabPanel(x, y, width, height, true, parent)
end

function createMenuTab(title, panel)
    return guiCreateTab(title, panel)
end

function getVehicleSpawnMenuGroups(catalog, legacy, rcVehicles)
    local rows, categories, labelCounts = {}, {}, {}
    local function add(id, base, label, provider, modelName, category)
        category = category or getVehicleType(base) or 'Other'
        if not categories[category] then
            categories[category] = {'group', name=category, children={}}
            table.insert(rows, categories[category])
        end
        labelCounts[label] = (labelCounts[label] or 0) + 1
        table.insert(categories[category].children, {'vehicle', id=id, name=label, provider=provider, modelName=modelName})
    end
    local labels = {}
    for key, entry in pairs(legacy) do
        local name = entry.name == 'phoenix' and 'pheonix' or entry.name
        labels[name] = getVcsText(key)
        if not catalog[name] then
            add(key, entry.base, labels[name] or key, 'dlc', entry.name)
        end
    end
    for name, entry in pairs(catalog) do
        local label = getVcsText(entry.textKey or name:upper()) or labels[name]
        add(entry.id, entry.base, label or name:gsub('^%l', string.upper), 'vcs', name)
    end
    for id, name in pairs(rcVehicles or {}) do
        add(id, id, name, nil, name, 'RC Vehicles')
    end
    local function byName(a, b) return a.name < b.name end
    table.sort(rows, byName)
    for _, group in ipairs(rows) do
        for _, vehicle in ipairs(group.children) do
            if labelCounts[vehicle.name] > 1 then
                vehicle.name = vehicle.name .. " (" .. vehicle.modelName .. ")"
            end
        end
        table.sort(group.children, byName)
    end
    return rows
end
