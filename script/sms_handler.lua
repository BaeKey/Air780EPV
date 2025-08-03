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
-- {"tz":32,"min":37,"seqNum":0,"refNum":0,"year":25,"sec":6,"maxNum":0,"mon":8,"hour":11,"day":3}
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

-- 检测是否以"【"开头（UTF-8安全）
local function starts_with_bracket(text)
    return text:match("^【") ~= nil
end

-- 检测是否以"】"结尾（UTF-8安全）
local function ends_with_bracket(text)
    return text:match("】$") ~= nil
end

-- 智能排序：先按时间戳，时间戳相同时特殊处理【】符号
local function smart_sort_messages(messages, has_bracket_start, has_bracket_end)
    -- 先按时间戳排序
    table.sort(messages, function(a, b)
        if a.timestamp ~= b.timestamp then
            return a.timestamp < b.timestamp
        end
        -- 时间戳相同，按index排序
        return a.index < b.index
    end)
    
    -- 如果没有特殊符号，直接返回时间戳排序结果
    if not has_bracket_start and not has_bracket_end then
        return messages
    end
    
    -- 按时间戳分组
    local time_groups = {}
    local current_time = nil
    local current_group = nil
    
    for _, msg in ipairs(messages) do
        if msg.timestamp ~= current_time then
            current_time = msg.timestamp
            current_group = {}
            table.insert(time_groups, {
                timestamp = current_time,
                messages = current_group
            })
        end
        table.insert(current_group, msg)
    end
    
    -- 对每个时间组进行特殊排序
    local result = {}
    for _, group in ipairs(time_groups) do
        if #group.messages == 1 then
            -- 单条消息直接添加
            table.insert(result, group.messages[1])
        else
            -- 多条消息需要特殊排序
            local start_msgs = {}  -- 所有【开头的消息
            local end_msgs = {}    -- 所有】结尾的消息
            local middle_msgs = {} -- 中间的消息
            
            -- 分类消息
            for _, msg in ipairs(group.messages) do
                local is_start = starts_with_bracket(msg.content)
                local is_end = ends_with_bracket(msg.content)
                
                if is_start and is_end then
                    -- 既是开头又是结尾，视为完整消息，放在开头处理
                    table.insert(start_msgs, msg)
                elseif is_start then
                    table.insert(start_msgs, msg)
                elseif is_end then
                    table.insert(end_msgs, msg)
                else
                    table.insert(middle_msgs, msg)
                end
            end
            
            -- 按顺序添加：所有开头 + 中间 + 所有结尾
            -- 开头消息按缓存顺序（index）排序
            table.sort(start_msgs, function(a, b) return a.index < b.index end)
            for _, msg in ipairs(start_msgs) do
                table.insert(result, msg)
            end
            
            -- 中间消息按缓存顺序排序
            table.sort(middle_msgs, function(a, b) return a.index < b.index end)
            for _, msg in ipairs(middle_msgs) do
                table.insert(result, msg)
            end
            
            -- 结尾消息按缓存顺序排序
            table.sort(end_msgs, function(a, b) return a.index < b.index end)
            for _, msg in ipairs(end_msgs) do
                table.insert(result, msg)
            end
        end
    end
    
    return result
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

    -- 智能排序：先按时间戳，时间戳相同时特殊处理【】符号
    local sorted_messages = smart_sort_messages(buffer.messages, buffer.has_bracket_start, buffer.has_bracket_end)
    
    local merged_content = ""
    for i, msg in ipairs(sorted_messages) do
        merged_content = merged_content .. msg.content
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
            index = buffer.msg_counter + 1  -- 用于排序的接收顺序
        })
        buffer.msg_counter = buffer.msg_counter + 1
        buffer.latest_metas = metas
        buffer.last_update = now_ts

        if starts_with_bracket(sms_content) then
            buffer.has_bracket_start = true
        end
        if ends_with_bracket(sms_content) then
            buffer.has_bracket_end = true
        end

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
            timer_id = sys.timerStart(handle_buffer, WAIT_WINDOW * 1000, sender_number, "timeout"),
            has_bracket_start = starts_with_bracket(sms_content),
            has_bracket_end = ends_with_bracket(sms_content)
        }
    end
end

return sms_handler
