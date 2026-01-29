module("luci.controller.iptv_scan", package.seeall)
function index()
    entry({"admin", "services", "iptv_scan"}, cbi("iptv_scan"), _("IPTV 扫描"), 90).dependent = true
    entry({"admin", "services", "iptv_scan_getlog"}, call("action_getlog")).leaf = true
end
function action_getlog()
    local f = io.open("/tmp/iptv_scan.log", "r")
    local data = f and f:read("*all") or ""
    if f then f:close() end
    luci.http.prepare_content("text/plain; charset=utf-8")
    luci.http.write(data)
end
