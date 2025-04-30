-- Lua Obfuscator Script
-- Usage: lua obfuscator.lua input.lua output.lua

local lfs = require("lfs")

-- Utility functions
local function random_string(length)
    local res = {}
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for i = 1, length do
        res[i] = chars:sub(math.random(#chars), math.random(#chars))
    end
    return table.concat(res)
end

local function base64_encode(data)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r,binary='',x:byte()
        for i=8,1,-1 do r=r..(binary%2^i-binary%2^(i-1)>0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

local function base64_decode(data)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r
    end):gsub('%d%d%d%d%d%d%d%d', function(x)
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- Obfuscation functions

-- Remove comments and unnecessary whitespace
local function remove_comments_and_whitespace(code)
    -- Remove multiline comments --[[ ... ]]
    code = code:gsub("%-%-%[%[.-%]%]", "")
    -- Remove single line comments -- ...
    code = code:gsub("%-%-.-\n", "\n")
    -- Remove leading/trailing whitespace on lines
    code = code:gsub("[ \t]+", " ")
    code = code:gsub("\n%s*\n", "\n")
    return code
end

-- Encode strings literals in base64 and decode at runtime
local function encode_strings(code)
    -- Pattern to find string literals (single or double quotes)
    local pattern = "(['\"])(.-)%1"
    local encoded_strings = {}
    local id = 0
    local function replacer(str)
        id = id + 1
        local encoded = base64_encode(str)
        encoded_strings[id] = encoded
        return string.format("decode_string(%d)", id)
    end
    local new_code = code:gsub(pattern, function(q, s)
        -- Avoid encoding empty strings
        if s == "" then return q..q end
        return replacer(s)
    end)
    return new_code, encoded_strings
end

-- Generate decode_string function and encoded strings table
local function generate_string_decoder(encoded_strings)
    local lines = {}
    table.insert(lines, "local encoded_strings = {")
    for i, v in ipairs(encoded_strings) do
        table.insert(lines, string.format("  [%d] = '%s',", i, v))
    end
    table.insert(lines, "}")
    table.insert(lines, [[
local function base64_decode(data)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r
    end):gsub('%d%d%d%d%d%d%d%d', function(x)
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local function decode_string(id)
    return base64_decode(encoded_strings[id])
end
]])
    return table.concat(lines, "\n")
end

-- Rename variables and functions to random strings
local function rename_identifiers(code)
    -- This is a simple heuristic approach: find local variables and function names and rename them
    local identifiers = {}
    local id_map = {}

    -- Find local variables
    for var in code:gmatch("local%s+([%w_]+)") do
        identifiers[var] = true
    end
    -- Find function definitions
    for func in code:gmatch("function%s+([%w_]+)") do
        identifiers[func] = true
    end
    -- Find function assigned to variables: local var = function(...)
    for func in code:gmatch("local%s+([%w_]+)%s*=%s*function") do
        identifiers[func] = true
    end

    -- Generate random names
    for id in pairs(identifiers) do
        id_map[id] = random_string(8)
    end

    -- Replace identifiers in code
    for orig, newname in pairs(id_map) do
        -- Use word boundaries to avoid partial replacements
        code = code:gsub("(%W)"..orig.."(%W)", "%1"..newname.."%2")
        -- Also replace at start or end of string
        code = code:gsub("^"..orig.."(%W)", newname.."%1")
        code = code:gsub("(%W)"..orig.."$", "%1"..newname)
    end

    return code
end

-- Insert junk/no-op code randomly
local function insert_junk_code(code)
    local junk_statements = {
        "local _junk = 0",
        "local _junk = _junk + 1",
        "if false then print('junk') end",
        "repeat until true",
        "local function _junk_func() return 42 end",
        "local _junk_table = {1,2,3}",
    }
    local lines = {}
    for line in code:gmatch("[^\r\n]+") do
        table.insert(lines, line)
        if math.random() < 0.1 then
            table.insert(lines, junk_statements[math.random(#junk_statements)])
        end
    end
    return table.concat(lines, "\n")
end

-- Encode numeric literals by adding zero or multiplying by 1
local function encode_numeric_literals(code)
    -- Replace numeric literals with expressions that evaluate to the same number
    code = code:gsub("(%d+)", function(num)
        local n = tonumber(num)
        if n == nil then return num end
        if n % 2 == 0 then
            return "("..num.." / 2) * 2"
        else
            return "("..num.." + 1) - 1"
        end
    end)
    return code
end

-- Control flow flattening (simple version)
local function control_flow_flattening(code)
    -- This is a complex technique; here we do a simple simulation by wrapping code in a while loop with a state machine
    local flattened = {}
    table.insert(flattened, "local state = 1")
    table.insert(flattened, "while true do")
    table.insert(flattened, "  if state == 1 then")
    table.insert(flattened, "    -- original code start")
    -- Indent original code lines
    for line in code:gmatch("[^\r\n]+") do
        table.insert(flattened, "    "..line)
    end
    table.insert(flattened, "    break")
    table.insert(flattened, "  end")
    table.insert(flattened, "end")
    return table.concat(flattened, "\n")
end

-- Main function
local function obfuscate(input_path, output_path)
    local file = io.open(input_path, "r")
    if not file then
        print("Error: Cannot open input file: "..input_path)
        return
    end
    local code = file:read("*all")
    file:close()

    math.randomseed(os.time())

    -- Step 1: Remove comments and whitespace
    code = remove_comments_and_whitespace(code)

    -- Step 2: Encode strings
    local encoded_code, encoded_strings = encode_strings(code)

    -- Step 3: Rename identifiers
    encoded_code = rename_identifiers(encoded_code)

    -- Step 4: Encode numeric literals
    encoded_code = encode_numeric_literals(encoded_code)

    -- Step 5: Insert junk code
    encoded_code = insert_junk_code(encoded_code)

    -- Step 6: Control flow flattening
    encoded_code = control_flow_flattening(encoded_code)

    -- Step 7: Generate string decoder and encoded strings table
    local decoder_code = generate_string_decoder(encoded_strings)

    -- Combine decoder and obfuscated code
    local final_code = decoder_code .. "\n\n" .. encoded_code

    -- Write to output file
    local outfile = io.open(output_path, "w")
    if not outfile then
        print("Error: Cannot open output file: "..output_path)
        return
    end
    outfile:write(final_code)
    outfile:close()

    print("Obfuscation complete. Output written to "..output_path)
end

-- Command line interface
local arg = {...}
if #arg < 2 then
    print("Usage: lua obfuscator.lua input.lua output.lua")
    os.exit(1)
end

obfuscate(arg[1], arg[2])
