#!/bin/sh

# ================= 配置信息 =================
PKG_NAME="luci-app-iptv-scan"
PKG_VERSION="1.0.0-1"
PKG_ARCH="all"
BUILD_ROOT="/tmp/ipk_root"
DATA_DIR="/tmp/ipk_data"
CONTROL_DIR="/tmp/ipk_control"
OUTPUT_DIR=$(pwd)

echo "开始构建 $PKG_NAME ..."

# 1. 环境准备
rm -rf $BUILD_ROOT $DATA_DIR $CONTROL_DIR
mkdir -p $DATA_DIR/usr/bin
mkdir -p $DATA_DIR/usr/lib/lua/luci/controller
mkdir -p $DATA_DIR/usr/lib/lua/luci/model/cbi
mkdir -p $DATA_DIR/usr/lib/lua/luci/view/cbi
mkdir -p $DATA_DIR/usr/share/rpcd/acl.d
mkdir -p $DATA_DIR/etc/config
mkdir -p $CONTROL_DIR
mkdir -p $BUILD_ROOT

# ---------------------------------------------------------
# 2. 写入文件内容
# ---------------------------------------------------------

# 2.1 后台 Lua 扫描引擎
cat <<'EOF' > $DATA_DIR/usr/bin/iptv_scan.lua
#!/usr/bin/lua
local socket = require("socket")
local uci = require("luci.model.uci").cursor()

local section = "@settings[0]"
local INTERFACE_NAME = uci:get("iptv_scan", section, "interface")
local TIMEOUT        = tonumber(uci:get("iptv_scan", section, "timeout")) or 1.0
local DICT_FILE      = uci:get("iptv_scan", section, "dict_file") or "/root/iptv_dict.txt"
local CITY_FILE      = uci:get("iptv_scan", section, "city_file") or "/root/city_list.txt"
local OUTPUT_M3U      = uci:get("iptv_scan", section, "m3u_file") or "/www/iptv.m3u"
local OUTPUT_TXT      = uci:get("iptv_scan", section, "txt_file") or "/www/iptv.txt"
local PLAY_PREFIX    = uci:get("iptv_scan", section, "play_prefix")
PLAY_PREFIX = (PLAY_PREFIX and PLAY_PREFIX ~= "") and PLAY_PREFIX or "rtp://"
local EPG_URL = uci:get("iptv_scan", section, "epg_url")
EPG_URL = (EPG_URL and EPG_URL ~= "") and EPG_URL or ""
local LOGO_BASE = uci:get("iptv_scan", section, "logo_base")
LOGO_BASE = (LOGO_BASE and LOGO_BASE ~= "") and LOGO_BASE or ""

local OUTPUT_M3U_HD   = OUTPUT_M3U:gsub("%.m3u$", "_hd.m3u")

local LOCK_FILE = "/tmp/iptv_scan.lock"

local function log(msg)
    print(msg)
    io.stdout:flush()
end

-- ================= 文件锁逻辑 =================
local function acquire_lock()
    local f = io.open(LOCK_FILE, "r")
    if f then
        local pid = f:read("*all")
        f:close()
        if pid and pid:match("^%d+$") then
            local running = os.execute("kill -0 " .. pid .. " 2>/dev/null")
            if running == 0 or running == true then
                return false
            end
        end
        os.remove(LOCK_FILE)
    end

    local my_pid = io.popen("pgrep -f 'lua /usr/bin/iptv_scan.lua' | head -n 1"):read("*a"):gsub("%s+", "")
    if my_pid == "" then
        my_pid = io.popen("sh -c 'echo $PPID'"):read("*a"):gsub("%s+", "")
    end

    f = io.open(LOCK_FILE, "w")
    if f then
        f:write(my_pid)
        f:close()
        return true
    end
    return false
end

local function release_lock()
    os.remove(LOCK_FILE)
end

