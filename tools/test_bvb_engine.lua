package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Engine=require('bvb_engine')
local root=assert(arg[1]);os.remove(root..'/bvb-hold.tsv')
local game,cycle='Normal',0
local called={}
local function setting(name)return function()called[name]=true;return {ok=true}end end
local o={path=root,log=function()end,arena={members=function()return {}end},
    stats={status=function()return {mode='game'}end},levels={picks={},status=function()return {mode='HOME'}end},
    difficulty={status=function()return {game=game,level='HARD'}end},
    immortal={status=function()return {blue=false,red=false}end},
    spectator={status=function()return {enabled_requested=true}end},cycle=function()return cycle end,
    hp=function()return 100 end,maxHP=function()return 100 end,now=function()return 0 end,
    player=function()return nil end,world=function()return nil end,canSpawn=function()return true end}
local d=Engine.new(o)
assert(not d:beforeSpawn('/A.B_C','blue'),'game must be Hard')
game='Hard';cycle=1;assert(not d:beforeSpawn('/A.B_C','blue'),'NG+ must be rejected')
cycle=0;o.levels.picks.X=15;assert(not d:beforeSpawn('/A.B_C','blue'),'manual level picks must be rejected')
o.levels.picks={};assert(d:beforeSpawn('/A.B_C','blue'))
assert(not d:beforeSpawn('/A.B_C','neutral'),'solo enemies are outside the match')
o.stats.status=function()return {mode='custom'}end;o.stats.setMode=setting('native')
o.immortal.status=function()return {blue=true,red=true}end;o.immortal.set=function(_,team,value)assert(value=='OFF');called[team]=true;return {ok=true}end
assert(d:beforeSpawn('/A.B_C','red'));assert(called.native and called.blue and called.red)
local spectatorState={enabled_requested=true,player_can_be_hatred_readback=false,pending_flags=0,pending_relations=0}
o.spectator.status=function()return spectatorState end
o.spectator.setEnabled=function(_,value)
    spectatorState.enabled_requested=value
    spectatorState.ok=true
    return spectatorState
end
assert(d:setPlayerAggro(true).ok and d:status().bvb_player_aggro)
assert(not d:beforeSpawn('/A.B_C','neutral'),'wait for game readback')
spectatorState.player_can_be_hatred_readback=true
spectatorState.pending_relations=1
assert(not d:beforeSpawn('/A.B_C','neutral'),'wait for relation restoration')
spectatorState.pending_relations=0
assert(d:beforeSpawn('/A.B_C','neutral') and d:spawned({},'/A.B_C','neutral'))
assert(#d.roster==0 and not spectatorState.enabled_requested,'opponents stay out of the frozen filming lineup')
assert(d:beforeSpawn('/A.B_C','blue') and not spectatorState.enabled_requested,'spawning must respect the user choice')
assert(d:setPlayerAggro(false).ok and spectatorState.enabled_requested and not d:status().bvb_player_aggro)
assert(not d:beforeSpawn('/A.B_C','neutral'))
print('bvb_engine: PASS (native rules, player aggro round trip, restoration gates and challenge opponents)')
