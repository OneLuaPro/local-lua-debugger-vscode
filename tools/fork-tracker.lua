--[[
MIT License

Copyright (c) 2026 The OneLuaPro project authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

-------------------------------------------------------------------------------
FORK-TRACKER: GitHub Network Activity Monitor
-------------------------------------------------------------------------------
This script recursively scans a GitHub repository's entire fork network
(including forks of forks) to identify active development branches.

Key Features:
- Baseline Comparison: Compares the last commit date of every fork against
  your own repository's last update.
- Deep Scanning: Traverses the network tree to find active "grandchild" forks
  even if their parent repositories are inactive.
- Activity Detection: Flags forks that contain commits newer than your
  baseline, helping maintainers track upstream changes or community patches.
- Tree Visualization: Outputs a structured ASCII tree of the discovered network.

Usage: lua fork-tracker.lua <token> [-d <depth>]
]]--

local https = require("ssl.https")
local json = require("cjson")
local ltn12 = require("ltn12")
local argparse = require("argparse")

-- Hardcoded repository configuration
local ROOT_REPO = "tomblind/local-lua-debugger-vscode"
local MY_REPO = "OneLuaPro/local-lua-debugger-vscode"
-- local MY_REPO = "Ismoh/local-lua-debugger-vscode"	-- Test only

-- Argument parsing
local parser = argparse("fork-tracker", "Compares last commit dates of all forks against " .. MY_REPO)
parser:argument("token", "GitHub Personal Access Token")
parser:option("-d --depth", "Maximum recursion depth for fork scanning", 3)
local args = parser:parse()

local API_TOKEN = args.token
local MAX_DEPTH = tonumber(args.depth)

local function github_get(path)
   local response_body = {}
   local _, code = https.request({
	 url = "https://api.github.com" .. path,
	 headers = {
            ["User-Agent"] = "Lua-Scanner",
            ["Authorization"] = "token " .. API_TOKEN,
            ["Accept"] = "application/vnd.github+json"
	 },
	 verify = "none",
	 sink = ltn12.sink.table(response_body)
   })
   if code == 401 then
      print("\n[ERROR] 401 Unauthorized: Your GitHub token is invalid or has been revoked.")
      os.exit(1)
   elseif code == 403 then
      print("\n[ERROR] 403 Forbidden: API Rate limit exceeded or insufficient permissions.")
      os.exit(1)
   elseif code ~= 200 then
      print("\n[ERROR] HTTP " .. tostring(code) .. " occurred.")
      return nil
   end
   return json.decode(table.concat(response_body))
end

-- Fetches the date of the very last commit in a repo
local function get_last_commit_date(repo)
   local data = github_get("/repos/" .. repo .. "/commits?per_page=1")
   if data and data[1] then
      return data[1].commit.committer.date
   end
   return nil
end

local my_last_update = get_last_commit_date(MY_REPO)

local function fetch_active_forks(repo_full_name, depth)
   if depth > MAX_DEPTH then return {} end

   local forks = github_get("/repos/" .. repo_full_name .. "/forks?per_page=100&sort=stargazers")
   if not forks then return {} end

   local results = {}
   for _, f in ipairs(forks) do
      if f.full_name ~= MY_REPO then
         local fork_last_update = get_last_commit_date(f.full_name)

         local sub_results = fetch_active_forks(f.full_name, depth + 1)

         if fork_last_update and my_last_update and fork_last_update > my_last_update then
            -- Found active fork
            print(string.format("  [!] ACTIVE: %s (Last commit: %s)",
                                f.full_name, fork_last_update:sub(1,10)))
            table.insert(results, {
                name = string.format("%s (Updated: %s)",
                         f.full_name, fork_last_update:sub(1,10)),
                children = sub_results
            })
         elseif #sub_results > 0 then
            -- Parent inactive but has active children -> show in tree to maintain structure
            print(string.format("  [.] %s (Inactive, but tracking %d active child-branches)",
                                f.full_name, #sub_results))
            table.insert(results, {
                name = f.full_name .. " (Inactive parent)",
                children = sub_results
            })
         else
            -- Totally inactive branch
            local last_date = fork_last_update and fork_last_update:sub(1,10) or "unknown"
            print(string.format("  [-] %s (Last commit: %s)", f.full_name, last_date))
         end
      end
   end
   return results
end

local function draw(tree, indent)
   indent = indent or ""
   for i, node in ipairs(tree) do
      local is_last = (i == #tree)
      local branch = is_last and "|__ " or "|-- "
      print(indent .. branch .. node.name)
      local next_indent = indent .. (is_last and "    " or "|   ")
      draw(node.children, next_indent)
   end
end

print("Scanning fork network for activity newer than yours...")
print("Your last commit: " .. (my_last_update and my_last_update:sub(1,10) or "unknown"))
print("--------------------------------------------------\n")

local data = fetch_active_forks(ROOT_REPO, 1)

print("\nNEW ACTIVITY FOUND:")
if #data == 0 then
   print("No public forks found with commits newer than your last update.")
else
   draw(data)
end
