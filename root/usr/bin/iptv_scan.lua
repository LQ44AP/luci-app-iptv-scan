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
EPG_URL = (EPG_URL and EPG_URL ~= "") and EPG_URL or "https://gitee.com/taksssss/tv/raw/main/epg/51zmt.xml.gz"

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
    end

    local handle = io.popen("echo -n $$")
    local my_pid = handle:read("*a")
    handle:close()
    
    f = io.open(LOCK_FILE, "w")
    if f then
        f:write(my_pid or "running")
        f:close()
    end
    return true
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
	log("[警告] 城市列表文件不存在: " .. path)
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
        log("[系统] 字典文件未找到，将使用默认命名。")
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
    local info = { device = nil, ip = "0.0.0.0" }
    local handle = io.popen("ubus call network.interface." .. name .. " status 2>/dev/null")
    local res = handle:read("*a")
    handle:close()
    if res and res ~= "" then
        info.device = res:match('\"l3_device\":%s*\"([^%s\"]+)\"')
        info.ip = res:match('\"address\":%s*\"(%d+%.%d+%.%d+%.%d+)\"')
    end
    if not info.device then info.device = name end
    if not info.ip or info.ip == "0.0.0.0" then
        local f = io.popen("ifconfig " .. info.device .. " 2>/dev/null")
        if f then
            local out = f:read("*all")
            f:close()
            info.ip = out:match("inet addr:(%d+%.%d+%.%d+%.%d+)") or out:match("inet (%d+%.%d+%.%d+%.%d+)")
        end
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
    if not net.ip or net.ip == "0.0.0.0" then
        log("[警告] 接口 " .. net.device .. " 未获取到有效 IP，终止扫描。")
        return
    end

    log("[网络] 接口: " .. net.device .. " | IP: " .. net.ip)

    CITY_LIST = load_cities(CITY_FILE)
    local name_dict = load_dict(DICT_FILE)
    
    local RAW_RANGES = uci:get("iptv_scan", "@settings[0]", "ranges")
    local TASKS = {}
    if type(RAW_RANGES) == "table" then TASKS = RAW_RANGES
    elseif type(RAW_RANGES) == "string" then table.insert(TASKS, RAW_RANGES) end

    for _, val in ipairs(TASKS) do
        local prefix, port = val:match("([^:]+):(%d+)")
        if prefix and port then
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
                            name = cname, url = PLAY_PREFIX .. key,
                            cat_full = cat .. "-" .. q, sort_key = cat .. q .. cname
                        })
                        log("  >> [√] " .. cname .. " [" .. q .. "]")
                    end
                end
                udp:close()
            end
            table.insert(range_stats, { range = val, found = r_found })
        end
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
    local f_txt = io.open(OUTPUT_TXT, "w")
    local bom = "\239\187\191"
    if f_m3u then f_m3u:write(string.format('#EXTM3U x-tvg-url="%s"\n', EPG_URL)) end
    -- if f_txt then f_txt:write(bom) end

    local last_cat = ""
    for _, item in ipairs(scan_results) do
        local tvg_name = get_pure_tvg_name(item.name)
        if f_m3u then 
            f_m3u:write(string.format('#EXTINF:-1 tvg-name="%s" group-title="%s",%s\n%s\n', 
                tvg_name, item.cat_full, item.name, item.url)) 
        end
        if f_txt then
            if item.cat_full ~= last_cat then f_txt:write("\n" .. item.cat_full .. ",#genre#\n") last_cat = item.cat_full end
            f_txt:write(item.name .. "," .. item.url .. "\n")
        end
    end

    if f_m3u then f_m3u:close() end
    if f_txt then f_txt:close() end
    
    log("\n--------------- 统计报告 ---------------")
    log("扫描耗时: " .. os.difftime(os.time(), start_time) .. " 秒")
    log("总计发现有效频道: " .. total_found)
    for _, res in ipairs(range_stats) do 
        log("  - 网段 [" .. res.range .. "] : 发现 " .. res.found .. " 个频道") 
    end
    log("===========================================")
end

-- ================= 主执行逻辑 =================

local function main()
    if not acquire_lock() then
        log("\n[拒绝] 检测到扫描任务已在运行中(PID 锁激活)，请勿重复启动。")
        return
    end

    local status, err = pcall(run_scan)
    if not status then
        log("\n[致命错误] 脚本崩溃: " .. tostring(err))
    end

    release_lock()
end

main()
