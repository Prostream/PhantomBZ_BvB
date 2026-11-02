-- Pure Lua controller tests; no UE4SS globals or game objects are used.
local Arena = dofile("Mods/PhantomGladiator/Scripts/arena_controller.lua")
local function fixture(overrides)
    local trace, actors, transforms, synced = {}, {}, {}, {}
    local player, world, cls = { name = "player", alive = true }, { alive = true }, { alive = true }
    local catalog = { selectedPath = "/Catalog/BP_Test.BP_Test_C" }
    function catalog:registerPath(path) trace[#trace + 1] = "register"; return { path = path } end
    function catalog:select(path) self.selectedPath = path; trace[#trace + 1] = "select"; return { path = path } end
    function catalog:refresh(npcs) assert(next(npcs) == nil); trace[#trace + 1] = "refresh"; return {} end
    function catalog:resolveSelected() trace[#trace + 1] = "resolve"; return cls end
    function catalog:selected() return { path = self.selectedPath } end
    local options = {
        catalog = catalog, log = function() end,
        canSpawn = function() return true end, -- Explicit fixture permission, not a production fallback.
        valid = function(object) return object ~= nil and object.alive == true end,
        name = function(actor) assert(actor.alive); return actor.name end,
        hp = function(actor) assert(actor.alive); return actor.hp or 400 end,
        combatReady = function(actor) assert(actor.alive); return true end,
        getPlayer = function() return player end,
        getWorld = function(p) assert(p == player and p.alive); return world end,
        getLocation = function(p) assert(p == player and p.alive); return { X = 0, Y = 0, Z = 100 } end,
        getForward = function(p) assert(p == player and p.alive); return { X = 2, Y = 0, Z = 0 } end,
        spawnClass = function(c, transform, w)
            assert(c == cls and w == world and cls.alive and world.alive)
            trace[#trace + 1] = "spawn"
            transforms[#transforms + 1] = transform
            local actor = { alive = true, name = "unit" .. (#actors + 1) }
            actors[#actors + 1] = actor
            return actor
        end,
        onUnitsChanged = function(units)
            trace[#trace + 1] = "sync"
            synced = units
        end,
        activate = function(actor)
            assert(actor.alive)
            local found = false
            for _, unit in ipairs(synced) do if unit.actor == actor then found = true end end
            assert(found, "ownership must be synchronized before activation")
            trace[#trace + 1] = "activate"
            return true
        end,
        setRelation = function(a, b, relation)
            assert(a.alive and b.alive)
            trace[#trace + 1] = { "relation", a, b, relation }
            return true
        end,
        forceAttack = function(a, b)
            assert(a.alive and b.alive and a ~= b)
            trace[#trace + 1] = { "attack", a, b }
            return true
        end,
        restore = function() trace[#trace + 1] = "restore"; return true end,
        destroy = function(actor) trace[#trace + 1] = "destroy"; actor.alive = false end,
        onBattleStarted = function(a, b) trace[#trace + 1] = { "observe", a, b } end,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return { arena = Arena.new(options), options = options, catalog = catalog, player = player, world = world,
        cls = cls, trace = trace, actors = actors, transforms = transforms, synced = function() return synced end }
end

local function stageCount(fixtureValue, stage)
    local count = 0
    for _, event in ipairs(fixtureValue.trace) do
        if event == stage or (type(event) == "table" and event[1] == stage) then count = count + 1 end
    end
    return count
end

local f = fixture()
local warningSpawn=fixture({activate=function()return true,'activated','数值未统一，已回滚到原生值' end})
assert(warningSpawn.arena:spawn(nil,'blue',1).ok)
local warningResult=warningSpawn.arena:spawn(nil,'red',1)
assert(warningResult.ok and warningResult.message:find('数值未统一',1,true))
assert(warningSpawn.arena:status().state~='cleanup_pending' and warningSpawn.arena:start().ok,
    'a safely rolled-back optional stat change must not remove HUDs or block normal combat')
local prepared=fixture()
assert(prepared.arena:spawn(nil,'blue',1).ok and prepared.arena:spawn(nil,'red',1).ok)
prepared.options.prepareBattle=function(members)
    assert(#members==2 and stageCount(prepared,'attack')==0 and stageCount(prepared,'relation')==0)
    return false
end
assert(not prepared.arena:start().ok and stageCount(prepared,'attack')==0,'unconfirmed preparation cannot request combat')
prepared.options.prepareBattle=function()return true end
assert(prepared.arena:start().ok and stageCount(prepared,'attack')==2)
-- Reproduce the multi-second spawn hitch: a selected path must never run discovery.
local directSpawn=fixture()
function directSpawn.catalog:refresh()error('full class discovery on the spawn path')end
assert(directSpawn.arena:spawn('/Catalog/BP_Chosen.BP_Chosen_C','blue',1).ok,
    'spawning an exact selected class must not perform a global catalog refresh')
assert(stageCount(directSpawn,'resolve')==1 and stageCount(directSpawn,'spawn')==1)
-- Switching the next spawn team cannot move existing participants or spawn one.
local teamCycle=fixture()
assert(teamCycle.arena:spawn('/Catalog/BP_Test.BP_Test_C','blue',1).ok)
assert(teamCycle.arena:select('/Catalog/BP_Test.BP_Test_C','blue',3).ok)
local beforeTeamCycle=#teamCycle.trace
for revision,wanted in ipairs({'red','neutral','companion','blue'})do
    local changed=teamCycle.arena:cycleTeam()
    local status=teamCycle.arena:status()
    assert(changed.ok and changed.spawned_count==0 and status.current_team==wanted and status.team_revision==revision)
    assert(status.current_count==3 and status.current_unit=='/Catalog/BP_Test.BP_Test_C')
    assert(status.blue_count==1 and status.red_count==0 and status.neutral_count==0)
end
assert(#teamCycle.trace==beforeTeamCycle,'cycling must not call spawn, relation or attack callbacks')
assert(teamCycle.arena:cycleTeam().ok)
assert(teamCycle.arena:spawn().ok and teamCycle.arena:status().red_count==3,'next shortcut spawn must use the cycled team')
local summons=fixture()
assert(summons.arena:spawn('/Catalog/BP_Owner.BP_Owner_C','blue',1).ok)
assert(summons.arena:spawn('/Catalog/BP_Enemy.BP_Enemy_C','red',1).ok)
assert(summons.arena:start().ok)
local pet={alive=true,name='summon',hp=100}
assert(not summons.arena:adoptSummon(pet,{alive=true},'/Catalog/BP_Pet.BP_Pet_C','fixture').ok,'unowned summoner must never claim a map actor')
assert(summons.arena:adoptSummon(pet,summons.actors[1],'/Catalog/BP_Pet.BP_Pet_C','fixture').ok)
assert(summons.arena:status().blue_count==2 and summons.arena:status().summon_count==1)
local attacks=stageCount(summons,'attack')
summons.arena:tickReinforcements()
assert(stageCount(summons,'attack')==attacks+1,'new summon should be directed at the opposing team')
summons.arena:tickReinforcements()
assert(stageCount(summons,'attack')==attacks+1,'stable targets must not be forced again every tick')
assert(summons.arena:stop().ok and not pet.alive,'owned summons must be included in cleanup')
local unlimited=fixture({maxUnits=0})
for _=1,4 do assert(unlimited.arena:spawn(nil,'blue',8).ok) end
assert(unlimited.arena:status().total==32 and unlimited.arena:status().max_units==0)
assert(unlimited.arena:spawn(nil,'neutral',2).ok)
local restoresBefore=stageCount(unlimited,'restore')
assert(unlimited.arena:clearNeutral().ok)
assert(unlimited.arena:status().blue_count==32 and unlimited.arena:status().neutral_count==0)
assert(stageCount(unlimited,'restore')==restoresBefore,'neutral cleanup must not reset blue/red battles')
local death=fixture()
assert(death.arena:spawn(nil,'blue',1).ok)
death.actors[1].hp=0
local deadState=death.arena:status()
assert(deadState.blue_count==0 and deadState.dead_count==1 and deadState.owned_records==1,'HP zero must leave live counts immediately without dropping cleanup ownership')
death.actors[1].hp=400
assert(death.arena:status().blue_count==1,'a revived phase must be counted again')
death.actors[1].hp=0
assert(death.arena:stop().ok and death.arena:status().owned_records==0,'dead actors must remain cleanable')
local limited=fixture({maxUnits=2})
assert(limited.arena:spawn('/Catalog/BP_A.BP_A_C','blue',1).ok)
assert(limited.arena:spawn('/Catalog/BP_B.BP_B_C','red',1).ok)
local beforeLimit=stageCount(limited,'resolve')
assert(not limited.arena:spawn('/Catalog/BP_C.BP_C_C','blue',1).ok)
assert(stageCount(limited,'resolve')==beforeLimit and #limited.actors==2,'total trial limit applies across different classes before loading')
assert(f.arena:status().current_team == "blue" and f.arena:status().current_count == 1)
local blue = f.arena:spawn("/Catalog/BP_A.BP_A_C", "blue", 2)
assert(blue.ok and blue.spawned_count == 2 and blue.activated_count == 2)
assert(stageCount(f,'refresh')==0 and f.trace[3]=='resolve','resolve the selected path directly without discovery')
assert(not f.arena:start().ok, "one team cannot start a battle")
local red = f.arena:spawn("/Catalog/BP_B.BP_B_C", "red", 2)
assert(red.ok and f.arena:status().total == 4)
local positions = {}
for _, transform in ipairs(f.transforms) do
    local p = transform.Translation
    local key = p.X .. "," .. p.Y .. "," .. p.Z
    assert(not positions[key], "spawn slots must be distinct")
    positions[key] = true
    assert(p.X >= 600 and p.Z == 150, "horizontal forward vector must be normalized")
end
assert(f.arena:start().ok)
local relationCount, attackCount, observeCount = 0, 0, 0
local owned, teams = {}, {}
for _, unit in ipairs(f.synced()) do owned[unit.actor], teams[unit.actor] = true, unit.team end
for _, event in ipairs(f.trace) do
    if type(event) == "table" then
        if event[1] == "relation" then
            relationCount = relationCount + 1
            assert(event[3] ~= f.player, 'starting a battle must not silently grant no-aggro while F8 is off')
            assert(owned[event[2]] and (event[3] == f.player or owned[event[3]]))
            if event[4] == 2 then assert(teams[event[2]] ~= teams[event[3]]) else assert(event[4]==0 and teams[event[2]]==teams[event[3]]) end
        elseif event[1] == "attack" then
            attackCount = attackCount + 1
            assert(owned[event[2]] and owned[event[3]] and teams[event[2]] ~= teams[event[3]])
        elseif event[1] == "observe" then observeCount = observeCount + 1 end
    end
end
assert(relationCount == 6 and attackCount == 4 and observeCount == 1)
local cleanup = f.arena:stop()
assert(cleanup.ok and cleanup.remaining_count == 0 and f.arena:status().total == 0)
local restoreIndex, destroyIndex
for i, event in ipairs(f.trace) do
    if event == "restore" then restoreIndex = i end
    if event == "destroy" and not destroyIndex then destroyIndex = i end
end
assert(restoreIndex < destroyIndex)

f = fixture()
assert(not f.arena:select("/Catalog/X.X_C", "red", 101).ok and f.arena:select("/Catalog/X.X_C", "red", 50).ok)
assert(not f.arena:spawn(nil, "invalid", 1).ok and #f.actors == 0)
assert(not f.arena:spawn(nil, "blue", 1.5).ok)
for _ = 1, 3 do assert(f.arena:spawn(nil, "blue", 8).ok) end
assert(f.arena:status().total == 24)
assert(not f.arena:spawn(nil, "red", 1).ok and #f.actors == 24)

f = fixture()
local originalSpawn, originalActivate, spawnCalls = f.options.spawnClass, f.options.activate, 0
f.options.spawnClass = function(...)
    spawnCalls = spawnCalls + 1
    if spawnCalls == 2 then return nil, "failed before native spawn", "not_started" end
    return originalSpawn(...)
end
f.options.activate = function(actor)
    originalActivate(actor)
    if spawnCalls == 3 then return false, "activation rejected" end
    return true
end
local partial = f.arena:spawn(nil, "blue", 3)
assert(not partial.ok and partial.spawned_count == 2 and partial.activated_count == 1)
assert(f.arena:status().total == 2)
assert(f.arena:stop().ok)

-- A valid returned actor with a warning still belongs to us, but is not full success.
f = fixture()
local spawnWithWarning = f.options.spawnClass
f.options.spawnClass = function(...)
    local actor = spawnWithWarning(...)
    return actor, "finish-spawn readback not fully confirmed"
end
local warningResult = f.arena:spawn(nil, "blue", 1)
assert(not warningResult.ok and warningResult.spawned_count == 1 and warningResult.failure_count == 1
    and warningResult.activated_count == 1)
assert(f.arena:status().owned_records == 1 and #f.synced() == 1)
assert(f.arena:stop().ok and f.arena:status().total == 0, "warning actors must remain available for owned cleanup")

-- Policy rejection must happen before any catalog loading or game generation.
for _, mode in ipairs({ "denied", "missing", "throws", "non_boolean" }) do
    f = fixture()
    if mode == "denied" then f.options.canSpawn = function() return false, "not verified" end
    elseif mode == "missing" then f.options.canSpawn = nil
    elseif mode == "throws" then f.options.canSpawn = function() error("policy unavailable") end
    else f.options.canSpawn = function() return "true" end end
    local selection = f.arena:select("/Catalog/BP_Unverified.BP_Unverified_C", "blue", 1)
    local refused = f.arena:spawn("/Catalog/BP_Unverified.BP_Unverified_C", "blue", 1)
    assert(not selection.ok and not refused.ok and refused.spawned_count == 0, mode)
    assert(stageCount(f, "refresh") == 0 and stageCount(f, "resolve") == 0 and stageCount(f, "spawn") == 0,
        mode .. ": denied choices must not reach refresh, class resolve, or generation")
    assert(#f.actors == 0 and f.arena:status().owned_records == 0)
end

-- Always check the actual selected path even if the catalog has changed independently.
local allowedPath, blockedPath = "/Catalog/BP_Allowed.BP_Allowed_C", "/Catalog/BP_Unverified.BP_Unverified_C"
local checkedPaths = {}
f = fixture({ canSpawn = function(path)
    checkedPaths[#checkedPaths + 1] = path
    return path == allowedPath, "not verified"
end })
assert(f.arena:select(allowedPath, "blue", 1).ok)
f.catalog.selectedPath=blockedPath
local changedSelection = f.arena:spawn()
assert(not changedSelection.ok and changedSelection.spawned_count == 0)
assert(checkedPaths[#checkedPaths] == blockedPath, "policy must inspect the actual catalog selection")
assert(stageCount(f, "refresh") == 0 and stageCount(f, "resolve") == 0 and stageCount(f, "spawn") == 0)
assert(#f.actors == 0)

-- Missing player/world during startup must stop before asset refresh/resolve.
for _, invalidObject in ipairs({ "player", "world" }) do
    f = fixture()
    f[invalidObject].alive = false
    local unavailable = f.arena:spawn("/Catalog/BP_A.BP_A_C", "blue", 1)
    assert(not unavailable.ok and unavailable.spawned_count == 0)
    assert(stageCount(f, "refresh") == 0 and stageCount(f, "resolve") == 0 and stageCount(f, "spawn") == 0,
        invalidObject .. ": no catalog or generation side effects are allowed while loading")
    assert(#f.actors == 0)
end

f = fixture()
function f.catalog:resolveSelected()
    f.trace[#f.trace + 1] = "resolve"
    f.world.alive = false -- The world can disappear during a class-load operation.
    return f.cls
end
assert(not f.arena:spawn().ok and stageCount(f, "resolve") == 1 and stageCount(f, "spawn") == 0)

f = fixture()
f.player.alive = false
assert(not f.arena:spawn().ok and #f.actors == 0)
f.player.alive, f.world.alive = true, false
assert(not f.arena:spawn().ok and #f.actors == 0)
f.world.alive, f.cls.alive = true, false
assert(not f.arena:spawn().ok and #f.actors == 0)

f = fixture()
assert(f.arena:spawn().ok)
f.options.destroy = function() return true end -- engine accepted request, actor is still live
local pending = f.arena:stop()
assert(not pending.ok and pending.remaining_count == 1 and f.arena:status().state == "cleanup_pending")
f.options.destroy = function(actor) actor.alive = false end
assert(f.arena:stop().ok and f.arena:status().total == 0)

-- A failed cleanup must block the next spawn/start, including an eight-unit batch.
f = fixture()
assert(f.arena:spawn(nil, "blue", 4).ok and f.arena:spawn(nil, "red", 4).ok)
f.options.destroy = function() return true end
assert(not f.arena:stop().ok and f.arena:status().state == "cleanup_pending")
local beforeBlockedRefresh, beforeBlockedResolve, beforeBlockedSpawn =
    stageCount(f, "refresh"), stageCount(f, "resolve"), stageCount(f, "spawn")
local blockedSpawn = f.arena:spawn("/Catalog/BP_New.BP_New_C", "blue", 1)
assert(not blockedSpawn.ok and blockedSpawn.spawned_count == 0)
assert(not f.arena:start().ok)
assert(stageCount(f, "refresh") == beforeBlockedRefresh and stageCount(f, "resolve") == beforeBlockedResolve
    and stageCount(f, "spawn") == beforeBlockedSpawn, "pending cleanup must stop before refresh, resolve or generation")
assert(stageCount(f, "relation") == 0 and stageCount(f, "attack") == 0 and stageCount(f, "observe") == 0)
assert(#f.actors == 8 and f.arena:status().owned_records == 8 and f.arena:status().state == "cleanup_pending")
f.options.destroy = function(actor) actor.alive = false end
assert(f.arena:stop().ok)
assert(f.arena:spawn(nil, "blue", 1).ok, "confirmed cleanup should permit the next spawn")

-- Restoration is a separate gate even after every owned actor has been destroyed.
f = fixture()
assert(f.arena:spawn(nil, "blue", 1).ok and f.arena:spawn(nil, "red", 1).ok)
f.options.restore = function() return false end
assert(not f.arena:stop().ok and f.arena:status().state == "restore_pending" and f.arena:status().total == 0)
local restoreBlockedRefresh, restoreBlockedResolve, restoreBlockedSpawn =
    stageCount(f, "refresh"), stageCount(f, "resolve"), stageCount(f, "spawn")
assert(not f.arena:spawn("/Catalog/BP_New.BP_New_C", "red", 1).ok and not f.arena:start().ok)
assert(stageCount(f, "refresh") == restoreBlockedRefresh and stageCount(f, "resolve") == restoreBlockedResolve
    and stageCount(f, "spawn") == restoreBlockedSpawn)
assert(stageCount(f, "relation") == 0 and stageCount(f, "attack") == 0 and stageCount(f, "observe") == 0)
assert(f.arena:status().state == "restore_pending")
f.options.restore = function() return true end
assert(f.arena:stop().ok and f.arena:status().state == "idle")

-- Check all combatants before issuing even the first relationship/attack write.
for _, failure in ipairs({ "hp_zero", "hp_negative", "hp_nil", "hp_nan", "hp_infinite",
    "hp_string", "hp_error", "ai_false", "ai_missing", "ai_string", "ai_error" }) do
    f = fixture()
    assert(f.arena:spawn(nil, "blue", 2).ok and f.arena:spawn(nil, "red", 1).ok)
    local lastCombatant = f.actors[3]
    local inspectedHP = {}
    f.options.hp = function(actor)
        inspectedHP[#inspectedHP + 1] = actor
        if actor ~= lastCombatant then return 400 end
        if failure == "hp_zero" then return 0 end
        if failure == "hp_negative" then return -1 end
        if failure == "hp_nil" then return nil end
        if failure == "hp_nan" then return 0 / 0 end
        if failure == "hp_infinite" then return math.huge end
        if failure == "hp_string" then return "400" end
        if failure == "hp_error" then error("HP read unavailable") end
        return 400
    end
    if failure == "ai_missing" then f.options.combatReady = nil
    else
        f.options.combatReady = function(actor)
            if actor ~= lastCombatant then return true end
            if failure == "ai_false" then return false end
            if failure == "ai_string" then return "true" end
            if failure == "ai_error" then error("combat AI read unavailable") end
            return true
        end
    end
    local refusedBattle = f.arena:start()
    assert(not refusedBattle.ok, failure .. ": unverified combatant must block battle")
    assert(stageCount(f, "relation") == 0 and stageCount(f, "attack") == 0 and stageCount(f, "observe") == 0,
        failure .. ": a healthy earlier combatant must not receive partial battle writes")
    assert(f.arena:status().owned_records == 3, "failed combat preflight must preserve owned cleanup records")
    if failure ~= "ai_missing" then
        assert(inspectedHP[#inspectedHP] == lastCombatant, "the failing last combatant must have been checked")
    end
end

-- UE can keep the UObject valid after the Actor has entered destruction.
f = fixture({
    isDestroying = function(actor) return actor.destroying == true end,
    destroy = function(actor) actor.destroying = true; return true end,
})
assert(f.arena:spawn().ok)
local destroyingActor = f.actors[1]
local destroyingCleanup = f.arena:stop()
assert(destroyingActor.alive == true, "the regression must not rely on IsValid turning false")
assert(destroyingCleanup.ok and destroyingCleanup.destroyed_count == 1 and destroyingCleanup.remaining_count == 0)
local destroyingStatus = f.arena:status()
assert(destroyingStatus.state == "idle" and destroyingStatus.total == 0 and destroyingStatus.owned_records == 0)
assert(#f.synced() == 0, "confirmed destruction must remove the actor from synchronized ownership")

-- A later status poll must finish pending cleanup without issuing Destroy again.
local delayedDestroyCalls = 0
f = fixture({
    isDestroying = function(actor) return actor.destroying == true end,
    destroy = function() delayedDestroyCalls = delayedDestroyCalls + 1; return true end,
})
assert(f.arena:spawn(nil, "red", 1).ok)
local delayedCleanup = f.arena:stop()
assert(not delayedCleanup.ok and delayedCleanup.remaining_count == 1)
local delayedBefore = f.arena:status()
assert(delayedBefore.state == "cleanup_pending" and delayedBefore.total == 1 and delayedBefore.owned_records == 1)
f.actors[1].destroying = true
local delayedAfter = f.arena:status()
assert(f.actors[1].alive == true and delayedDestroyCalls == 1)
assert(delayedAfter.state == "idle" and delayedAfter.total == 0 and delayedAfter.red_count == 0
    and delayedAfter.owned_records == 0 and #f.synced() == 0,
    "status must prune an actor whose destruction becomes observable after stop")

-- A failed/non-boolean destruction query cannot prove that an owned actor is gone.
f = fixture({
    isDestroying = function() error("destruction query unavailable") end,
    destroy = function(actor) actor.destroyRequested = true; return true end,
})
assert(not f.arena:spawn().ok and stageCount(f,'activate')==0,
    'unknown destruction state must prevent activation while retaining ownership')
local unknownDestruction = f.arena:stop()
assert(not unknownDestruction.ok and unknownDestruction.remaining_count == 1 and unknownDestruction.destroyed_count == 0)
local unknownDestructionStatus = f.arena:status()
assert(unknownDestructionStatus.state == "cleanup_pending" and unknownDestructionStatus.total == 0 and unknownDestructionStatus.unreadable_count==1
    and unknownDestructionStatus.owned_records == 1 and #f.synced() == 1,
    "a query exception must retain ownership rather than report cleanup success")
f.options.isDestroying = function() return "true" end
assert(f.arena:status().owned_records == 1, "a non-boolean query result is still unknown")
f.options.isDestroying = function() return true end
assert(f.arena:status().state == "idle" and f.arena:status().total == 0)

f = fixture()
assert(f.arena:spawn().ok)
f.options.restore = function() return false end
assert(not f.arena:stop().ok and f.arena:status().state == "restore_pending")
f.options.restore = function() return true end
assert(f.arena:stop().ok)

f = fixture()
assert(f.arena:spawn().ok)
local originalValid = f.options.valid
f.options.valid = function(object)
    if object == f.actors[1] then error("cannot read validity") end
    return originalValid(object)
end
assert(f.arena:status().unreadable_count == 1)
assert(not f.arena:stop().ok and f.arena:status().owned_records == 1, "unknown validity must retain ownership")
f.options.valid = originalValid
assert(f.arena:stop().ok)

f = fixture()
assert(f.arena:spawn().ok)
f.options.spawnClass = function() return f.actors[1] end
assert(not f.arena:spawn().ok and f.arena:status().total == 1, "duplicate actor must not gain second team/ownership")

f = fixture()
assert(f.arena:spawn(nil, "neutral", 1).ok)
assert(f.arena:status().neutral_count == 1 and not f.arena:start().ok)
assert(f.arena:spawn(nil, "blue", 1).ok and f.arena:spawn(nil, "red", 1).ok)
assert(f.arena:start().ok)
local neutralActor = f.actors[1]
for _, event in ipairs(f.trace) do
    if type(event) == "table" and event[1] == "attack" then assert(event[2] ~= neutralActor and event[3] ~= neutralActor) end
end
-- Companions follow the player: activation is told their team, they are counted apart,
-- a stop keeps them, and only their own clear removes them.
local c=fixture()
local activatedTeams={}
c.options.activate=function(actor,path,team) activatedTeams[#activatedTeams+1]=team;return true end
assert(c.arena:spawn('/Catalog/BP_Test.BP_Test_C','companion',2).ok)
assert(c.arena:spawn('/Catalog/BP_Test.BP_Test_C','blue',1).ok)
assert(activatedTeams[1]=='companion' and activatedTeams[2]=='companion' and activatedTeams[3]=='blue')
local cs=c.arena:status()
assert(cs.companion_count==2 and cs.companion_owned==2 and cs.blue_count==1 and cs.neutral_count==0 and cs.total==1)
local near=c.transforms[1].Translation
assert(math.abs(near.X)<=200 and math.abs(near.Y)==300,'companions appear beside the player')
local stopped=c.arena:stop()
assert(stopped.ok and stopped.remaining_count==0 and c.arena:status().state=='idle','stop finishes without waiting for companions')
assert(c.actors[1].alive and c.actors[2].alive and not c.actors[3].alive and c.arena:status().companion_count==2)
local dismissed=c.arena:clearCompanions()
assert(dismissed.ok and dismissed.destroyed_count==2 and not c.actors[1].alive and c.arena:status().companion_owned==0)

-- A batch of 50: allowed, every slot distinct, laid out in rows of five within about 33 m ahead and
-- 16 m to the side; a single no-team unit still appears straight ahead.
local big=fixture({maxUnits=0})
local bigResult=big.arena:spawn(nil,'blue',50)
assert(bigResult.ok and bigResult.spawned_count==50 and big.arena:status().blue_count==50,bigResult.message)
local seenSlots={}
for _,transform in ipairs(big.transforms)do
    local p=transform.Translation
    local key=p.X..','..p.Y
    assert(not seenSlots[key],'50 slots must be distinct');seenSlots[key]=true
    assert(p.X>=600 and p.X<=600+9*300 and p.Y<=-360 and p.Y>=-(360+4*300),'blue rows of five on the left: '..key)
end
assert(not big.arena:spawn(nil,'red',101).ok,'more than 100 in one summon is refused')
local solo=fixture()
assert(solo.arena:spawn(nil,'neutral',1).ok and solo.transforms[1].Translation.Y==0,'one no-team unit straight ahead')

-- Safety net behind combat_lock.lua: every second a unit found out of combat (it walks home after a round)
-- is sent at its target again; units in combat are never forced. A unit whose target died goes for the
-- least attacked enemy.
do
    local t,combat,engaged=200,{},{}
    local r=fixture({now=function()return t end,
        inCombat=function(actor)local c=combat[actor]~=false;return c,c and 'AI.State.Combat' or 'AI.State.Idle' end,
        engage=function(actor,target)engaged[#engaged+1]={actor,target};return true,'AI.State.Combat' end})
    assert(r.arena:spawn(nil,'blue',3).ok and r.arena:spawn(nil,'red',2).ok and r.arena:start().ok)
    local b1,b2,b3,r1,r2=r.actors[1],r.actors[2],r.actors[3],r.actors[4],r.actors[5]
    r.arena:tickReinforcements()
    assert(#engaged==0,'units in combat are left alone')
    combat[b2]=false
    t=200.5;r.arena:tickReinforcements()
    assert(#engaged==0,'the safety net looks once a second')
    t=201;r.arena:tickReinforcements()
    assert(#engaged==1 and engaged[1][1]==b2 and engaged[1][2]==r2,'b2 is sent back at its own target (round robin gave it r2)')
    t=201.5;r.arena:tickReinforcements()
    assert(#engaged==1)
    t=202;r.arena:tickReinforcements()
    assert(#engaged==2 and engaged[2][1]==b2)
    combat[b2]=nil;t=206;r.arena:tickReinforcements()
    assert(#engaged==2,'back in combat: not forced again')
    -- r1 dies: b1 and b3 (both sent at r1) take the least attacked enemy, which is r2.
    r1.hp=0;t=207
    local attacks=stageCount(r,'attack')
    r.arena:tickReinforcements()
    assert(stageCount(r,'attack')==attacks+2,'both attackers of the fallen enemy get a new target')
    local last=r.trace[#r.trace]
    assert(last[1]=='attack' and last[3]==r2)
    -- Instant send-back by key: the unit goes at its live target; unknown keys, dead targets, the
    -- stopped arena are refused.
    local before=#engaged
    assert(r.arena:reengage(tostring(b2)) and #engaged==before+1 and engaged[#engaged][1]==b2 and engaged[#engaged][2]==r2)
    assert(not r.arena:reengage('nobody') and not r.arena:reengage(nil))
    r2.hp=0;assert(not r.arena:reengage(tostring(b2)),'its target is down')
    assert(r.arena:stop().ok and not r.arena:reengage(tostring(b1)),'no fight, no send-back')
end

-- Battle clock in game seconds: runs once both sides stand after the start, stops when one side has
-- nobody alive or unreadable, starts over when the beaten side gets new units, and stop clears it.
local now=100
local k=fixture({now=function()return now end})
assert(k.arena:status().battle_clock=='' and k.arena:status().battle_seconds==0,'no clock before a fight')
assert(k.arena:spawn(nil,'blue',1).ok and k.arena:spawn(nil,'red',2).ok)
now=103;assert(k.arena:status().battle_clock=='','summoning alone does not start the clock')
assert(k.arena:start().ok)
now=105;local ks=k.arena:status()
assert(ks.battle_clock=='running' and ks.battle_seconds==0,'the clock starts at the first status after the start')
now=110.5;assert(k.arena:status().battle_seconds==5.5)
k.actors[2].hp=0;now=112;assert(k.arena:status().battle_clock=='running','one red still stands')
k.options.valid=function(object)
    if object==k.actors[3] then error('unreadable') end
    return object~=nil and object.alive==true
end
k.actors[3].hp=0;now=114
assert(k.arena:status().battle_clock=='running','an unreadable unit does not end the fight')
k.options.valid=function(object)return object~=nil and object.alive==true end
now=117;ks=k.arena:status()
assert(ks.battle_clock=='ended' and ks.battle_seconds==12,'red wiped out at 117, 12 s after 105')
now=130;assert(k.arena:status().battle_seconds==12,'an ended fight keeps its time')
assert(k.arena:spawn(nil,'red',1).ok)
now=131;ks=k.arena:status()
assert(ks.battle_clock=='running' and ks.battle_seconds==0,'new units on the beaten side start a new fight')
assert(k.arena:stop().ok and k.arena:status().battle_clock=='','stop clears the clock')
local noClock=fixture()
assert(noClock.arena:spawn(nil,'blue',1).ok and noClock.arena:spawn(nil,'red',1).ok and noClock.arena:start().ok)
assert(noClock.arena:status().battle_clock=='','without a game clock nothing is timed')
print("arena_controller: PASS (spawn policy, loading gate, pending-cleanup gate, combat preflight, warning ownership, spacing, teams, caps, partial failures, cleanup retries, deferred destruction, unknown readbacks)")

local gated=fixture({setRelation=function()return false end})
assert(gated.arena:spawn(nil,'blue',1).ok and gated.arena:spawn(nil,'red',1).ok)
assert(not gated.arena:start().ok)
for _,event in ipairs(gated.trace)do assert(type(event)~='table' or event[1]~='attack','unverified factions must not attack')end
print('bvb faction gate: PASS')
