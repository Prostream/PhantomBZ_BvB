package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local updates,creates,removed={},0,0
package.loaded.ue_observe={valid=function(a)return a and a.valid end,key=function(a)return a and a.valid and a.key end}
package.loaded.arena_hud_widget={new=function()return {
    create=function(_,u)creates=creates+1;return {widget={valid=true,key='w'..creates}}end,
    update=function(_,record,unit,hp,maximum,title,row)updates[unit.team]={hp=hp,max=maximum,title=title,row=row};return true end,
    remove=function()removed=removed+1;return true end,syncNative=function()end}end}
local HUD=require('bvb_team_hud');local h=HUD.new({})
local a={valid=true,key='a'};local b={valid=true,key='b'}
local d={roster={{actor=a,team='blue',hp=100,path='/A.A_C'},{actor=b,team='blue',hp=50,path='/B.B_C'}},
    totals={blue={hp=150,max=200,alive=2,count=2,unknown=0},red={hp=0,max=0,alive=0,count=0,unknown=0}}}
h:sync(d);assert(creates==1 and updates.blue.hp==150 and updates.blue.max==200 and updates.blue.row==1)
a.valid=false;d.roster[1].hp=0;d.totals.blue.hp=50;d.totals.blue.alive=1;h:sync(d)
assert(creates==2 and removed==1 and updates.blue.max==200,'dead member stays in denominator')
d.totals.blue.unknown=1;h:sync(d);assert(updates.blue.title:find('读数待确认',1,true))
h:clear();assert(removed==2)
print('bvb_team_hud: PASS (one team bar, fixed death denominator, representative replacement, unknowns, cleanup)')
