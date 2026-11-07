-- Checks addon code against the Forever client's own API documentation
-- (Blizzard_APIDocumentationGenerated from Gethe/wow-ui-source, `forever` branch):
--   * every RegisterEvent/RegisterUnitEvent("NAME") is a real event
--   * every C_Namespace.Function used exists
-- The doc files are only read as text, never executed.
-- Usage: lua check-api.lua <docs dir> <file.lua>...
local docsDir = assert(arg[1], "usage: check-api.lua <docs dir> <files...>")

local events, functions, namespaces = {}, {}, {}

local list = assert(io.popen('ls "' .. docsDir .. '"/*.lua'))
for path in list:lines() do
    local fh = assert(io.open(path))
    local text = fh:read("*a")
    fh:close()
    local ns = text:match('Namespace = "([%w_]+)"')
    if ns then
        namespaces[ns] = true
    end
    for name in text:gmatch('Name = "([%w_]+)",%s*Type = "Function"') do
        functions[(ns and ns .. "." or "") .. name] = true
    end
    for ev in text:gmatch('LiteralName = "([%u%d_]+)"') do
        events[ev] = true
    end
end
list:close()
assert(next(events), "no API docs found in " .. docsDir .. " (run `just setup`)")

local problems = 0
local function report(file, n, msg)
    problems = problems + 1
    print(("%s:%d: %s"):format(file, n, msg))
end

for i = 2, #arg do
    local file = arg[i]
    local n = 0
    for line in io.lines(file) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "") -- drop comments (good enough here)
        for ev in code:gmatch('Register%a*Event%(%s*"([%u%d_]+)"') do
            if not events[ev] then
                report(file, n, "unknown event " .. ev)
            end
        end
        for ns, fn in code:gmatch("(C_%w+)%.([%a_][%w_]*)") do
            if not namespaces[ns] then
                report(file, n, "unknown namespace " .. ns)
            elseif not functions[ns .. "." .. fn] then
                report(file, n, "unknown function " .. ns .. "." .. fn)
            end
        end
    end
end

if problems > 0 then
    print(problems .. " API problem(s)")
    os.exit(1)
end
print("forever API: ok")
