local sms_handler = {}

local sms_buffer = {}

-- 配置参数
local WAIT_WINDOW = 3  -- 等待窗口（秒）
local MAX_CONTENT_LENGTH = 1024  -- 合并后单条消息最大长度 1KB
local MAX_BUFFER_SIZE = 20       -- 最大同时缓存号码数量

-- 格式化时间
local function format_time(metas)
    return string.format("%d/%02d/%02d %02d:%02d:%02d", 
        metas.year + 2000, metas.mon, metas.day, metas.hour, metas.min, metas.sec)
end

-- 将时间元信息转换为时间戳用于排序
local function metas_to_timestamp(metas)
    -- metas是table，包含year, mon, day, hour, min, sec等字段
    return os.time({
        year = metas.year + 2000,
        month = metas.mon,
        day = metas.day,
        hour = metas.hour,
        min = metas.min,
        sec = metas.sec
    })
end

-- 清理缓冲区
local function clear_buffer(sender_number)
    local buffer = sms_buffer[sender_number]
    if buffer then
        if buffer.timer_id then
            sys.timerStop(buffer.timer_id)
        end
        sms_buffer[sender_number] = nil
    end
end

-- 处理缓存（因超时或超长）
local function handle_buffer(sender_number, reason)
    local buffer = sms_buffer[sender_number]
    if not buffer then return end

    log.info("sms_handler", "处理缓冲短信:", sender_number, "原因:", reason)

    -- 按时间排序后拼接内容
    local merged_content = ""
    if #buffer.messages > 0 then
        table.sort(buffer.messages, function(a, b)
            if a.timestamp == b.timestamp then
                -- 时间相同时按缓存顺序（index）
                return a.index < b.index
            end
            return a.timestamp < b.timestamp
        end)
        
        for i, msg in ipairs(buffer.messages) do
            merged_content = merged_content .. msg.content
        end
    end

    sys.taskInit(function()
        if buffer.callback then
            local ok, err = pcall(buffer.callback, sender_number, merged_content, buffer.latest_metas, buffer.first_time, reason)
            if not ok then
                log.error("sms_handler", "回调异常", err)
            end
        end
    end)

    clear_buffer(sender_number)
end

-- 检查缓冲区是否超出限制
local function check_buffer_limit()
    local count = 0
    for _ in pairs(sms_buffer) do
        count = count + 1
    end
    if count >= MAX_BUFFER_SIZE then
        -- 找出最久未更新的号码
        local oldest_number, oldest_time
        for number, buffer in pairs(sms_buffer) do
            if not oldest_time or buffer.last_update < oldest_time then
                oldest_time = buffer.last_update
                oldest_number = number
            end
        end
        if oldest_number then
            log.warn("sms_handler", "缓冲区满，淘汰最老缓存:", oldest_number)
            handle_buffer(oldest_number, "timeout")
        end
    end
end

-- 计算当前缓冲区总长度
local function calculate_buffer_length(buffer)
    local total_length = 0
    for _, msg in ipairs(buffer.messages) do
        total_length = total_length + #msg.content
    end
    return total_length
end

-- 主要处理函数
function sms_handler.process_sms(sender_number, sms_content, metas, callback)
    local time_str = format_time(metas)
    local now_ts = os.time()
    local msg_timestamp = metas_to_timestamp(metas)
    local buffer = sms_buffer[sender_number]

    if buffer then
        -- 同号码短信 → 合并
        log.info("sms_handler", "合并同号码短信:", sender_number)
        
        -- 添加新消息到缓冲区
        table.insert(buffer.messages, {
            content = sms_content,
            timestamp = msg_timestamp,
            index = buffer.msg_counter + 1  -- 用于时间相同时的排序
        })
        buffer.msg_counter = buffer.msg_counter + 1
        buffer.latest_metas = metas
        buffer.last_update = now_ts

        -- 检查是否超长
        local total_length = calculate_buffer_length(buffer)
        if total_length > MAX_CONTENT_LENGTH then
            handle_buffer(sender_number, "length")
            -- 立即处理新消息作为新缓冲
            sms_handler.process_sms(sender_number, sms_content, metas, callback)
            return
        end

        -- 重置定时器
        sys.timerStop(buffer.timer_id)
        buffer.timer_id = sys.timerStart(handle_buffer, WAIT_WINDOW * 1000, sender_number, "timeout")

    else
        -- 新号码短信
        log.info("sms_handler", "新号码短信，放入缓冲:", sender_number)

        -- 检查是否超长
        if #sms_content > MAX_CONTENT_LENGTH then
            log.warn("sms_handler", "单条短信过长，立即处理:", sender_number)
            sys.taskInit(function()
                if callback then
                    local ok, err = pcall(callback, sender_number, sms_content, metas, time_str, "length")
                    if not ok then
                        log.error("sms_handler", "回调异常", err)
                    end
                end
            end)
            return
        end

        -- 检查缓冲区限制
        check_buffer_limit()

        -- 添加到缓冲区
        sms_buffer[sender_number] = {
            messages = {{
                content = sms_content,
                timestamp = msg_timestamp,
                index = 1
            }},
            msg_counter = 1,
            latest_metas = metas,
            first_time = time_str,
            last_update = now_ts,
            callback = callback,
            timer_id = sys.timerStart(handle_buffer, WAIT_WINDOW * 1000, sender_number, "timeout")
        }
    end
end

return sms_handler