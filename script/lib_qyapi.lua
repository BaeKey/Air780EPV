local qyapi = {}

local access_token = nil

function qyapi.get_access_token(force_refresh)
    local corp_id = config.WECOM_CORPID
    local corp_secret = config.WECOM_CORPSECRET
    local agent_id = config.WECOM_AGENTID

    if not corp_id or corp_id == "" or not corp_secret or corp_secret == "" or not agent_id or agent_id == "" then
        log.info("lib_qyapi", "WECOM_CORPID/WECOM_CORPSECRET/WECOM_AGENTID 未配置，无法获取 access_token")
        return nil, "WECOM_CORPID/WECOM_CORPSECRET/WECOM_AGENTID 未配置"
    end

    if access_token and not force_refresh then
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
        local json_data = json.encode(body)
        return util_http.fetch(nil, "POST", url, headers, json_data)
    end

    local token, err = qyapi.get_access_token(false)
    if not token then return nil, err end

    local code, _, body = do_send(token)

    if code == 200 and body then
        local res = json.decode(body or "{}")
        -- 42001	access_token已过期，https://developer.work.weixin.qq.com/document/path/90313
        if res.errcode == 42001 then
            log.warn("lib_qyapi", "access_token 过期或无效，刷新后重试")
            token = qyapi.get_access_token(true)
            if not token then
                return nil, "token 刷新失败"
            end
            return do_send(token)
        end
    end

    return code, nil, body
end

return qyapi
