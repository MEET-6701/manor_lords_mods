-- Each feature keeps its original state and error handling.
local function startFeature(name, start)
    local ok, problem = pcall(start)
    if not ok then print("[ManorLordsModPack] " .. name .. ": " .. tostring(problem) .. "\n") end
end

startFeature("NPCPloughing2x", function()
    -- NPCFarming4x. Keeps the original mod folder for upgrades.
    local MULTIPLIER = 4.0
    local MANUAL_PLOW_ACTION = 51 -- ManorLords.EActionType.PlowManual
    local PLANT_OR_TRAP_ACTION = 8 -- ManorLords.EActionType.PlantingOrTrapping
    local SOWING_TASK = 11 -- ManorLords.ETaskType.Sowing
    local originals = {}
    local reported = {}
    local errors = 0

    local function log(message)
        print('[NPCFarming4x] ' .. message .. '\n')
    end

    local function once(key, message)
        if not reported[key] then reported[key] = true; log(message) end
    end

    local function finitePositive(value)
        return type(value) == 'number' and value > 0 and value < math.huge
    end

    local function getFarmingAction(unit)
        local action = unit:GetAction()
        if action == MANUAL_PLOW_ACTION then return 'ploughing' end
        if action ~= PLANT_OR_TRAP_ACTION then return end

        -- The action is shared with trapping. Require a sowing task as well.
        local sowing = false
        unit.Tasks:ForEach(function(_, parameter)
            if parameter:get().Type == SOWING_TASK then
                sowing = true
                return true
            end
        end)
        if sowing then return 'sowing' end
    end

    local function patchForUnit(unit)
        if not unit:IsValid() or unit.dead then return end
        local farmingAction = getFarmingAction(unit)
        if not farmingAction then return end
        if not unit:isHumanCivilian(false) then return end
        local dt = unit.currentAnimsetDT
        if not dt or not dt:IsValid() then return end
        local animationID = unit.targetAnim
        local tableName = dt:GetFullName()
        local matched = false
        dt:ForEachRow(function(rowName, row)
            if row.ID ~= animationID then return end
            -- Confirm both the live action and animation identity before changing shared data.
            local tag = (tostring(rowName) .. ' ' .. row.Tag:ToString()):lower()
            local candidates = {}
            local farmingClip = false
            row.variations:ForEach(function(index, parameter)
                local clip = parameter:get()
                local name = clip.clipName:ToString():lower()
                local identity = tag .. ' ' .. name
                if identity:find('ox', 1, true) or identity:find('heavy', 1, true) then return end
                if farmingAction == 'ploughing' then
                    if identity:find('plow', 1, true) or identity:find('plough', 1, true)
                        or identity:find('hoe', 1, true) then farmingClip = true end
                elseif identity:find('sow', 1, true) or identity:find('seed', 1, true) then
                    if identity:find('trap', 1, true) then return end
                    farmingClip = true
                else
                    return
                end
                candidates[#candidates + 1] = {index = index, clip = clip}
            end)
            if not farmingClip or #candidates ~= #row.variations or #candidates == 0 then
                once(tableName .. tostring(rowName), 'Skipped unconfirmed animation: '
                    .. tableName .. ' row=' .. tostring(rowName) .. ' tag=' .. tag
                    .. ' targetAnim=' .. tostring(animationID))
                return
            end
            matched = true
            -- Validate all entries first. Repeated polling must never compound the multiplier.
            local changes = {}
            for _, candidate in ipairs(candidates) do
                local clip = candidate.clip
                local key = tableName .. '/' .. tostring(rowName) .. '/' .. candidate.index
                local original = originals[key]
                if not original then
                    if not finitePositive(clip.spd) or type(clip.speedVariation) ~= 'number'
                        or clip.speedVariation ~= clip.speedVariation
                        or math.abs(clip.speedVariation) == math.huge then
                        once(key, 'Skipped invalid rate: ' .. key); return
                    end
                    original = {speed = clip.spd, variation = clip.speedVariation}
                end
                local target = original.speed * MULTIPLIER
                local targetVariation = original.variation * MULTIPLIER
                local function close(a, b) return math.abs(a - b) < 0.00001 end
                if not (close(clip.spd, original.speed) or close(clip.spd, target))
                    or not (close(clip.speedVariation, original.variation)
                        or close(clip.speedVariation, targetVariation)) then
                    once(key .. '/conflict', 'Skipped conflicting animation rate: ' .. key); return
                end
                changes[#changes + 1] = {clip = clip, key = key, original = original,
                    speed = target, variation = targetVariation}
            end
            for _, change in ipairs(changes) do
                originals[change.key] = change.original
                change.clip.spd = change.speed
                change.clip.speedVariation = change.variation
                once(change.key .. '/patched', string.format('Applied 4x %s animation rate: %s %.4f -> %.4f',
                    farmingAction, change.key, change.original.speed, change.speed))
            end
        end)
        if not matched then
            once(tableName .. '/missing/' .. tostring(animationID),
                'No confirmed ' .. farmingAction .. ' animation row found for targetAnim='
                .. tostring(animationID) .. ' table=' .. tableName)
        end
    end

    local function scan()
        local units = FindAllOf('SMUnit') or {}
        for _, unit in ipairs(units) do patchForUnit(unit) end
    end

    log('Loaded. Waiting for villagers to plough manually or sow. Multiplier=4.0.')
    if type(LoopInGameThreadWithDelay) ~= 'function' then
        log('DISABLED: this loader lacks LoopInGameThreadWithDelay.'); return
    end
    LoopInGameThreadWithDelay(1000, function()
        local ok, problem = pcall(scan)
        if not ok then
            errors = errors + 1
            if errors <= 3 then log('Runtime error: ' .. tostring(problem)) end
            if errors >= 3 then log('Stopped after 3 errors. Disable mod and restart.'); return true end
        end
        return false
    end)
end)

startFeature("TreeGrowth4x", function()
    local TREE_GROWTH_RATE = 10.0
    local previousError

    local function log(message)
        print("[TreeGrowth10x] " .. message .. "\n")
    end

    local function applyGrowthRate()
        local region = FindFirstOf("Region")
        if not region or not region:IsValid() then
            return
        end

        local gameInstance = FindFirstOf("MLGameInstance")
        if not gameInstance or not gameInstance:IsValid() then
            return
        end

        local settings = gameInstance.gameSetup.currentGameSetup
        local currentRate = settings.treeGrowthRate
        if type(currentRate) ~= "number" then
            error("Expected a numeric treeGrowthRate in the active game setup")
        end

        if currentRate ~= TREE_GROWTH_RATE then
            settings.treeGrowthRate = TREE_GROWTH_RATE
            local appliedRate = gameInstance.gameSetup.currentGameSetup.treeGrowthRate
            if appliedRate ~= TREE_GROWTH_RATE then
                error("The new treeGrowthRate could not be read back")
            end
            log(string.format("Applied treeGrowthRate %.4g -> %.4g", currentRate, appliedRate))
        end
    end

    log(string.format("Loaded. Waiting for a settlement. Target treeGrowthRate=%.1f.", TREE_GROWTH_RATE))
    LoopInGameThreadWithDelay(1000, function()
        local ok, problem = pcall(applyGrowthRate)
        if ok then
            previousError = nil
        elseif problem ~= previousError then
            previousError = problem
            log(tostring(problem))
        end
        return false
    end)
end)

startFeature("Tariff5PastureBreeding", function()
    local IMPORT_FEE = 2
    local MONTHS_PER_YEAR = 12
    local PASTURE = 10
    local offspringRole = {[10] = 11, [21] = 22} -- Sheep -> Lamb, Cow -> Calf
    local offspringName = {[10] = "lamb", [21] = "calf"}

    local cooldownKey = FName("Tariff5PastureBreeding_NextMonth", EFindName.FNAME_Add)
    local livestockSettings
    local originalSheepChance, originalCowChance
    local lastEngine, lastDay
    local breedingFailed = false

    local function log(message)
        print("[Tariff5PastureBreeding] " .. message .. "\n")
    end

    local function valid(object)
        return object and object:IsValid()
    end

    local function nextMonth(animal)
        local data = animal.customUnitData
        if not data:Contains(cooldownKey) then return nil end
        local value = data:Find(cooldownKey):get()
        local month = tonumber(type(value) == "string" and value or value:ToString())
        assert(month and math.tointeger(month), "Invalid saved breeding month")
        return month
    end

    local function setNextMonth(animal, month)
        animal.customUnitData:Add(cooldownKey, FString(tostring(month)))
        assert(nextMonth(animal) == month, "Could not save the breeding cooldown")
    end

    local function breedPasture(engine, pasture, month, regionCapacity)
        if pasture.Data.bType ~= PASTURE or not pasture.Data.constructed then return end
        local region = pasture.Region
        if not valid(region) or not region.isSettled then return end

        local regionKey = region:GetFullName()
        if regionCapacity[regionKey] == nil then
            regionCapacity[regionKey] = region:getTotalPastureSpace() - region:getTotalPastureNeeds()
        end
        local space = pasture.animalSpaceCache
        local freeSlots = math.min(space.pastureMax - math.max(space.pastureCurrent, #pasture.animalsOnPasture),
            regionCapacity[regionKey])

        local ready = {[10] = {}, [21] = {}}
        local seen = {}
        pasture.animalsOnPasture:ForEach(function(_, entry)
            local animal = entry:get()
            if not valid(animal) or animal.dead then return end
            local group = ready[animal.currentUnitRole]
            if not group then return end
            local name = animal:GetFullName()
            if seen[name] then return end
            seen[name] = true

            local due = nextMonth(animal)
            if not due then
                setNextMonth(animal, month + MONTHS_PER_YEAR)
            elseif month >= due then
                group[#group + 1] = {animal = animal, due = due, name = name}
            end
        end)

        for _, role in ipairs({10, 21}) do
            local group = ready[role]
            table.sort(group, function(a, b)
                if a.due ~= b.due then return a.due < b.due end
                return a.name < b.name
            end)
            for index = 1, #group - 1, 2 do
                if freeSlots < 1 then return end
                local first, second = group[index], group[index + 1]
                setNextMonth(first.animal, month + MONTHS_PER_YEAR)
                setNextMonth(second.animal, month + MONTHS_PER_YEAR)
                local baby = engine:SpawnLivestock(offspringRole[role], first.animal.realPos, region)
                if not valid(baby) then
                    setNextMonth(first.animal, first.due)
                    setNextMonth(second.animal, second.due)
                    error("SpawnLivestock returned no newborn")
                end
                assert(baby.currentUnitRole == offspringRole[role], "Unexpected newborn role")
                freeSlots = freeSlots - 1
                regionCapacity[regionKey] = regionCapacity[regionKey] - 1
                log(string.format("Born: %s in %s. Parents eligible again in 12 game months.",
                    offspringName[role], region.regionName:ToString()))
            end
        end
    end

    local function updateBreeding()
        if breedingFailed then return end
        local engine = FindFirstOf("RTSMultiEngineCPP")
        if not valid(engine) or not valid(engine.TemporalComponent) then return end
        local clock = engine.TemporalComponent
        local engineName = engine:GetFullName()
        if engineName == lastEngine and clock.daysTotal == lastDay then return end

        if not valid(livestockSettings) then
            livestockSettings = StaticFindObject("/Script/ManorLords.Default__LivestockSettings")
            if not valid(livestockSettings) then return end
            originalSheepChance = livestockSettings.SheepConceptionChance
            originalCowChance = livestockSettings.CowConceptionChance
            assert(type(originalSheepChance) == "number" and type(originalCowChance) == "number",
                "Conception settings unavailable")
            livestockSettings.SheepConceptionChance = 0
            livestockSettings.CowConceptionChance = 0
            assert(livestockSettings.SheepConceptionChance == 0 and livestockSettings.CowConceptionChance == 0,
                "Could not disable random conception")
            log("Annual pasture breeding active.")
        end

        local regionCapacity = {}
        for _, pasture in ipairs(FindAllOf("SMBuildingMaster") or {}) do
            if valid(pasture) and valid(pasture.masterPtr) and pasture.masterPtr:GetFullName() == engineName then
                breedPasture(engine, pasture, clock.monthsTotal, regionCapacity)
            end
        end
        lastEngine, lastDay = engineName, clock.daysTotal
    end

    local function applyTariff()
        local settings = StaticFindObject("/Script/ManorLords.Default__TradeSettings")
        if not valid(settings) then return end
        local oldFee = settings.importFee
        if oldFee == IMPORT_FEE then return end
        assert(type(oldFee) == "number", "Import fee setting unavailable")
        settings.importFee = IMPORT_FEE
        assert(settings.importFee == IMPORT_FEE, "Could not apply import fee")
        log(string.format("Import fee %d -> %d.", oldFee, IMPORT_FEE))
    end

    log(string.format("Loaded. Import fee %d and one newborn per eligible pair per 12 game months.", IMPORT_FEE))
    local lastTariffError
    LoopInGameThreadWithDelay(1000, function()
        local tariffOk, tariffError = pcall(applyTariff)
        if not tariffOk and tariffError ~= lastTariffError then
            log(tostring(tariffError))
        end
        lastTariffError = tariffError

        local breedingOk, breedingError = pcall(updateBreeding)
        if not breedingOk then
            breedingFailed = true
            if valid(livestockSettings) and type(originalSheepChance) == "number"
                and type(originalCowChance) == "number" then
                livestockSettings.SheepConceptionChance = originalSheepChance
                livestockSettings.CowConceptionChance = originalCowChance
            end
            log("Annual breeding stopped: " .. tostring(breedingError))
        end
        return false
    end)
end)

startFeature("YarnClothes4x", function()
    -- EItemType values from the installed Manor Lords build.
    local fabrics = {[12] = "linen", [148] = "yarn"}
    local CLOTHES = 149
    local CLOTHES_PER_FABRIC = 4
    local patchedTableAddress
    local previousError

    local function log(message)
        print("[YarnClothes4x] " .. message .. "\n")
    end

    local function applyRecipe()
        local engine = FindFirstOf("RTSMultiEngineCPP")
        if not engine or not engine:IsValid() then return end

        local items = engine.itemStats
        if not items or not items:IsValid() then return end
        local address = items:GetAddress()
        if address == patchedTableAddress then return end

        local found = {}
        items:ForEachRow(function(name, row)
            local fabricAmount = 0
            local ingredients = {}
            row.Resources:ForEach(function(_, entry)
                local input = entry:get()
                local fabric = fabrics[input.Type]
                if fabric and input.amt > 0 then
                    fabricAmount = fabricAmount + input.amt
                    ingredients[#ingredients + 1] = string.format("%d %s", input.amt, fabric)
                end
            end)
            if fabricAmount <= 0 then return end

            local output
            row.craftingOutput:ForEach(function(_, entry)
                local good = entry:get()
                if good.Type == CLOTHES then
                    assert(not output, "Multiple clothes outputs in recipe " .. tostring(name))
                    output = good
                end
            end)
            if not output then return end

            local oldAmount = output.amt
            local newAmount = fabricAmount * CLOTHES_PER_FABRIC
            output.amt = newAmount
            assert(output.amt == newAmount, "Could not update clothes output")
            log(string.format("%s uses %s and yields %d clothes (was %d).",
                tostring(name), table.concat(ingredients, " + "), newAmount, oldAmount))
            row.Resources:ForEach(function(_, entry)
                local input = entry:get()
                if fabrics[input.Type] and input.amt > 0 then found[input.Type] = true end
            end)
        end)

        for id, fabric in pairs(fabrics) do
            if not found[id] then log("No " .. fabric .. "-to-clothes recipe found in the active item table.") end
        end
        patchedTableAddress = address
    end

    log("Loaded. Waiting for the settlement item table.")
    LoopInGameThreadWithDelay(1000, function()
        local ok, problem = pcall(applyRecipe)
        if not ok and problem ~= previousError then log(tostring(problem)) end
        previousError = problem
        return false
    end)
end)

startFeature("BarleyMaltAle", function()
    -- Item IDs from the installed build's EItemType enum.
    local recipes = {
        {input = 165, output = 29, yield = 4, name = "barley to malt"},
        {input = 29, output = 28, yield = 4, name = "malt to ale"},
    }

    local patchedTableAddress
    local previousError

    local function log(message)
        print("[BarleyMaltAle] " .. message .. "\n")
    end

    local function patchRecipe(row, recipe)
        local inputAmount = 0
        row.Resources:ForEach(function(_, entry)
            local good = entry:get()
            if good.Type == recipe.input then inputAmount = inputAmount + good.amt end
        end)
        if inputAmount <= 0 then return false end

        local output
        row.craftingOutput:ForEach(function(_, entry)
            local good = entry:get()
            if good.Type == recipe.output then
                assert(not output, "Multiple outputs for " .. recipe.name)
                output = good
            end
        end)
        if not output then return false end

        local newAmount = inputAmount * recipe.yield
        output.amt = newAmount
        assert(output.amt == newAmount, "Could not update " .. recipe.name)
        log(string.format("%s yields %d output for %d input.", recipe.name, newAmount, inputAmount))
        return true
    end

    local function applyRecipes()
        local engine = FindFirstOf("RTSMultiEngineCPP")
        if not engine or not engine:IsValid() then return end
        local items = engine.itemStats
        if not items or not items:IsValid() then return end

        local address = items:GetAddress()
        if address == patchedTableAddress then return end
        local found = {}
        items:ForEachRow(function(_, row)
            for index, recipe in ipairs(recipes) do
                if patchRecipe(row, recipe) then found[index] = true end
            end
        end)
        for index, recipe in ipairs(recipes) do
            if not found[index] then log("No matching recipe for " .. recipe.name .. ".") end
        end
        patchedTableAddress = address
    end

    log("Loaded. Waiting for the settlement item table.")
    LoopInGameThreadWithDelay(1000, function()
        local ok, problem = pcall(applyRecipes)
        if not ok and problem ~= previousError then log(tostring(problem)) end
        previousError = problem
        return false
    end)
end)

startFeature("Planks15RoyalTax500", function()
    -- EItemType values from the installed Manor Lords build.
    local TIMBER = 16
    local PLANKS = 17
    local PLANKS_PER_TIMBER = 15
    local patchedTableAddress
    local previousError

    local function log(message)
        print("[Planks15RoyalTax500] " .. message .. "\n")
    end

    local function applyRecipe()
        local engine = FindFirstOf("RTSMultiEngineCPP")
        if not engine or not engine:IsValid() then return end

        local items = engine.itemStats
        if not items or not items:IsValid() then return end
        local address = items:GetAddress()
        if address == patchedTableAddress then return end

        local matches = 0
        items:ForEachRow(function(name, row)
            local timberAmount = 0
            row.Resources:ForEach(function(_, entry)
                local input = entry:get()
                if input.Type == TIMBER then timberAmount = timberAmount + input.amt end
            end)
            if timberAmount <= 0 then return end

            local output
            row.craftingOutput:ForEach(function(_, entry)
                local good = entry:get()
                if good.Type == PLANKS then
                    assert(not output, "Multiple planks outputs in recipe " .. tostring(name))
                    output = good
                end
            end)
            if not output then return end

            local oldAmount = output.amt
            local newAmount = timberAmount * PLANKS_PER_TIMBER
            output.amt = newAmount
            assert(output.amt == newAmount, "Could not update planks output")
            matches = matches + 1
            log(string.format("%s uses %d timber and yields %d planks (was %d).",
                tostring(name), timberAmount, newAmount, oldAmount))
        end)

        if matches == 0 then log("No timber-to-planks recipe found in the active item table.") end
        patchedTableAddress = address
    end

    local function applyTaxCap()
        local win64 = IterateGameDirectories().Game.Binaries.Win64.__absolute_path
        local path = win64 .. "/ue4ss/Mods/ManorLordsModPack/RoyalTaxCap.dll"
        local apply, reason = package.loadlib(path, "ApplyRoyalTaxCap")
        assert(apply, reason)
        assert(apply(true), "Royal tax cap refused this game build or could not patch memory.")
        log("Royal tax cap applied at 500.")
    end

    local attemptedTaxCap = false
    log("Loaded. Waiting for the settlement item table.")
    LoopInGameThreadWithDelay(1000, function()
        if not attemptedTaxCap then
            attemptedTaxCap = true
            local taxOk, taxError = pcall(applyTaxCap)
            if not taxOk then log("Royal tax cap unavailable: " .. tostring(taxError)) end
        end
        local ok, problem = pcall(applyRecipe)
        if not ok and problem ~= previousError then log(tostring(problem)) end
        previousError = problem
        return false
    end)
end)