-- ================= 精简频道名 =================
local function get_pure_tvg_name(name)
    if not name or name:find("未识别") then return "" end
    local n = name:upper()
    n = n:gsub("CCTV[%-%s]?4K", "PROTECTCCTVFOURK")
    n = n:gsub("CCTV[%-%s]?5%+", "PROTECTCCTVFIVEPLUS")
    n = n:gsub("爱上4K", "PROFOURK")
	n = n:gsub("茶频道", "PROCHA")
    local keywords = {"奥林匹克", "超高清", "高清", "标清", "频道", "字幕", "UHD", "FHD", "4K", "8K", "HD"}
    for _, k in ipairs(keywords) do n = n:gsub(k, "") end
	if n:find("CCTV") then n = n:gsub("[\128-\255]+", "") end
    local symbols = {"·", "—", "｜", "“", "”", "▲", "★"}
    for _, s in ipairs(symbols) do n = n:gsub(s, "") end
    n = n:gsub("[%p%s]", "")
    n = n:gsub("PROTECTCCTVFOURK", "CCTV4K")
    n = n:gsub("PROTECTCCTVFIVEPLUS", "CCTV5+")
    n = n:gsub("PROFOURK", "爱上4K")
	n = n:gsub("PROCHA", "茶频道")
    return n
end

-- ================= 分类与配置 =================
local CAT_LIST = {
    { key = "CCTV",                name = "央视频道" },
    { key = "卫视",                name = "卫视频道" },
    { key = "电影,影视,影院,剧场", name = "影视频道" },
    { key = "少儿,动画,卡通,动漫", name = "少儿频道" }, 
    { key = "体育,竞技,足球",      name = "体育频道" }
}
local CITY_LIST = {}

for _, cat in ipairs(CAT_LIST) do
    cat.keys = {}
    for k in cat.key:gmatch("([^,]+)") do
        table.insert(cat.keys, k:gsub("%s+", ""):upper())
    end
end

