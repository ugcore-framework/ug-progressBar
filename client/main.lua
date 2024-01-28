local Action = {
    name = '',
    duration = 0,
    label = '',
    useWhileDead = false,
    canCancel = true,
    disarm = true,
    controlDisables = {
        disableMovement = false,
        disableCarMovement = false,
        disableMouse = false,
        disableCombat = false
    },
    animation = {
        animDict = nil,
        anim = nil,
        flags = 0,
        task = nil
    },
    prop = {
        model = nil,
        bone = nil,
        coords = vector3(0.0, 0.0, 0.0),
        rotation = vector3(0.0, 0.0, 0.0)
    },
    propTwo = {
        model = nil,
        bone = nil,
        coords = vec3(0.0, 0.0, 0.0),
        rotation = vec3(0.0, 0.0, 0.0)
    }
}

local isDoingAction = false
local wasCancelled = false
local propNet = nil
local propTwoNet = nil
local isAnim = false
local isProp = false
local isPropTwo = false

local controls = {
    disableMouse = { 1, 2, 106 },
    disableMovement = { 30, 31, 36, 21, 75 },
    disableCarMovement = { 63, 64, 71, 72 },
    disableCombat = { 24, 25, 37, 47, 58, 140, 141, 142, 143, 263, 264, 257 }
}

local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(5)
    end
end

local function LoadModel(model)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(5)
    end
end

local function CreateAttachedProp(prop, ped)
    LoadModel(prop.model)
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0)
    local propEntity = CreateObject(GetHashKey(prop.model), coords.x, coords.y, coords.z, true, true, true)
    local netId = ObjToNet(propEntity)
    SetNetworkIdExistsOnAllMachines(netId, true)
    NetworkUseHighPrecisionBlending(netId, true)
    SetNetworkIdCanMigrate(netId, false)
    local boneIndex = GetPedBoneIndex(ped, prop.bone or 60309)
    AttachEntityToEntity(
        propEntity, ped, boneIndex,
        prop.coords.x, prop.coords.y, prop.coords.z,
        prop.rotation.x, prop.rotation.y, prop.rotation.z,
        true, true, false, true, 0, true
    )
    return netId
end

local function DisableControls()
    CreateThread(function()
        while isDoingAction do
            for disableType, isEnabled in pairs(Action.controlDisables) do
                if isEnabled and controls[disableType] then
                    for _, control in ipairs(controls[disableType]) do
                        DisableControlAction(0, control, true)
                    end
                end
            end
            if Action.controlDisables.disableCombat then
                DisablePlayerFiring(PlayerId(), true)
            end
            Wait(0)
        end
    end)
end

local function StartActions()
    local ped = PlayerPedId()
    if isDoingAction then
        if not isAnim and Action.animation then
            if Action.animation.task then
                TaskStartScenarioInPlace(ped, Action.animation.task, 0, true)
            else
                local anim = Action.animation
                if anim.animDict and anim.anim and DoesEntityExist(ped) and not IsEntityDead(ped) then
                    LoadAnimDict(anim.animDict)
                    TaskPlayAnim(ped, anim.animDict, anim.anim, 3.0, 3.0, -1, anim.flags or 1, 0, false, false, false)
                end
            end
            isAnim = true
        end
        if not isProp and Action.prop and Action.prop.model then
            propNet = CreateAttachedProp(Action.prop, ped)
            isProp = true
        end
        if not isPropTwo and Action.propTwo and Action.propTwo.model then
            propTwoNet = CreateAttachedProp(Action.propTwo, ped)
            isPropTwo = true
        end
        DisableControls()
    end
end

