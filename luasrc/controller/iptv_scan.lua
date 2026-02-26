module("luci.controller.iptv_scan", package.seeall)

function index()
    entry({"admin", "services", "iptv_scan"}, cbi("iptv_scan"), _("IPTV 扫描"), 90).dependent = true
    entry({"admin", "services", "iptv_scan_getlog"}, call("action_getlog")).leaf = true
    entry({"admin", "services", "iptv_scan_status"}, call("action_check_status")).leaf = true
end

function action_getlog()
    local f = io.open("/tmp/iptv_scan.log", "r")
    local data = f and f:read("*all") or ""
    if f then f:close() end
    luci.http.prepare_content("text/plain; charset=utf-8")
    luci.http.write(data)
end

function action_check_status()
    local running = false
    local lock_file = "/tmp/iptv_scan.lock"
    local f = io.open(lock_file, "r")
    if f then
        local pid = f:read("*all"):gsub("%s+", "")
        f:close()
        if pid and pid:match("^%d+$") then
            local res = luci.sys.call("kill -0 " .. pid .. " 2>/dev/null")
            if res == 0 then
                running = true
            else
                os.remove(lock_file)
            end
        else
            os.remove(lock_file)
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({ running = running })
end
