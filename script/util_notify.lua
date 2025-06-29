    local util_notify = {}

    -- 消息队列
    local msg_queue = {}

    local function urlencodeTab(params)
        local msg = {}
        for k, v in pairs(params) do
            table.insert(msg, string.urlEncode(k) .. "=" .. string.urlEncode(v))
            table.insert(msg, "&")
        end
        table.remove(msg)
        return table.concat(msg)
    end

    local notify = {
        -- 发送到企业微信
        ["wecom"] = function(msg)
            return qyapi.send_message(msg)
        end,
        -- 发送到 bark
        ["bark"] = function(msg)
            if config.BARK_API == nil or config.BARK_API == "" then
                log.error("util_notify", "未配置 `config.BARK_API`")
                return
            end
            if config.BARK_KEY == nil or config.BARK_KEY == "" then
                log.error("util_notify", "未配置 `config.BARK_KEY`")
                return
            end

            local header = {
                ["Content-Type"] = "application/x-www-form-urlencoded"
            }
            local body = {
                body = msg
            }
            local url = config.BARK_API .. "/" .. config.BARK_KEY

            log.info("util_notify", "POST", url)
            return util_http.fetch(nil, "POST", url, header, urlencodeTab(body))
        end
    }

    --- 发送通知
    -- @param msg 消息内容
    -- @param channel 通知渠道
    -- @return true: 无需重发, false: 需要重发
    function util_notify.send(msg, channel)
        log.info("util_notify.send", "发送通知", channel)

        -- 判断消息内容 msg
        if type(msg) ~= "string" then
            log.error("util_notify.send", "发送通知失败", "参数类型错误", type(msg))
            return true
        end
        if msg == "" then
            log.error("util_notify.send", "发送通知失败", "消息为空")
            return true
        end

        -- 判断通知渠道 channel
        if channel and notify[channel] == nil then
            log.error("util_notify.send", "发送通知失败", "未知通知渠道", channel)
            return true
        end

        -- 发送通知
        local code, headers, body = notify[channel](msg)
        if code == nil then
            log.info("util_notify.send", "发送通知失败, 无需重发", "code:", code, "body:", body)
            return true
        end
        if code == -6 then
            -- 发生在 url 过长时, 重发也不会成功
            log.info("util_notify.send", "发送通知失败, 无需重发", "code:", code, "body:", body)
            return true
        end
        if code == 200 then
            -- http 2xx 成功
            log.info("util_notify.send", "发送通知成功", "code:", code, "body:", body)
            return true
        end
        log.error("util_notify.send", "发送通知失败, 等待重发", "code:", code, "body:", body)
        return false
    end

    --- 添加到消息队列
    -- @param msg 消息内容
    -- @param channels 通知渠道
    function util_notify.add(msg, channels)
        if type(msg) == "table" then
            msg = table.concat(msg, "\n")
        end

        channels = channels or config.NOTIFY_TYPE

        if type(channels) ~= "table" then
            channels = {channels}
        end

        for _, channel in ipairs(channels) do
            table.insert(msg_queue, {channel = channel, msg = msg, retry = 0})
        end
        sys.publish("NEW_MSG")
        log.debug("util_notify.add", "添加到消息队列, 当前队列长度:", #msg_queue)
    end

    -- 轮询消息队列
    -- 发送成功则从消息队列中删除
    -- 发送失败则等待下次轮询
    local function poll()
        local item, result
        while true do
            -- 消息队列非空, 且网络已注册
            if next(msg_queue) ~= nil and mobile.status() == 1 then
                log.debug("util_notify.poll", "轮询消息队列中, 当前队列长度:", #msg_queue)

                item = msg_queue[1]
                table.remove(msg_queue, 1)

                if item.retry > (config.NOTIFY_RETRY_MAX or 100) then
                    log.error("util_notify.poll", "超过最大重发次数", "msg:", item.msg)
                else
                    result = util_notify.send(item.msg, item.channel)
                    item.retry = item.retry + 1

                    if not result then
                        -- 发送失败, 移到队尾
                        table.insert(msg_queue, item)
                        sys.wait(5000)
                    end
                end
                sys.wait(50)
            else
                sys.waitUntil("NEW_MSG", 1000 * 10)
            end
        end
    end

    sys.taskInit(poll)

    return util_notify
