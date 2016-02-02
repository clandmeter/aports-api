local sqlite    = require("lsqlite3")
local inspect   = require("inspect")

local aports    = class("aports")

function aports:initialize(conf)
    self.checksum = {}
    self.conf = conf
    self.db = sqlite.open(conf.db.path)
    self:createTables()
    self.db:exec("PRAGMA foreign_keys = ON")
end

--- helpers

function aports:begins(str, prefix)
    return str:sub(1,#prefix)==prefix
end

function aports:split(d,s)
    local r = {}
    for i in s:gmatch(d) do table.insert(r,i) end
    return r
end

function aports:mergeTables(...)
    local r = {}
    for k,v in ipairs({...}) do
        if type(v) == "table" then
            for k,v in pairs(v) do
                r[k] = v
            end
        end
    end
    return r
end

function aports:log(msg)
    if self.conf.logging then
        if self.conf.logging == "syslog" then
            os.execute("logger "..msg)
        else
            print(msg)
        end
    end
end

function aports:fileExists(path)
    local f = io.open(path, "r")
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

-- keys used in alpine linux repository index
function aports:indexFormat(k)
    local f = {
        P = "name",
        V = "version",
        T = "description",
        U = "url",
        L = "license",
        A = "arch",
        D = "depends",
        C = "checksum",
        S = "size",
        I = "installed_size",
        p = "provides",
        i = "install_if",
        o = "origin",
        m = "maintainer",
        t = "build_time",
        c = "commit",
    }
    return k and f[k] or f
end

function aports:createTables()
    local packages = [[ create table if not exists 'packages' (
        'id' INTEGER primary key,
        'name' TEXT,
        'version' TEXT,
        'description' TEXT,
        'url' TEXT,
        'license' TEXT,
        'arch' TEXT,
        'branch' TEXT,
        'repo' TEXT,
        'checksum' TEXT,
        'size' INTEGER,
        'installed_size' INTEGER,
        'origin' TEXT,
        'maintainer' INTEGER,
        'build_time' INTEGER,
        'commit' TEXT
    ) ]]
    self.db:exec(packages)
    self.db:exec("create index if not exists 'packages_name' on 'packages' (name)")
    self.db:exec("create index if not exists 'packages_maintainer' on 'packages' (maintainer)")
    local files = [[ create table if not exists 'files' (
        'branch' TEXT,
        'file' TEXT,
        'path' TEXT,
        'pid' INTEGER REFERENCES packages(id) on delete cascade
    )]]
    self.db:exec(files)
    self.db:exec("create index if not exists 'files_file' on 'files' (file)")
    self.db:exec("create index if not exists 'files_pid' on 'files' (pid)")
    local field = [[ create table if not exists '%s' (
        'name' TEXT,
        'version' TEXT,
        'operator' TEXT,
        'pid' INTEGER REFERENCES packages(id) on delete cascade
    )]]
    for _,v in pairs(self.conf.db.fields) do
        self.db:exec(string.format(field,v))
        self.db:exec(string.format("create index if not exists '%s_name' on '%s' (name)", v, v))
        self.db:exec(string.format("create index if not exists '%s_pid' on '%s' (pid)", v, v))
    end
    local maintainer = [[ create table if not exists maintainer (
        'id' INTEGER primary key,
        'name' TEXT,
        'email' TEXT
    ) ]]
    self.db:exec(maintainer)
    self.db:exec("create index if not exists 'maintainer_name' on maintainer (name)")
end

function aports:getIndex(branch, repo, arch)
    local r,i = {},{}
    local index = string.format("%s/%s/%s/%s/APKINDEX.tar.gz",
        self.conf.mirror, branch, repo, arch)
    local f = io.popen(string.format("tar -Ozx -f '%s' APKINDEX", index))
    for line in f:lines() do
        if (line ~= "") then
            local k,v = line:match("^(%a):(.*)")
            local key = self:indexFormat(k)
            r[key] = k:match("^[Dpi]$") and self:split("%S+", v) or v
        else
            local nv = string.format("%s-%s", r.name, r.version)
            r.repo = repo
            r.branch = branch
            i[nv] = r
            r = {}
        end
    end
    f:close()
    return i
end

function aports:getChanges(branch, repo, arch)
    local del = {}
    local add = self:getIndex(branch, repo, arch)
    local sql = [[SELECT branch, repo, arch, name,version FROM 'packages'
        WHERE branch = ?
        AND repo = ?
        AND arch = ?
    ]]
    local stmt = self.db:prepare(sql)
    stmt:bind_values(branch,repo,arch)
    for r in stmt:nrows() do
        local nv = string.format("%s-%s", r.name, r.version)
        if add[nv] then
            add[nv] = nil
        else
            del[nv] = r
        end
    end
    return add,del
end

function aports:addPackages(branch, add)
    for _,pkg in pairs(add) do
        local apk = string.format("%s/%s/%s/%s/%s-%s.apk",
            self.conf.mirror, branch, pkg.repo, pkg.arch, pkg.name, pkg.version)
        if self:fileExists(apk) then
            self:log(string.format("Adding: %s/%s/%s/%s-%s", branch, pkg.repo, pkg.arch, pkg.name, pkg.version))
            pkg.maintainer = self:addMaintainer(pkg.maintainer)
            local pid = self:addHeader(pkg)
            self:addFields(branch,pid,pkg)
            self:addFiles(branch,pid,apk)
        else
            self:log(string.format("Could not find pkg: %s/%s/%s/%s-%s", branch, pkg.repo, pkg.arch, pkg.name, pkg.version))
        end
    end
end

function aports:addHeader(pkg)
    local sql = [[ insert into 'packages' ("name", "version", "description", "url",
        "license", "arch", "branch", "repo", "checksum", "size", "installed_size", "origin",
        "maintainer", "build_time", "commit") values(:name, :version, :description,
        :url, :license, :arch, :branch, :repo, :checksum, :size, :installed_size, :origin,
        :maintainer, :build_time, :commit)]]
    local stmt = self.db:prepare(string.format(sql))
    stmt:bind_names(pkg)
    stmt:step()
    local pid = stmt:last_insert_rowid()
    stmt:finalize()
    return pid
end

function aports:formatMaintainer(maintainer)
    if maintainer then
        local r = {}
        maintainer = maintainer:match("^%s*(.-)%s*$")
        local name,email = maintainer:match("(.*)(<.*>)")
        r.email = email:match("[A-Za-z0-9%.%%%+%-]+@[A-Za-z0-9%.%%%+%-]+%.%w%w%w?%w?")
        if r.email then
            r.name = name:match("^%s*(.-)%s*$")
            return r
        end
    end
end

function aports:addMaintainer(maintainer)
    local m = self:formatMaintainer(maintainer)
    if m then
        local sql = [[ insert or replace into maintainer ('id', 'name', 'email')
            VALUES ((SELECT id FROM maintainer WHERE name = :name AND email = :email),
            :name, :email) ]]
        local stmt = self.db:prepare(sql)
        stmt:bind_names(m)
        stmt:step()
        local r = stmt:last_insert_rowid()
        stmt:reset()
        stmt:finalize()
        return r
    end
end

function aports:delPackages(branch, del)
    local sql = [[ delete FROM 'packages' WHERE "branch" = :branch
        AND "repo" = :repo AND "arch" = :arch AND "name" = :name
        AND "version" = :version ]]
    local stmt = self.db:prepare(sql)
    self.db:exec("begin transaction")
    for _,pkg in pairs(del) do
        self:log(string.format("Deleting: %s/%s/%s/%s-%s", branch, pkg.repo, pkg.arch, pkg.name, pkg.version))
        stmt:bind_names(pkg)
        stmt:step()
        stmt:reset()
    end
    stmt:finalize()
    self.db:exec("commit")
end

function aports:formatField(v, pid)
    local r = {}
    r.pid = pid
    for _,o in ipairs({">=","<=","><","=",">","<"}) do
        if v:match(o) then
            r.name,r.version = v:match("^(.*)"..o.."(.*)$")
            r.operator = o
            return r
        end
    end
    r.name = v
    return r
end

function aports:addFields(branch, pid, pkg)
    for _,field in ipairs(self.conf.db.fields) do
        local values = pkg[field] or {}
        --insert pkg name as a provides in the table.
        if field == "provides" then table.insert(values, pkg.name) end
        local sql = [[ insert into '%s' ("pid", "name", "version", "operator")
            VALUES (:pid, :name, :version, :operator) ]]
        local stmt = self.db:prepare(string.format(sql, field))
        for _,v in pairs(values) do
            local r = self:formatField(v,pid)
            r.branch = branch
            stmt:bind_names(r)
            stmt:step()
            stmt:reset()
        end
        stmt:finalize()
    end
end

function aports:getFilelist(apk)
    r = {}
    local f = io.popen(string.format("tar ztf '%s'", apk))
    for line in f:lines() do
        if not (line:match("^%.") or line:match("/$")) then
            local path,file = self:formatFile(line)
            table.insert(r, {path=path,file=file})
        end
    end
    f:close()
    return r
end

function aports:addFiles(branch, pid, apk)
    local files = self:getFilelist(apk)
    local sql = [[ insert into 'files' ("pid", "file", "path")
        VALUES (:pid, :file, :path) ]]
    local stmt = self.db:prepare(sql)
    for _,file in pairs(files) do
        file.pid = pid
        file.branch = branch
        stmt:bind_names(file)
        local step = stmt:step()
        stmt:reset()
    end
    stmt:finalize()
end

function aports:formatFile(line)
    local path, file
    if line:match("/") then
        path, file = line:match("(.*/)(.*)")
        if path:match("/$") then path = path:sub(1, -2) end
        return "/"..path,file
    end
    return "/", line
end

function aports:indexChanged(index)
    local h = io.popen("md5sum "..index)
    local r =  h:read("*a")
    h:close()
    if self.checksum[index] == r then
        return false
    end
    self.checksum[index] = r
    return true
end

function aports:update()
    for _,branch in pairs(self.conf.branches) do
        for _,repo in pairs(self.conf.repos) do
            for _,arch in pairs(self.conf.archs) do
                local index = string.format("%s/%s/%s/%s/APKINDEX.tar.gz",
                    self.conf.mirror, branch, repo, arch)
                if self:fileExists(index) and self:indexChanged(index) then
                    self:log(string.format("Updating: %s/%s/%s",branch, repo, arch))
                    local add,del = self:getChanges(branch, repo, arch)
                    self.db:exec("begin transaction")
                    self:addPackages(branch, add)
                    self:delPackages(branch, del)
                    self.db:exec("commit")
                end
            end
        end
    end
    self:log("Update finished.")
end

function aports:getDepends(pid)
    local r = {}
    local pkg = self:getPackage(pid)
    if pkg then
        local sql = [[ SELECT DISTINCT packages.*, maintainer.name as mname, maintainer.email as memail FROM depends
            LEFT JOIN provides ON depends.name = provides.name
            LEFT JOIN packages ON provides.pid = packages.id
            LEFT JOIN maintainer ON packages.maintainer = maintainer.id
            WHERE packages.branch = ? AND packages.arch = ? AND depends.pid = ?
            LIMIT 50 ]]
        local stmt = self.db:prepare(sql)
        stmt:bind_values(pkg.branch, pkg.arch, pid)
        for row in stmt:nrows(sql) do
            table.insert(r,row)
        end
        return r
    end
end

function aports:getProvides(pid)
    local r = {}
    local pkg = self:getPackage(pid)
    if pkg then
        local sql = [[ SELECT DISTINCT packages.*, maintainer.name as mname, maintainer.email as memail FROM provides
            LEFT JOIN depends ON provides.name = depends.name
            LEFT JOIN packages ON depends.pid = packages.id
            LEFT JOIN maintainer ON packages.maintainer = maintainer.id
            WHERE branch = ? AND arch = ? AND provides.pid = ?
            LIMIT 50 ]]
        local stmt = self.db:prepare(sql)
        stmt:bind_values(pkg.branch, pkg.arch, pid)
        for row in stmt:nrows(sql) do
            table.insert(r,row)
        end
        return r
    end
end

function aports:getPackage(pid)
    local sql = [[ SELECT packages.*, maintainer.name as mname, maintainer.email as memail FROM packages
        LEFT JOIN maintainer ON packages.maintainer = maintainer.id
        WHERE packages.id = ? ]]
    local stmt = self.db:prepare(sql)
    stmt:bind_values(pid)
    for row in stmt:nrows(sql) do
        return row
    end
end


function aports:whereQuery(values,tname)
    local r = {}
    for field in pairs(values) do
        tfield = table and string.format("%s.%s",tname, field) or field
        table.insert(r, string.format(" %s GLOB :%s ", tfield, field))
    end
    return next(r) and string.format("WHERE %s", table.concat(r, " AND ")) or ""
end

function aports:getPackages(filter, sort, pager)
    local r = {}
    local bind = self:mergeTables(filter,sort,pager)
    local where = self:whereQuery(filter, "packages")
    local sql = string.format([[
        SELECT packages.*, maintainer.name as mname, maintainer.email as memail FROM packages
        LEFT JOIN maintainer ON packages.maintainer = maintainer.id
        %s ORDER BY %s %s LIMIT :limit OFFSET :offset ]], where, sort.sort, sort.order)
    local stmt = self.db:prepare(sql)
    stmt:bind_names(bind)
    for row in stmt:nrows(sql) do
        table.insert(r, row)
    end
    return r
end

function aports:getFiles(pid)
    local r = {}
    local sql = [[ SELECT file, path FROM files WHERE pid = ? ]]
    local stmt = self.db:prepare(sql)
    stmt:bind_values(pid)
    for row in stmt:nrows(sql) do
        table.insert(r, row)
    end
    return r
end

function aports:getOrigins(pid)
    local r = {}
    local pkg = self:getPackage(pid)
    if pkg then
        local sql = [[ SELECT packages.*, maintainer.name as mname, maintainer.email as memail FROM packages
            LEFT JOIN maintainer ON packages.maintainer = maintainer.id
            WHERE packages.origin = :origin AND branch = :branch AND repo = :repo AND arch = :arch ]]
        local stmt = self.db:prepare(sql)
        stmt:bind_names(pkg)
        for row in stmt:nrows(sql) do
            table.insert(r, row)
        end
        return r
    end
end


return aports
