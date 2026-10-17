-- Human Haste - Configurable 1.1.0
-- Derived from HumanHasteAtNight by SkrappyNPC (MIT; see LICENSE).
local Settings=require('Settings')
local dir=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])'))
local root=assert(dir:match('^(.*[\\/])Scripts[\\/]$'),'Expected Scripts directory')
local config,configError=Settings.load(root..'settings.ini')
local level=config and config.logLevel or Settings.failureLogLevel or 2
local reported={}
local function log(severity,message)
    if level>=severity then print('[HumanHaste] '..message..'\n') end
end
local function failure(key,message)
    if not reported[key] then reported[key]=true;log(2,message) end
end
if not config then log(1,'Settings unavailable: '..tostring(configError));return end
local UEHelpers=require('UEHelpers')
local HUMAN='/Game/_Dawnwalker/Player/Abilities/GA_FastTravelHumanSprint.GA_FastTravelHumanSprint_C'
local VAMP='/Game/_Dawnwalker/Player/Abilities/GA_FastTravelVampireSprint.GA_FastTravelVampireSprint_C'
local PREFIX='/Game/_Dawnwalker/Player/MovementProfiles/'
local PROFILE_NAMES={
    'DA_FastTravelSprintOpenWorld_Human_MovementProfile',
    'DA_FastTravelSprintOpenWorld_MovementProfile_Human_Enhanced'
}
-- Ratio of mean RootSpeedY in vanilla Wolf_Run_Forward and Coen_SprintFastTravel02_F.
-- The packaged vampire blendspace supplies the missing human haste gait (Y=3).
-- This calibrates forward movement to the vanilla wolf curve, before its normal/enhanced profile scale.
local WOLF_TO_HUMAN=1.1892839243706543
local human,vamp,coen=nil,nil,nil
local candidates={human={},vamp={}}
local profiles={}
local active=nil
local generation,pending,attempts=0,false,0
local workerHandle=nil
local discoveryQueued=false
local hookIds={}
local ready=false
local function valid(o)
    local ok,result=pcall(function() return o~=nil and o:IsValid()==true end)
    return ok and result
end
local function same(a,b)
    return valid(a) and valid(b) and a:GetAddress()==b:GetAddress()
end
local function unwrap(p) return p and p:get() end
local function currentPawn()
    local pc=UEHelpers.GetPlayerController()
    return valid(pc) and pc.Pawn or nil
end
local function restoreProfiles()
    for _,p in ipairs(profiles) do
        if valid(p.object) and p.written then
            local cfg=p.object.MovementConfig
            if math.abs(cfg.RootSpeedScale-p.written)<1e-5 then cfg.RootSpeedScale=p.original end
            p.written=nil
        end
    end
    active=nil
end
local function forget()
    generation=generation+1;pending=false;attempts=0;ready=false
    if workerHandle then pcall(CancelDelayedAction,workerHandle);workerHandle=nil end
    pcall(restoreProfiles)
    human,vamp,coen=nil,nil,nil;candidates={human={},vamp={}};profiles={}
end
local function profileRecord(obj)
    for _,p in ipairs(profiles) do if same(obj,p.object) then return p end end
end
local function applySpeed(record,pawn)
    if not same(pawn,coen) or not valid(vamp) or not same(vamp:GetOuter(),pawn) then return end
    if pawn:IsVampire()~=true then restoreProfiles();return end
    -- Ask the original vampire ability: this keeps Effect.WolfBoost.Enhanced selection.
    local wolf=vamp:GetSprintProfile()
    assert(valid(wolf),'Vampire haste profile is unavailable')
    local baseline=wolf.MovementConfig.RootSpeedScale
    assert(type(baseline)=='number' and baseline>0 and baseline<100,'Invalid vampire haste root-speed scale')
    local target=baseline*WOLF_TO_HUMAN*config.hasteSpeedPercent/100
    local cfg=record.object.MovementConfig
    if math.abs(cfg.RootSpeedScale-target)>1e-5 then cfg.RootSpeedScale=target end
    assert(math.abs(cfg.RootSpeedScale-target)<1e-5,'Haste root-speed write did not persist')
    record.written=target;active=record
    if level==4 then log(4,string.format('Vampire haste: %d%%; wolf scale %.4f; human scale %.4f',config.hasteSpeedPercent,baseline,target)) end
end
local function installHook(path,pre,post)
    if hookIds[path] then return true end
    local ok,a,b=pcall(RegisterHook,path,pre,post)
    if ok and type(a)=='number' and type(b)=='number' then hookIds[path]={a,b};return true end
    failure(path,'Hook unavailable: '..path);return false
end
local function movementPre(ctx,profile)
    if not ready then return end
    local ok,err=pcall(function()
        local movement=unwrap(ctx);local p=profileRecord(unwrap(profile))
        if not valid(movement) or not same(movement:GetOwner(),coen) then return end
        if p then applySpeed(p,coen) end
    end)
    if not ok then failure('speed','Speed adjustment unavailable: '..tostring(err)) end
end
local function eventPre(_,actor,eventTag,payload)
    if not ready then return end
    local ok,err=pcall(function()
        local pawn=unwrap(actor)
        if not same(pawn,coen) or pawn:IsVampire()~=true then return end
        local tag=unwrap(eventTag)
        if tag.TagName:ToString()~='Abilities.Shapeshift' then return end
        -- Native SendGameplayEventToActor pre-hook: modify only this player's event.
        tag.TagName=FName('Abilities.MercurialFervour')
        unwrap(payload).EventTag.TagName=FName('Abilities.MercurialFervour')
        if level==4 then log(4,'Redirected vampire haste to the human haste ability') end
    end)
    if not ok then failure('redirect','Haste redirect unavailable: '..tostring(err)) end
