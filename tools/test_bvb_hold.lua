local Hold=dofile('Mods/PhantomGladiator/Scripts/bvb_hold.lua')
local root=assert(arg[1]);os.remove(root..'/bvb-hold.tsv')
local a={valid=true,key='1',name='/Test/Unit',dilation=1.25}
local writes=0
local o={path=root,log=function()end,valid=function(v)return v and v.valid end,key=function(v)return v.key end,
    name=function(v)return v.name end,find=function(p)return p==a.name and a or nil end,
    get=function(v)return v.dilation end,set=function(v,n)writes=writes+1;v.dilation=n;return true end}
local h=Hold.new(o);assert(h:apply(a) and a.dilation==0)
local f=assert(io.open(root..'/bvb-hold.tsv'));local data=f:read('*a');f:close();assert(data:find('1.25',1,true))
assert(h:apply(a) and writes==1,'unchanged hold must not rewrite actor every tick')
local reloaded=Hold.new(o);assert(reloaded:recover() and a.dilation==1.25,'reload restores persisted original')
assert(reloaded:apply(a));a.key='2';a.dilation=.5
local nextLoad=Hold.new(o);assert(nextLoad:recover() and a.dilation==.5,'address-reused actor must not be changed')
os.remove(root..'/bvb-hold.tsv');a.dilation=1
local h=Hold.new(o);assert(h:apply(a))
o.set=function()return false end
assert(not h:release(),'failed restore remains pending')
local f=assert(io.open(root..'/bvb-hold.tsv'));assert(f:read('*a'):find('/Test/Unit',1,true));f:close()
print('bvb_hold: PASS (persist-before-write, reload recovery, object identity, failed restore)')