local function StartProgressBar(action, onStart, onTick, onFinish)
    local playerPed = PlayerPedId()
    local isPlayerDead = IsEntityDead(playerPed)
    if (not isPlayerDead or action.useWhileDead) and not isDoingAction then
        isDoingAction = true
        Action = action
        SendNUIMessage({
            action = 'progress',
            duration = action.duration,
            label = action.label
        })
        StartActions()
        CreateThread(function()
            if onStart then onStart() end
            while isDoingAction do
                Wait(1)
                if onTick then onTick() end
                if IsControlJustPressed(0, 200) and action.canCancel then
                    TriggerEvent('ug-progressBar:Cancel')
                    wasCancelled = true
                    break
                end
                if IsEntityDead(playerPed) and not action.useWhileDead then
                    TriggerEvent('ug-progressBar:Cancel')
                    wasCancelled = true
                    break
                end
            end
            if onFinish then onFinish(wasCancelled) end
            isDoingAction = false
        end)
    end
end

local function ActionCleanup()
    local ped = PlayerPedId()
    if Action.animation then
        if Action.animation.task or (Action.animation.animDict and Action.animation.anim) then
            StopAnimTask(ped, Action.animation.animDict, Action.animation.anim, 1.0)
            ClearPedSecondaryTask(ped)
        else
            ClearPedTasks(ped)
        end
    end
    if propNet then
        DetachEntity(NetToObj(propNet), true, true)
        DeleteObject(NetToObj(propNet))
    end
    if propTwoNet then
        DetachEntity(NetToObj(propTwoNet), true, true)
        DeleteObject(NetToObj(propTwoNet))
    end
    propNet = nil
    propTwoNet = nil
    isDoingAction = false
    wasCancelled = false
    isAnim = false
    isProp = false
    isPropTwo = false
end

RegisterNetEvent('ug-progressBar:ToggleBusyness', function (bool)
    isDoingAction = bool
end)

RegisterNetEvent('ug-progressBar:CreateProgressBar', function (action, finish)
    StartProgressBar(action, nil, nil, finish)
end)

RegisterNetEvent('ug-progressBar:CreateProgressBarWithStartEvent', function (action, start, finish)
    StartProgressBar(action, start, nil, finish)
end)

RegisterNetEvent('ug-progressBar:CreateProgressBarWithTickEvent', function (action, tick, finish)
    StartProgressBar(action, nil, tick, finish)
end)

RegisterNetEvent('ug-progressBar:CreateProgressBarWithStartAndTickEvent', function (action, start, tick, finish)
    StartProgressBar(action, start, tick, finish)
end)

RegisterNetEvent('ug-progressBar:Cancel', function ()
    ActionCleanup()
    SendNUIMessage({
        action = 'cancel'
    })
end)

RegisterNUICallback('FinishAction', function (data, cb)
    ActionCleanup()
    cb('ok')
end)

RegisterNetEvent('ug-progressBar:ToggleBusyness', function (bool)
    isDoingAction = bool
end)

RegisterNetEvent('ug-progressBar:CreateProgressBar', function (action, finish)
    StartProgressBar(action, nil, nil, finish)
end)

RegisterNetEvent('ug-progressBar:CreateProgressBarWithStartEvent', function (action, start, finish)
    StartProgressBar(action, start, nil, finish)
end)

RegisterNetEvent('ug-progressBar:CreateProgressBarWithTickEvent', function (action, tick, finish)
    StartProgressBar(action, nil, tick, finish)
end)

local function CreateProgressBar(action, finish)
    StartProgressBar(action, nil, nil, finish)
end
exports('CreateProgressBar', CreateProgressBar)

local function CreateProgressBarWithStartEvent(action, start, finish)
    StartProgressBar(action, start, nil, finish)
end
exports('CreateProgressBarWithStartEvent', CreateProgressBarWithStartEvent)

local function CreateProgressBarWithTickEvent(action, tick, finish)
    StartProgressBar(action, nil, tick, finish)
end
exports('CreateProgressBarWithTickEvent', CreateProgressBarWithTickEvent)

local function CreateProgressBarWithStartAndTickEvent(action, start, tick, finish)
    StartProgressBar(action, start, tick, finish)
end
exports('CreateProgressBarWithStartAndTickEvent', CreateProgressBarWithStartAndTickEvent)

local function IsBusy()
    return isDoingAction
end
exports('IsBusy', IsBusy)