end
local function ownInstance(list,pawn)
    for _,ability in ipairs(list) do
        if valid(ability) and same(ability:GetOuter(),pawn) then return ability end
    end
end
local function cdo(path)
    local cls=StaticFindObject(path)
    return valid(cls) and cls:GetCDO() or nil
end
local function hasTag(container,name)
    local found=false
    container.GameplayTags:ForEach(function(_,e)
        if e:get().TagName:ToString()==name then found=true end
    end)
    return found
end
local function initialize()
    local pawn=currentPawn()
    if not valid(pawn) then return false end
    local h,v=ownInstance(candidates.human,pawn),ownInstance(candidates.vamp,pawn)
    if not h or not v then return false end
    local hc,vc=cdo(HUMAN),cdo(VAMP)
    if not valid(hc) or not valid(vc) then return false end
    local found={}
    for _,name in ipairs(PROFILE_NAMES) do
        local p=StaticFindObject(PREFIX..name..'.'..name)
        if not valid(p) then return false end
        local original=p.MovementConfig.RootSpeedScale
        if type(original)~='number' or original<=0 or original>=100 then return false end
        found[#found+1]={object=p,original=original}
    end
    -- Install both required operations before changing ability eligibility.
    if not installHook('/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor',eventPre) then return false end
    if not installHook('/Script/RebelLocomotion.RebelCharacterMovement:PushMovementProfile',movementPre) then return false end
    assert(not hasTag(vc.ActivationBlockedTags,'Player.IsVampire') and hasTag(hc.ActivationBlockedTags,'Player.IsVampire'),'Unexpected haste eligibility contract')
    h.AdditionalForbiddenTags=vc.AdditionalForbiddenTags
    v.AdditionalForbiddenTags=hc.AdditionalForbiddenTags
    h.ActivationBlockedTags=vc.ActivationBlockedTags
    v.ActivationBlockedTags=hc.ActivationBlockedTags
    h.ActivationRequiredTags.GameplayTags:ForEach(function(_,e)
        local t=e:get()
        if t.TagName:ToString()=='CharDev.AnimalSprintUnlock' then t.TagName=FName('Player.Input.MoveFast') end
    end)
    assert(not hasTag(h.ActivationBlockedTags,'Player.IsVampire') and hasTag(v.ActivationBlockedTags,'Player.IsVampire') and not hasTag(h.ActivationRequiredTags,'CharDev.AnimalSprintUnlock'),'Haste eligibility write did not persist')
    human,vamp,coen=h,v,pawn;profiles=found;ready=true
    log(3,'Human haste ready; vampire speed '..config.hasteSpeedPercent..'%')
    return true
end
local wake
local function queue()
    if pending or ready or attempts>=20 then return end
    pending=true;local token=generation
    workerHandle=ExecuteInGameThreadWithDelay(250,function()
        if token~=generation then return end
        pending=false;workerHandle=nil;attempts=attempts+1
        local ok,done=pcall(initialize)
        if ok and done then return end
        if attempts<20 then queue()
        else failure('readiness','Haste setup is not ready; waiting for the next player/load event'..(ok and '' or ': '..tostring(done))) end
    end)
end
wake=function()
    if ready then
        if same(currentPawn(),coen) then return end
        forget()
    end
    if not pending then attempts=0 end
    queue()
end
local function add(kind,obj)
    if not valid(obj) then return end
    -- Notifications run during construction. Only defer here, never inspect owner/properties.
    local list=candidates[kind]
    if #list>=16 then table.remove(list,1) end
    list[#list+1]=obj
    wake()
end
local function discover()
    forget()
    -- One search per class at a lifecycle boundary; retries never repeat global scans.
    candidates.human=FindAllOf('GA_FastTravelHumanSprint_C') or {}
    candidates.vamp=FindAllOf('GA_FastTravelVampireSprint_C') or {}
    wake()
end
local function requestDiscovery()
    if discoveryQueued then return end
    discoveryQueued=true
    ExecuteInGameThread(function() discoveryQueued=false;discover() end)
end
local apiOk,apiError=pcall(function()
    require('dmm_api').subscribe('HumanHasteConfigurable',function(values)
        local accepted,err=Settings.validate(values)
        if not accepted then failure('menu',err);return end
        config=accepted;level=config.logLevel
        if ready and active then
            local ok,why=pcall(function()
                if same(currentPawn(),coen) then applySpeed(active,coen) end
            end)
            if not ok then failure('menu-speed','Could not apply haste speed: '..tostring(why)) end
        end
    end)
end)
if not apiOk then failure('menu-subscribe','Live settings unavailable: '..tostring(apiError)) end
for _,spec in ipairs({{HUMAN,'human'},{VAMP,'vamp'}}) do
    local path,kind=spec[1],spec[2]
    local ok=pcall(NotifyOnNewObject,path,function(obj)
        ExecuteInGameThread(function() add(kind,obj) end)
    end)
    if not ok then failure('notify-'..kind,'Ability construction notification unavailable: '..kind) end
end
pcall(RegisterLoadMapPreHook,forget)
pcall(RegisterLoadMapPostHook,requestDiscovery)
installHook('/Script/Engine.PlayerController:ClientRestart',function() end,requestDiscovery)
installHook('/Script/DogwoodCombat.CombatSubsystem:OnLoadingScreenStateChanged',function() end,function()
    requestDiscovery()
end)
requestDiscovery()
