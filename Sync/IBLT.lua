local _,addon=...
-- Invertible Bloom lookup table for set reconciliation. Each record is fingerprinted by a two-part
-- hash of its canonical form (content and version), so two clients can find
-- exactly which records differ by exchanging a small table of cells instead
-- of their whole libraries. Fingerprints identify versions, not authority.
local I={};addon.SyncIBLT=I
local P=2147483647
I.P=P

-- Deterministic text for any plain value (sorted keys).
function I.Canonical(value)
 local kind=type(value)
 if kind=='nil' then return 'z' end
 if kind=='boolean' then return value and 't' or 'f' end
 if kind=='number' then return 'n'..string.format('%.17g',value)..';' end
 if kind=='string' then return 's'..#value..':'..value end
 assert(kind=='table','unsupported sync value')
 local keys,parts={},{'{'}
 for key in pairs(value) do keys[#keys+1]={I.Canonical(key),key} end
 table.sort(keys,function(a,b) return a[1]<b[1] end)
 for _,key in ipairs(keys) do parts[#parts+1]=key[1];parts[#parts+1]=I.Canonical(value[key[2]]) end
 parts[#parts+1]='}'
 return table.concat(parts)
end
function I.Hash(text,seed)
 local h=seed or 5381
 for n=1,#text do h=(h*33+text:byte(n))%P end
 return h
end
-- Two independent recurrences avoid correlated collisions.
function I.Key(record)
 local text=I.Canonical(record)
 local a,b=5381,7919
 for n=1,#text do
  local c=text:byte(n)
  a=(a*33+c)%P
  b=(b*65599+c)%P
 end
 return {a,b}
end
function I.ID(k) return k[1]..':'..k[2] end
local function Check(k) return I.Hash(I.ID(k),104729) end
local function Positions(k,size)
 local a=k[1]%size+1
 local b=k[2]%size+1
 if b==a then b=b%size+1 end
 local c=Check(k)%size+1
 while c==a or c==b do c=c%size+1 end
 return {a,b,c}
end
function I.New(size)
 assert(size>=3 and size<=256 and size==math.floor(size))
 local out={}
 for n=1,size do out[n]={0,0,0,0} end
 return out
end
function I.Add(cells,k,sign)
 for _,n in ipairs(Positions(k,#cells)) do
  local c=cells[n]
  c[1]=c[1]+sign
  c[2]=(c[2]+sign*k[1])%P
  c[3]=(c[3]+sign*k[2])%P
  c[4]=(c[4]+sign*Check(k))%P
 end
end
function I.Valid(cells,size)
 if type(cells)~='table' or #cells~=size then return false end
 for _,c in ipairs(cells) do
  if type(c)~='table' or #c~=4 then return false end
  for n=1,4 do if type(c[n])~='number' or c[n]~=math.floor(c[n]) or math.abs(c[n])>=P then return false end end
 end
 return true
end
function I.Subtract(a,b)
 if not I.Valid(a,#b) or not I.Valid(b,#a) then return nil end
 local out=I.New(#a)
 for n,c in ipairs(out) do
  c[1]=a[n][1]-b[n][1]
  for j=2,4 do c[j]=(a[n][j]-b[n][j])%P end
 end
 return out
end
-- Peel pure cells. Returns (onlyInA, onlyInB) key lists, or nil if the table
-- is too small for the difference (the caller then retries larger).
function I.Peel(cells)
 if not cells then return nil end
 local positive,negative,seen={},{},{}
 for _=1,#cells*2 do
  local changed=false
  for n,c in ipairs(cells) do
   local sign=c[1]
   if sign==1 or sign==-1 then
    local k={(sign*c[2])%P,(sign*c[3])%P}
    local valid=false
    for _,pos in ipairs(Positions(k,#cells)) do if pos==n then valid=true end end
    if valid and (sign*c[4])%P==Check(k) then
     local id=I.ID(k)
     if seen[id] then return nil end
     seen[id]=true
     local list=sign==1 and positive or negative
     list[#list+1]=k
     I.Add(cells,k,-sign)
     changed=true
    end
   end
  end
  if not changed then
   for _,c in ipairs(cells) do for n=1,4 do if c[n]~=0 then return nil end end end
   return positive,negative
  end
 end
 return nil
end