local function load_cities(path)
    local list = {}
    local f = io.open(path, "r")
    if not f then
	log("[警告] 城市列表文件不存在，地方频道可能无法正确归类 ：" .. path)
	return list end
    for line in f:lines() do
        local c = line:gsub("%s+", "")
        if c ~= "" then table.insert(list, c) end
    end
    f:close()
    log("[系统] 已加载城市关键词: " .. #list .. " 个")
    return list
end

local function load_dict(path)
    local dict = {}
    if not path or path == "" then return dict end
    local f = io.open(path, "r")
    if not f then
        log('[警告] 字典文件未找到，扫描结果将显示为“未识别” ：' .. path)
        return dict 
    end

    local count = 0
    for line in f:lines() do
        line = line:gsub("%s+", "")
        local name, ip_port = line:match("([^,]+),.-(%d+%.%d+%.%d+%.%d+:%d+)")
        if name and ip_port then 
            dict[ip_port] = name 
            count = count + 1
        end
    end
    f:close()
    log("[系统] 已加载字典记录: " .. count .. " 条")
    return dict
end

local function get_category(name)
    local n_up = name:upper()
    for i = 1, 2 do
        local cat = CAT_LIST[i]
        for _, k in ipairs(cat.keys) do
            if n_up:find(k, 1, true) then return cat.name end
        end
    end
    for _, city in ipairs(CITY_LIST) do
        if name:find(city, 1, true) then return "地方频道" end
    end
    for i = 3, #CAT_LIST do
        local cat = CAT_LIST[i]
        for _, k in ipairs(cat.keys) do
            if n_up:find(k, 1, true) then return cat.name end
        end
    end
    return "其他频道"
end

local function get_quality(name)
    local n = name:upper()
    if n:find("4K") or n:find("超高清") then return "4K"
    elseif n:find("高清") or n:find("HD") or n:find("1080") or n:find("720") then return "高清"
    else return "标清" end
end

local function get_interface_robust(name)
    local info = { device = nil, ip = "0.0.0.0", error = nil }
	
    if not name or name == "" then
        info.error = "未配置扫描接口，请选择接口（如 eth0, 或 wan）。"
        return info
    end

    local handle = io.popen("ubus call network.interface." .. name .. " status 2>/dev/null")
    local res = handle:read("*a")
    handle:close()
	
    if res and res ~= "" and res ~= "{}" then
        info.device = res:match('\"l3_device\":%s*\"([^%s\"]+)\"')
        info.ip = res:match('\"address\":%s*\"(%d+%.%d+%.%d+%.%d+)\"')
    end

    if not info.ip or info.ip == "0.0.0.0" then
        local f = io.popen("ifconfig " .. name .. " 2>/dev/null")
        if f then
            local out = f:read("*all")
            f:close()
            info.ip = out:match("inet addr:(%d+%.%d+%.%d+%.%d+)") or out:match("inet (%d+%.%d+%.%d+%.%d+)")
            info.device = name
        end
    end

    if not info.ip or info.ip == "0.0.0.0" then
        info.error = "接口 [" .. name .. "] 无法获取 IP。请确保接口已连接并获得地址。"
    end
    return info
end

-- ==================== 核心扫描函数 ====================
local function run_scan()
    local start_time = os.time()
    local total_found, total_scanned = 0, 0
    local range_stats, scan_results = {}, {}

    log("========================================")
    log("任务启动: " .. os.date())
    
    local net = get_interface_robust(INTERFACE_NAME)    
    if net.error then
        log("\n[错误] " .. net.error)
        log("[失败] 扫描任务终止。")
        log("========================================")
        return
    end

    log("[网络] 接口: " .. net.device .. " | IP: " .. net.ip)

    CITY_LIST = load_cities(CITY_FILE)
    local name_dict = load_dict(DICT_FILE)
    
    local RAW_RANGES = uci:get("iptv_scan", "@settings[0]", "ranges")
    local TASKS = {}
    if not RAW_RANGES or (type(RAW_RANGES) == "string" and RAW_RANGES == "") then
        log("[错误] 待扫描网段配置为空，请检查配置文件。")
        return
    end
    if type(RAW_RANGES) == "table" then 
        TASKS = RAW_RANGES
    elseif type(RAW_RANGES) == "string" then 
        table.insert(TASKS, RAW_RANGES) 
    end
    local validated_tasks = {}
    for _, val in ipairs(TASKS) do
        local prefix, port = val:match("^(%d+%.%d+%.%d+%.)%:(%d+)$")        
        if prefix and port then
            table.insert(validated_tasks, {prefix = prefix, port = tonumber(port)})
        else
            log("[警告] 网段格式错误，已忽略: " .. tostring(val))
        end
    end
    if #validated_tasks == 0 then
        log("[错误] 未发现合法的扫描任务，任务终止。格式: 239.81.0.:8000")
        return
    end

for _, task in ipairs(validated_tasks) do
        local prefix, port = task.prefix, task.port
        local r_found = 0
        log("[扫描] 网段: " .. prefix .. "X:" .. port)        
        for i = 1, 255 do
            total_scanned = total_scanned + 1
            local target_ip = prefix .. i
            local key = target_ip .. ":" .. port
            local udp = socket.udp()
            udp:settimeout(TIMEOUT)
            udp:setsockname("0.0.0.0", port)
            
            if udp:setoption("ip-add-membership", {multiaddr = target_ip, interface = net.ip}) then
                local data = udp:receive()
                if data and (string.byte(data, 1) == 0x80 or data:sub(1,1):find("\x47")) then
                    r_found = r_found + 1
                    total_found = total_found + 1
                    local cname = name_dict[key] or ("未识别-" .. target_ip)
                    local cat = get_category(cname)
                    local q = get_quality(cname)
                    table.insert(scan_results, {
                        name = cname, 
                        url = PLAY_PREFIX .. key,
                        cat_full = cat .. "-" .. q, 
                        sort_key = cat .. q .. cname
                    })
                    log("  >> [√] " .. cname .. " [" .. q .. "]")
                end
            end
            udp:close()
        end
        table.insert(range_stats, { range = prefix .. "X:" .. port, found = r_found })
    end

    -- 自然排序逻辑
    table.sort(scan_results, function(a, b)
        if a.cat_full ~= b.cat_full then return a.cat_full < b.cat_full end
        local str_a = a.name:upper():gsub("[48]K", "")
        local str_b = b.name:upper():gsub("[48]K", "")
        local num_a = tonumber(str_a:match("(%d+)"))
        local num_b = tonumber(str_b:match("(%d+)"))
        if num_a and num_b then
            if num_a ~= num_b then return num_a < num_b
            else
                local plus_a = a.name:find("+", 1, true) and 1 or 0
                local plus_b = b.name:find("+", 1, true) and 1 or 0
                if plus_a ~= plus_b then return plus_a < plus_b end
            end
        end
        return a.sort_key < b.sort_key
    end)

    -- 输出文件
    local f_m3u = io.open(OUTPUT_M3U, "w")
    local f_m3u_hd = io.open(OUTPUT_M3U_HD, "w")
    local f_txt = io.open(OUTPUT_TXT, "w")
    local bom = "\239\187\191"
    if f_m3u then
    	if EPG_URL and EPG_URL ~= "" then
        	f_m3u:write(string.format('#EXTM3U x-tvg-url="%s"\n', EPG_URL))
    	else
        	f_m3u:write('#EXTM3U\n')
    	end
	end
	if f_m3u_hd then
    	if EPG_URL and EPG_URL ~= "" then
        	f_m3u_hd:write(string.format('#EXTM3U x-tvg-url="%s"\n', EPG_URL))
    	else
        	f_m3u_hd:write('#EXTM3U\n')
    	end
	end
    
	local base_path = LOGO_BASE or ""
    if base_path ~= "" and base_path:sub(-1) ~= "/" then
        base_path = base_path .. "/"
    end

    local last_cat = ""
    for _, item in ipairs(scan_results) do
        local pure_name = get_pure_tvg_name(item.name)      
        
        local name_attr = ""
        if pure_name ~= "" then
            name_attr = string.format(' tvg-name="%s"', pure_name)
        end

        local logo_attr = ""
        if base_path ~= "" and pure_name ~= "" then
            logo_attr = string.format(' tvg-logo="%s%s.png"', base_path, pure_name)
        end

        if f_m3u then 
            f_m3u:write(string.format('#EXTINF:-1%s%s group-title="%s",%s\n%s\n', 
                name_attr, logo_attr, item.cat_full, item.name, item.url)) 
        end

        if f_m3u_hd and not item.cat_full:find("标清") then
            local clean_name = item.name
            local p_list = { "[%[%‍%(（【《]?[Hh][Dd][%]%]%)）】》]?", "[%[%‍%(（【《]?高清[%]%]%)）】》]?",
                             "[%-%s/—_]+[Hh][Dd]", "[%-%s/—_]+高清" }
            for _, p in ipairs(p_list) do clean_name = clean_name:gsub(p, "") end
            clean_name = clean_name:match("^[%s%p]*(.-)[%s%p]*$") or clean_name

            local clean_cat = item.cat_full:gsub("%-高清", ""):gsub("%-HD", "")            

            f_m3u_hd:write(string.format('#EXTINF:-1%s%s group-title="%s",%s\n%s\n', 
                name_attr, logo_attr, clean_cat, clean_name, item.url))
        end

        if f_txt then
            if item.cat_full ~= last_cat then 
                f_txt:write("\n" .. item.cat_full .. ",#genre#\n") 
                last_cat = item.cat_full 
            end
            f_txt:write(item.name .. "," .. item.url .. "\n")
        end
    end


    if f_m3u then f_m3u:close() end
    if f_m3u_hd then f_m3u_hd:close() end
    if f_txt then f_txt:close() end
    
    log("\n--------------- 统计报告 ---------------")
    log("扫描耗时: " .. os.difftime(os.time(), start_time) .. " 秒")
    log("总计发现有效频道: " .. total_found)
    for _, res in ipairs(range_stats) do 
        log("  - 网段 [" .. res.range .. "] : 发现 " .. res.found .. " 个频道") 
    end
    log("  >> 全量文件: " .. OUTPUT_M3U)
    log("  >> 高清文件: " .. OUTPUT_M3U_HD)
    log("===========================================")
end

-- ================= 主执行逻辑 =================

local function main()
    if not acquire_lock() then
        log("\n[拒绝] 扫描任务已在运行中，请勿重复启动。")
        return
    end

    local status, err = pcall(run_scan)
    
    if not status then
        log("\n[致命错误] 脚本崩溃: " .. tostring(err))
    end

    release_lock()
end

main()
EOF
chmod +x $DATA_DIR/usr/bin/iptv_scan.lua

# 2.2 LuCI 控制器
cat <<'EOF' > $DATA_DIR/usr/lib/lua/luci/controller/iptv_scan.lua
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
EOF

# 2.3 LuCI CBI 界面
cat <<'EOF' > $DATA_DIR/usr/lib/lua/luci/model/cbi/iptv_scan.lua
local m, s, iface, timeout, ranges, dict, city, m3u, txt, epg, run, stop

m = Map("iptv_scan", "IPTV 组播频道扫描", 
    "修改配置后请点击‘保存并应用’再开始扫描。")

s = m:section(TypedSection, "settings")
s.anonymous = true
s:tab("basic", "基础配置")
s:tab("log", "运行日志")

-- ================= 基础配置标签页 =================

iface = s:taboption("basic", ListValue, "interface", "扫描接口")
for _, n in ipairs(luci.sys.net.devices()) do
    if n ~= "lo" and not n:find("veth") then
        iface:value(n)
    end
end

timeout = s:taboption("basic", Value, "timeout", "超时(秒)")
timeout.default = "1.0"
timeout.datatype = "string" 

ranges = s:taboption("basic", DynamicList, "ranges", "待扫描网段", "格式 - 前缀:端口 (例: 239.1.0.:8000)")

dict = s:taboption("basic", Value, "dict_file", "字典路径", "频道名称匹配库 (.txt), 内容格式:  频道名,rtp://ip:端口")
dict.datatype = "string"
dict.placeholder = "/root/iptv_dict.txt"

city = s:taboption("basic", Value, "city_file", "城市列表", "用于地方频道分类 (.txt)")
city.datatype = "string"
city.default = "/root/city_list.txt"

epg = s:taboption("basic", Value, "epg_url", "EPG 源地址", "用于 M3U 文件头的 x-tvg-url")
epg.default = "https://gitee.com/taksssss/tv/raw/main/epg/51zmt.xml.gz"

logo = s:taboption("basic", Value, "logo_base", "图标基础路径", "用于拼接 tvg-logo。格式 URL (如 http://addr/ ) 。")
logo.default = "https://gcore.jsdelivr.net/gh/taksssss/tv/icon/"
logo.placeholder = "https://gcore.jsdelivr.net/gh/taksssss/tv/icon/"

m3u = s:taboption("basic", Value, "m3u_file", "M3U 路径")
m3u.datatype = "string"
m3u.default = "/www/iptv.m3u"

txt = s:taboption("basic", Value, "txt_file", "TXT 路径")
txt.datatype = "string"
txt.default = "/www/iptv.txt"

prefix = s:taboption("basic", Value, "play_prefix", "播放前缀")
prefix.default = "rtp://"

-- ================= 任务操作按钮 =================

run = s:taboption("basic", Button, "_run", "任务操作")
run.inputtitle = "开始扫描"
run.inputstyle = "apply"
function run.write(self, section)
    if luci.http.formvalue(self:cbid(section)) then
        local pid = luci.sys.exec("cat /tmp/iptv_scan.lock 2>/dev/null"):gsub("%s+", "")
        local is_running = false
        if pid ~= "" then
            is_running = luci.sys.call("kill -0 " .. pid .. " 2>/dev/null") == 0
        end

        if is_running then
            luci.sys.call("echo \"[警告] 扫描任务 (PID: " .. pid .. ") 已经在运行中...\" >> /tmp/iptv_scan.log")
        else
            luci.sys.call("rm -f /tmp/iptv_scan.lock")
            luci.sys.call("echo \"[系统] 正在启动任务...\" > /tmp/iptv_scan.log")
            luci.sys.call("/usr/bin/lua /usr/bin/iptv_scan.lua >> /tmp/iptv_scan.log 2>&1 &")
        end
        luci.http.header("Referer", luci.http.getenv("HTTP_REFERER"))
    end
end

stop = s:taboption("basic", Button, "_stop", "终止扫描")
stop.inputtitle = "停止扫描"
stop.inputstyle = "reset"
function stop.write(self, section)
    if luci.http.formvalue(self:cbid(section)) then
        local pid = luci.sys.exec("cat /tmp/iptv_scan.lock 2>/dev/null"):gsub("%s+", "")      
        if pid ~= "" and pid:match("^%d+$") then
            luci.sys.call("kill -9 " .. pid .. " >/dev/null 2>&1")
            luci.sys.call("pkill -9 -f iptv_scan.lua >/dev/null 2>&1")            
            luci.sys.call("rm -f /tmp/iptv_scan.lock")
            luci.sys.call("echo \"[系统] 已强制停止 PID 为 " .. pid .. " 的扫描进程。\" >> /tmp/iptv_scan.log")
        else
            luci.sys.call("pkill -9 -f iptv_scan.lua >/dev/null 2>&1")
            luci.sys.call("rm -f /tmp/iptv_scan.lock")
            luci.sys.call("echo \"[系统] 未发现锁文件，已尝试清理残留进程。\" >> /tmp/iptv_scan.log")
        end
        luci.http.header("Referer", luci.http.getenv("HTTP_REFERER"))
    end
end

-- ================= 日志标签页 =================

log_view = s:taboption("log", DummyValue, "_log")
log_view.template = "cbi/log_view"

return m
EOF

# 2.4 日志 View 模板
cat <<'EOF' > $DATA_DIR/usr/lib/lua/luci/view/cbi/log_view.htm
<%+cbi/valueheader%>
<style>
    #log_content { width: 100% !important; min-height: 500px; background-color: #ffffff; color: #333333; font-family: monospace; font-size: 13px; padding: 12px; border: 1px solid #cccccc; border-radius: 4px; white-space: pre; overflow: auto; box-sizing: border-box; }
</style>
<div style="margin-bottom:10px;"><input type="button" class="cbi-button cbi-button-apply" value="刷新/读取日志" onclick="update_log(this)" /></div>
<textarea id="log_content" readonly>等待扫描开始...</textarea>
<script type="text/javascript">//<![CDATA[
    function update_log(btn) {
        var area = document.getElementById('log_content');
        var old_val = btn.value; btn.value = "正在读取..."; btn.disabled = true;
        XHR.get('<%=luci.dispatcher.build_url("admin", "services", "iptv_scan_getlog")%>', null, function(x, data) {
            btn.disabled = false; btn.value = old_val;
            if (x && x.responseText) { area.value = x.responseText; area.scrollTop = area.scrollHeight; }
        });
    }
//]]></script>
<%+cbi/valuefooter%>
EOF

# 2.5 ACL 与 默认配置
cat <<EOF > $DATA_DIR/usr/share/rpcd/acl.d/luci-app-iptv-scan.json
{ "luci-app-iptv-scan": { "description": "IPTV", "read": { "cgi-bin/luci/admin/services/iptv_scan*": [ "exec" ], "file": { "/*": [ "read" ] } }, "write": { "cgi-bin/luci/admin/services/iptv_scan*": [ "exec" ], "file": { "/tmp/iptv_scan.log": [ "write" ], "/www/*": [ "write" ] } } } }
EOF

cat <<EOF > $DATA_DIR/etc/config/iptv_scan

config settings
	option interface ''
	option timeout '1.0'
	list ranges '239.81.0.:4056'
	list ranges '239.81.1.:4056'
	option dict_file '/root/iptv_dict.txt'
	option city_file '/root/city_list.txt'
	option epg_url ''
	option logo_base ''
	option m3u_file '/www/iptv.m3u'
	option txt_file '/www/iptv.txt'
	option play_prefix 'rtp://'
EOF

# ---------------------------------------------------------
# 3. 制作 CONTROL
# ---------------------------------------------------------
cat <<EOF > $CONTROL_DIR/control
Package: $PKG_NAME
Version: $PKG_VERSION
Section: luci
Architecture: $PKG_ARCH
Depends: luasocket, luci-base, luci-compat, libuci-lua
Description: IPTV Multicast Scanner
EOF

cat <<EOF > $CONTROL_DIR/postinst
#!/bin/sh
[ -n "\${IPKG_INSTROOT}" ] || {
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
    killall -HUP rpcd 2>/dev/null
}
exit 0
EOF
chmod +x $CONTROL_DIR/postinst

# ---------------------------------------------------------
# 4. 打包 IPK
# ---------------------------------------------------------
echo "正在打包中..."
cd $DATA_DIR && tar -czf $BUILD_ROOT/data.tar.gz .
cd $CONTROL_DIR && tar -czf $BUILD_ROOT/control.tar.gz .
cd $BUILD_ROOT
echo "2.0" > debian-binary
IPK_FILE="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"
tar -czf $OUTPUT_DIR/$IPK_FILE ./debian-binary ./control.tar.gz ./data.tar.gz

echo "--------------------------------------------"
echo "打包完成！文件名: $IPK_FILE"
echo "使用说明: opkg install ./$IPK_FILE"
echo "--------------------------------------------"
rm -rf $DATA_DIR $CONTROL_DIR $BUILD_ROOT
