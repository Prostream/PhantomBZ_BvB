local Director=dofile('Mods/PhantomGladiator/Scripts/bvb_director.lua')
local root=assert(arg[1]);local serial=0
local function fixture()
    serial=serial+1
    local state={members={},clears=0,spawns=0,world='Map_A',anchor={x=0,y=0,z=100,yaw=0},time=0,rule=true}
    -- Files are unique per test, directory supplied by test runner.
    local prefix=root..'/bvb-lineup.tsv';os.remove(prefix)
    local d
    local options={path=root,valid=function(a)return a and a.valid end,hp=function(a)return a.hp end,maxHP=function(a)return a.max end,
        pose=function(a)return a.p end,anchor=function()return state.anchor end,world=function()return state.world end,
        now=function()return state.time end,rules=function()return state.rule,'wrong difficulty' end,
        hold={recover=function()return true end,apply=function(_,a)a.held=true;return not state.holdFail end,
            release=function()for _,u in ipairs(state.members)do u.actor.held=false end;return not state.releaseFail end},
        members=function()return state.members end,canSpawn=function()return not state.badPath end,
        resolve=function(id)return '/Game/'..id..'.'..id..'_C' end,
        stop=function()
            state.clears=state.clears+1
            if state.clearFail then return {ok=false,message='cleanup pending'} end
            for _,u in ipairs(state.members)do u.actor.valid=false end
            state.members={};return {ok=true}
        end,
        finish=function()state.finished=true end}
    options.spawn=function(path,team,p)
        state.spawns=state.spawns+1
        if state.spawnFail==state.spawns then return {ok=false,spawned_count='unknown',message='uncertain'} end
        local a={valid=true,p=p,hp=100,max=100};state.members[#state.members+1]={actor=a,team=team}
        return {ok=d:spawned(a,path,team),spawned_count=1}
    end
    d=Director.new(options)
    state.add=function(team,x)
        assert(d:beforeSpawn('/Game/B.B_C',team))
        options.spawn('/Game/B.B_C',team,{x=x or 100,y=0,z=100,yaw=0})
        return state.members[#state.members].actor
    end
    return d,state,options
end
local d,s=fixture()
assert(not d:restore(false).ok and s.clears==0,'no plan must not clear current match')
local a=s.add('blue',100);local b=s.add('red',400)
assert(a.held and b.held and d:save().ok)
assert(d:beforeStart() and not a.held)
assert(not d:beforeSpawn('/Game/B.B_C','blue'),'no reinforcements in a recorded match')
a.hp=0;b.hp=35;s.time=12;d:tick()
assert(d.state=='ended' and d.winner=='red' and s.finished)
assert(d.totals.blue.max==100 and d.totals.blue.hp==0 and d.totals.red.hp==35)
assert(d:restore(false).ok and s.clears==1 and #s.members==2)
assert(s.members[1].actor~=a and s.members[1].actor.hp==100 and s.members[1].actor.held)
assert(d.state=='intro','reset never starts fight')
s.clearFail=true;local before=s.spawns
assert(not d:restore(false).ok and s.spawns==before,'cleanup failure must not create another roster')
d,s=fixture();s.add('blue');s.add('red');assert(d:save().ok)
s.world='Map_B';s.anchor={x=1000,y=2000,z=500,yaw=90}
assert(not d:restore(false).ok and s.clears==0,'cross-map reset must be explicit')
assert(d:restore(true).ok)
local p=s.members[1].actor.p
assert(math.abs(p.x-1000)<0.001 and math.abs(p.y-2100)<0.001 and p.z==500 and p.yaw==90)
d,s=fixture();local a=s.add('blue');s.add('red');assert(d:beforeStart())
a.valid=false;d:tick()
assert(d.state=='running' and d.totals.blue.unknown==1 and not d.winner,'missing actor is not observed death')
d,s=fixture();s.add('blue');s.add('red');assert(d:save().ok)
s.spawnFail=s.spawns+2
assert(not d:restore(false).ok and d.state=='error' and #s.members==1,'partial reset stays stopped')
d,s=fixture();s.add('blue');s.add('red');s.releaseFail=true
assert(not d:beforeStart() and d.state=='error','unverified unhold cannot start')
d,s=fixture();s.rule=false
assert(not d:beforeSpawn('/Game/B.B_C','blue') and s.spawns==0)
d,s=fixture();assert(d:preset().ok and #s.members==8 and d.saved)
assert(not d:preset().ok and #s.members==8,'preset cannot duplicate a live roster')
print('bvb_director: PASS (reset transaction, cross-map placement, totals, unknowns, rules, hold, 4v4 preset)')

local function request(text)
    local f=assert(io.open(root..'/bvb-request.tsv','wb'));f:write(text);f:close()
end
local draft='BVBDraft1\t42\nblue\t/Game/A.A_C\nred\t/Game/B.B_C\nblue\t/Game/C.C_C\n'
d,s=fixture();s.add('blue');s.add('red');assert(d:save().ok)
request(draft)
assert(not d:applyRequest('41').ok and s.clears==0,'stale draft must not clear')
s.badPath=true;assert(not d:applyRequest('42').ok and s.clears==0,'validate every class before clear');s.badPath=false
assert(d:applyRequest('42').ok and s.clears==1 and #s.members==3)
assert(d.state=='intro' and d.saved and #d.saved.rows==3)
assert(d.saved.rows[1].path=='/Game/A.A_C' and d.saved.rows[3].team=='blue')
assert(s.members[1].actor.held and s.members[3].actor.p.x>s.members[1].actor.p.x)
assert(d:beforeStart());assert(not d:applyRequest('42').ok and s.clears==1,'live battle cannot be replaced')
d,s=fixture();request('BVBDraft1\t42\nblue\t/Game/A.A_C\n')
assert(not d:applyRequest('42').ok and s.clears==0,'one-sided draft cannot clear')
request(draft);s.clearFail=true;assert(not d:applyRequest('42').ok and s.spawns==0)
d,s=fixture();request(draft);s.spawnFail=2
assert(not d:applyRequest('42').ok and d.state=='error' and #s.members==1 and not d.saved,'partial apply is not saved or started')
print('bvb_editor: PASS (revision, preflight, both teams, no live replacement, cleanup failure, partial spawn, held/saved lineup)')
