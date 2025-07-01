-- 短信处理器模块
local sms_handler = {}

-- 长短信缓存表，结构：{手机号: {短信ID: 缓存条目}}
local long_sms_buffer = {}

-- 配置参数
local CONFIG = {
    TIMEOUT_SEC = 30,          -- 超时时间：30秒，如果在此时间内未收齐所有片段则强制拼接并清理
}

-- 获取当前时间戳（秒）
local function now()
    return os.time()
end

-- 清除指定的长短信缓存条目（发送完成后立即清理内存）
-- @param phone_number: 手机号码
-- @param sms_id: 短信ID
local function clear_long_sms_buffer(phone_number, sms_id)
    local entry = long_sms_buffer[phone_number] and long_sms_buffer[phone_number][sms_id]
    if entry then
        -- 如果存在超时定时器，则停止它
        if entry.timeout_timer then
            sys.timerStop(handle_timeout, phone_number, sms_id, entry.callback)
        end
        -- 删除缓存条目，立即释放内存
        long_sms_buffer[phone_number][sms_id] = nil
        -- 如果该手机号下没有更多短信了，删除整个手机号条目
        if next(long_sms_buffer[phone_number]) == nil then
            long_sms_buffer[phone_number] = nil
        end
    end
end

-- 拼接并发送完整的长短信（发送后立即清理内存）
-- @param phone_number: 手机号码
-- @param sms_id: 短信ID
-- @param callback: 回调函数
local function assemble_and_send_long_sms(phone_number, sms_id, callback)
    local buffer_entry = long_sms_buffer[phone_number] and long_sms_buffer[phone_number][sms_id]
    if not buffer_entry then return end

    local parts = buffer_entry.parts
    local content_parts = {}  -- 存储各片段内容的数组
    local first_time, first_metas  -- 保存第一个片段的时间和元数据

    -- 按顺序拼接所有片段
    for i = 1, buffer_entry.total_parts do
        local part = parts[i]
        if not part then
            -- 如果某个片段缺失，记录警告但继续拼接（允许不完整拼接）
            log.warn("sms_handler", "缺少片段", phone_number, sms_id, i)
        else
            table.insert(content_parts, part.content)
            -- 保存第一个片段的时间和元数据作为整条短信的时间和元数据
            if i == 1 then
                first_time = part.time
                first_metas = part.metas
            end
        end
    end

    -- 拼接所有片段内容
    local full_content = table.concat(content_parts)
    
    -- 【关键】先清除缓存释放内存，再调用回调
    clear_long_sms_buffer(phone_number, sms_id)

    -- 调用回调函数，传递完整的短信内容（第5个参数true表示这是长短信）
    if callback then
        local ok, err = pcall(callback, phone_number, full_content, first_metas, first_time, true)
        if not ok then 
            log.error("sms_handler", "回调异常", err) 
        end
    end
end

-- 处理超时情况的函数
-- 当在指定时间内未收齐所有片段时，强制拼接已收到的片段并清理内存
function handle_timeout(phone_number, sms_id, callback)
    local entry = long_sms_buffer[phone_number] and long_sms_buffer[phone_number][sms_id]
    if not entry then return end

    -- 统计已收到的片段数量
    local received = 0
    for _, v in pairs(entry.parts) do 
        received = received + 1 
    end

    -- 记录超时警告
    log.warn("sms_handler", string.format("超时未收全: %s ID: %s (%d/%d)", 
        phone_number, sms_id, received, entry.total_parts))
    
    -- 强制拼接、发送并清理内存
    assemble_and_send_long_sms(phone_number, sms_id, callback)
end

-- 判断是否是长短信
-- @param metas: 短信元数据
-- @return: 布尔值，true表示是长短信
local function is_long_sms(metas)
    return metas and metas.long and metas.long.total and metas.long.total > 1
end

-- 获取长短信的相关信息
-- @param metas: 短信元数据
-- @return: 包含总片段数、当前片段号、短信ID的表，如果不是长短信则返回nil
local function get_long_sms_info(metas)
    if not is_long_sms(metas) then return nil end
    
    local id = metas.long.id
    -- 如果没有ID，则根据接收时间和当前片段号生成一个ID
    if not id then
        id = tostring(metas.recv_tick or now()) .. "_" .. metas.long.current
    end
    
    return {
        total_parts = metas.long.total,    -- 总片段数
        current_part = metas.long.current, -- 当前片段号
        sms_id = id                        -- 短信ID
    }
end

-- 主要的短信处理函数
-- 短信处理流程：
-- 1. 正常短信：直接调用回调函数处理，无需缓存，立即完成
-- 2. 长短信：缓存片段，收齐后拼接并调用回调，然后立即清理内存
-- @param sender_number: 发送方手机号
-- @param sms_content: 短信内容
-- @param metas: 短信元数据
-- @param callback: 处理完成后的回调函数
function sms_handler.process_sms(sender_number, sms_content, metas, callback)
    -- 格式化时间字符串
    local time = string.format("%d/%02d/%02d %02d:%02d:%02d", 
        metas.year + 2000, metas.mon, metas.day, metas.hour, metas.min, metas.sec)

    -- 【正常短信处理】：直接处理，无需缓存，立即完成
    if not is_long_sms(metas) then
        log.info("sms", "正常短信", sender_number, time)
        if callback then 
            -- 第5个参数false表示这是正常短信
            callback(sender_number, sms_content, metas, time, false) 
        end
        return  -- 正常短信处理完毕，直接返回
    end

    -- 【长短信处理】：需要缓存、拼接、然后清理
    local info = get_long_sms_info(metas)
    if not info then
        log.error("sms_handler", "无法解析长短信")
        return
    end

    log.info("sms_handler", string.format("收到长短信片段: %s ID: %s [%d/%d]", 
        sender_number, info.sms_id, info.current_part, info.total_parts))

    -- 初始化该手机号的缓存
    long_sms_buffer[sender_number] = long_sms_buffer[sender_number] or {}
    local buffer = long_sms_buffer[sender_number][info.sms_id]

    -- 如果是新的长短信，创建缓存条目
    if not buffer then
        buffer = {
            parts = {},                    -- 存储各个片段
            total_parts = info.total_parts, -- 总片段数
            create_time = now(),           -- 创建时间
            callback = callback            -- 回调函数
        }
        long_sms_buffer[sender_number][info.sms_id] = buffer
        
        -- 启动超时定时器（超时后会自动清理）
        sys.timerStart(handle_timeout, CONFIG.TIMEOUT_SEC * 1000, sender_number, info.sms_id, callback)
        buffer.timeout_timer = true
    end

    -- 检查是否是重复片段
    if buffer.parts[info.current_part] then
        log.warn("sms_handler", "重复片段", sender_number, info.sms_id, info.current_part)
        return
    end

    -- 存储当前片段
    buffer.parts[info.current_part] = {
        id = info.current_part,  -- 片段ID
        content = sms_content,   -- 片段内容
        time = time,             -- 时间
        metas = metas            -- 元数据
    }

    -- 统计已收到的片段数量
    local count = 0
    for _ in pairs(buffer.parts) do 
        count = count + 1 
    end
    log.debug("sms_handler", string.format("缓存进度 %d/%d", count, buffer.total_parts))

    -- 如果已收齐所有片段，立即拼接、发送并清理内存
    if count >= buffer.total_parts then
        log.info("sms_handler", "已收齐所有片段", sender_number, info.sms_id)
        assemble_and_send_long_sms(sender_number, info.sms_id, callback)
        -- 注意：assemble_and_send_long_sms函数内部已经调用了clear_long_sms_buffer清理内存
    end
end

-- 返回模块
return sms_handler