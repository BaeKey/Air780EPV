local qyapi = {}

local access_token = nil
local token_fetch_time = 0  -- access_token获取时间戳，单位：秒
local token_expires_in = 0  -- 缓存有效期，单位：秒

-- 获取当前时间的时间戳（秒）
local function now()
    return os.time()
end

-- 判断 access_token 是否过期
local function is_token_expired()
    if not access_token or token_fetch_time == 0 then
        return true
    end
    local elapsed = now() - token_fetch_time  -- 秒
    return elapsed >= token_expires_in
end

local function clear_expired_token()
    if is_token_expired() then
        access_token = nil
        token_fetch_time = 0
        token_expires_in = 0
        log.info("lib_qyapi", "清理过期的access_token")
    end
end

function qyapi.get_access_token(force_refresh)
    local corp_id = config.WECOM_CORPID
    local corp_secret = config.WECOM_CORPSECRET
    local agent_id = config.WECOM_AGENTID

    if not corp_id or not corp_secret or not agent_id then
        return nil, "WECOM_CORPID/WECOM_CORPSECRET/WECOM_AGENTID 未配置"
    end

    clear_expired_token()

    if not force_refresh and access_token and not is_token_expired() then
        return access_token
    end

    local url = string.format(
        "%s/cgi-bin/gettoken?corpid=%s&corpsecret=%s",
        config.WECOM_URL,
        corp_id,
        corp_secret
    )

    log.info("lib_qyapi", "请求 access_token:", url)

    local headers = {["content-type"] = "application/json"}
    local code, _, body = util_http.fetch(nil, "GET", url, headers, nil)

    if code ~= 200 then
        return nil, "gettoken 请求失败, code=" .. tostring(code)
    end

    local res = json.decode(body or "{}")
    if res.errcode ~= 0 or not res.access_token then
        return nil, "gettoken 响应异常: " .. (res.errmsg or "未知错误")
    end

    access_token = res.access_token
    token_fetch_time = now()
    token_expires_in = (res.expires_in or 7200) - 60  -- 秒单位，提前60秒刷新

    log.info("lib_qyapi", "缓存 access_token，获取时间:", token_fetch_time, "有效期:", token_expires_in, "秒")
    return access_token
end

function qyapi.send_message(msg)
    local function do_send(token)
        local url = config.WECOM_URL .. "/cgi-bin/message/send?access_token=" .. token
        local headers = {["content-type"] = "application/json; charset=utf-8"}
        local body = {
            touser  = config.WECOM_TOUSER or "@all",
            agentid = config.WECOM_AGENTID,
            msgtype = config.WECOM_MSGTYPE or "text",
            text    = { content = msg }
        }
        local json_data = json.encode(body):gsub("\\b", "\\n")
        return util_http.fetch(nil, "POST", url, headers, json_data)
    end

    local token, err = qyapi.get_access_token(false)
    if not token then return nil, err end

    local code, _, body = do_send(token)

    if code == 200 and body then
        local res = json.decode(body or "{}")
        if res.errcode == 42001 or res.errcode == 40014 then
            log.warn("lib_qyapi", "access_token 可能过期，尝试刷新并重试")
            token = qyapi.get_access_token(true)
            if token then
                return do_send(token)
            else
                return nil, "token 刷新失败"
            end
        end
    end

    return code, nil, body
end

return qyapi