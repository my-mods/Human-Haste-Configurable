-- Personal configuration: startup reads, then committed menu snapshots.
local M = {}
M.schema = { {key='hasteSpeedPercent', default=100, min=25, max=300}, {key='logLevel', default=2, min=0, max=4} }
function M.validate(values)
    local out={}
    for _,row in ipairs(M.schema) do
        local v=values[row.key]
        if type(v)~='number' or v~=v or v%1~=0 or v<row.min or v>row.max then return nil,'Invalid '..row.key end
        out[row.key]=v
    end
    return out
end
local function read(path)
    local f,e,c=io.open(path,'rb'); if not f then return nil,e,c end
    local s,err=f:read(1048577); f:close()
    if err then return nil,err,-1 end
    s=s or ''
    if #s>1048576 then return nil,'Settings exceed 1 MiB',-1 end
    return s
end
M.read=read
function M.complete(text)
    -- Honor explicit Off even when another setting is malformed.
    local section,seen,value='',0,nil
    for line in (text..'\n'):gmatch('(.-)\r?\n') do
        local clean=line:gsub('^\239\187\191',''):gsub('[;#].*$','')
        local header=clean:match('^%s*%[([^%]]+)%]%s*$')
        if header then section=header
        elseif section=='Settings' then
            local v=clean:match('^%s*logLevel%s*=%s*(.-)%s*$')
            if v then seen=seen+1;value=tonumber(v) end
        end
    end
    M.failureLogLevel=seen==1 and value and value%1==0 and value>=0 and value<=4 and value or 2
    local values,seen,section={}, {}, ''
    local known={}; for _,r in ipairs(M.schema) do known[r.key]=r end
    for line in (text..'\n'):gmatch('(.-)\r?\n') do
        local clean=line:gsub('^\239\187\191',''):gsub('[;#].*$','')
        local header=clean:match('^%s*%[([^%]]+)%]%s*$')
        if header then section=header
        elseif section=='Settings' then
            local k,v=clean:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
            if known[k] then
                if seen[k] then return nil,'Duplicate '..k end
                seen[k]=true; values[k]=tonumber(v)
                local row=known[k];local n=values[k]
                if not n or n~=n or n%1~=0 or n<row.min or n>row.max then return nil,'Invalid '..k end
            end
        end
    end
    local out=text;local nl=text:find('\r\n',1,true) and '\r\n' or '\n'
    for _,row in ipairs(M.schema) do
        if not seen[row.key] then
            if out~='' and out:sub(-1)~='\n' then out=out..nl end
            out=out..'[Settings]'..nl..row.key..' = '..row.default..nl
            values[row.key]=row.default
        end
    end
    return values,nil,out
end
function M.load(path)
    local original,e,c=read(path)
    if not original and c~=2 then return nil,e end
    local values,err,text=M.complete(original or '')
    if not values then return nil,err end
    if text==original then return values end
    local tmp,backup=path..'.haste.tmp',path..'.before-haste-settings'
    for _,p in ipairs({tmp,backup}) do
        local existing,why,code=read(p)
        if existing or code~=2 then return nil,'Recover existing settings transaction: '..p end
    end
    local f,why=io.open(tmp,'wb');if not f then return nil,why end
    local wrote,we=f:write(text);local closed,ce=f:close()
    if not wrote or not closed or read(tmp)~=text then os.remove(tmp);return nil,we or ce or 'Settings verification failed' end
    if read(path)~=original then os.remove(tmp);return nil,'Settings changed during startup' end
    if original then
        local ok,why=os.rename(path,backup);if not ok then os.remove(tmp);return nil,why end
    end
    local ok,why=os.rename(tmp,path)
    if not ok then
        if original then os.rename(backup,path) end
        os.remove(tmp);return nil,why
    end
    if read(path)~=text then return nil,'Settings verification failed; retain backup' end
    return values
end
return M
