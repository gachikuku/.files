-- Run: rex do ~/.files/rex/tests/test_file_at_click.lua --json
-- Pure tests: no filesystem mutation, sessions, tabs, or external processes.
local parser = dofile(os.getenv("HOME") .. "/.config/rex/file-at-click.lua")
local cwd = "/project/work"
local results = {}
local function check(name, text, needle, expected, line, options)
  options = options or {}
  local position = assert(text:find(needle, 1, true), name .. ": missing click fixture")
  position = position + (options.offset or 0)
  local files = options.files or { expected }
  local function exists(value)
    for _, file in ipairs(files) do if value == file then return true end end
    return false
  end
  local target_cwd
  if not options.no_cwd then target_cwd = options.cwd or cwd end
  local found, found_line = parser.find(text, position, exists, target_cwd)
  assert(found == expected, name .. ": expected " .. tostring(expected) .. ", got " .. tostring(found))
  assert(found_line == line, name .. ": unexpected line " .. tostring(found_line))
  results[#results + 1] = name
end

check("absolute", "See /tmp/report.json", "report", "/tmp/report.json")
check("absolute colon line", "/tmp/source.lua:12:4", "source", "/tmp/source.lua", 12)
check("absolute punctuation", "(/tmp/report.json).", "report", "/tmp/report.json")
check("absolute quoted spaces", '"/tmp/report with spaces.json"', "with", "/tmp/report with spaces.json")
check("absolute backtick spaces", '`/tmp/report with spaces.json`', "with", "/tmp/report with spaces.json")
check("tilde", "~/report.json", "report", os.getenv("HOME") .. "/report.json")
check("file URI", "file:///tmp/a%20b.json", "a%20b", "/tmp/a b.json")
check("localhost URI", "file://localhost/tmp/report.json", "report", "/tmp/report.json")
check("bare filename", "report.json", "report", cwd .. "/report.json")
check("parenthesized filename", "successful run (h1-4138534-report.jsonl)", "report", cwd .. "/h1-4138534-report.jsonl")
check("relative slash", "logs/report.json", "report", cwd .. "/logs/report.json")
check("dot prefix", "./report.json", "report", cwd .. "/./report.json")
check("parent prefix preserves symlink semantics", "../report.json", "report", cwd .. "/../report.json")
check("explicit extensionless", "./README", "README", cwd .. "/./README")
check("hidden filename", ".gitignore", "gitignore", cwd .. "/.gitignore")
check("relative quoted spaces", '"reports/report with spaces.json"', "spaces", cwd .. "/reports/report with spaces.json")
check("relative single quotes", "'report with spaces.json'", "spaces", cwd .. "/report with spaces.json")
check("relative backtick spaces", "`report with spaces.json`", "spaces", cwd .. "/report with spaces.json")
check("relative line", "Code.md:42", "Code", cwd .. "/Code.md", 42)
check("relative line and column", "Code.md:42:3", "42", cwd .. "/Code.md", 42)
check("quoted relative line", '"report with spaces.json":9:2', "spaces", cwd .. "/report with spaces.json", 9)
check("relative trailing punctuation", "report.json,", "report", cwd .. "/report.json")
check("literal existing punctuation wins", "report.json,", "report", cwd .. "/report.json,")
check("literal existing colon suffix wins", "report.json:9", "report", cwd .. "/report.json:9")
check("two-line wrap", "h1-4138534-long-\n  report.jsonl", "report", cwd .. "/h1-4138534-long-report.jsonl")
check("three-line wrap", "h1-4138534-\n  long-\n  report.jsonl", "report", cwd .. "/h1-4138534-long-report.jsonl")
check("quoted wrap", '"report with\n spaces.json"', "spaces", cwd .. "/report withspaces.json")
check("absolute wrap", "/tmp/long-\n report.json", "report", "/tmp/long-report.json")
check("root cwd", "report.json", "report", "/report.json", nil, { cwd = "/" })
check("cwd trailing slash", "report.json", "report", cwd .. "/report.json", nil, { cwd = cwd .. "/" })

-- No basename guessing within URLs/emails, even if that basename exists.
for _, value in ipairs({ "https://example.test/report.json", "file://remote/tmp/report.json",
    "mailto:report.json@example.test", "person@report.json", "ssh:report.json", "www.example.test/report.json" }) do
  check("reject " .. value, value, "report.json", nil, nil,
    { files = { cwd .. "/report.json", cwd .. "/example.test/report.json", "/report.json" } })
  assert(#parser.candidates(value, assert(value:find("report.json", 1, true))) == 0)
end
check("unquoted non-file word", "successful run", "successful", nil, nil, { files = { cwd .. "/successful" } })
check("missing relative file", "missing.json", "missing", nil)
check("missing quoted path does not fall back to basename", '"not present.json"', "present", nil, nil,
  { files = { cwd .. "/present.json" } })
check("relative requires cwd", "report.json", "report", nil, nil,
  { no_cwd = true, files = { cwd .. "/report.json" } })
check("absolute without cwd", "/tmp/report.json", "report", "/tmp/report.json", nil, { no_cwd = true })
check("long punctuation tail", "report.json" .. string.rep(")", 70), "report", cwd .. "/report.json")

local candidates = parser.candidates("successful run (h1-report.jsonl:23)", 20)
local matched = false
for _, candidate in ipairs(candidates) do
  assert(candidate.path:sub(1, 1) ~= "/")
  if candidate.path == "h1-report.jsonl" and candidate.line == 23 then matched = true end
end
assert(matched, "Deferred candidates must preserve filename and line")
assert(#parser.candidates("plain prose", 3) == 0)
assert(#parser.candidates("file.json", 0) == 0)
assert(parser.find("file.json", 1, function() return true end, "relative/cwd") == nil)
assert(#parser.candidates(string.rep("a", 4097) .. ".json", 3) == 0, "Oversized path must be skipped")
local bounded = parser.candidates("report.json" .. string.rep(")", 5000), 3)
local bytes = 0
for _, candidate in ipairs(bounded) do
  assert(#candidate.path <= 4096)
  bytes = bytes + #candidate.path
end
assert(#bounded <= 1024 and bytes <= 65536, "Deferred candidate payload must be bounded")
return { passed = #results + 6, cases = results }
