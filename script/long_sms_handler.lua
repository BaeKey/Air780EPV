local long_sms_handler = {}

local long_sms_buffer = {}

local CONFIG = {
    TIMEOUT_SEC = 30,          -- 30秒
    MAX_BUFFER_SIZE = 20,
    CLEANUP_INTERVAL_SEC = 300, -- 300秒 = 5分钟
    MAX_AGE_SEC = 120          -- 120秒 = 2分钟
}

-- 获取当前时间（秒）
local function now()
    return os.time()
end

local function clear_long_sms_buffer(phone_number, sms_id)
    local entry = long_sms_buffer[phone_number] and long_sms_buffer[phone_number][sms_id]
    if entry then
        if entry.timeout_timer then
            sys.timerStop(handle_timeout, phone_number, sms_id, entry.callback)
        end
        long_sms_buffer[phone_number][sms_id] = nil
        if next(long_sms_buffer[phone_number]) == nil then
            long_sms_buffer[phone_number] = nil
        end
    end
end

local function assemble_and_send_long_sms(phone_number, sms_id, callback)
    local buffer_entry = long_sms_buffer[phone_number] and long_sms_buffer[phone_number][sms_id]
    if not buffer_entry then return end

    local parts = buffer_entry.parts
    local content_parts = {}
    local first_time, first_metas

    for i = 1, buffer_entry.total_parts do
        local part = parts[i]
        if not part then
            log.warn("long_sms", "缺少片段", phone_number, sms_id, i)
            -- 允许不完整也拼接
        else
            table.insert(content_parts, part.content)
            if i == 1 then
                first_time = part.time
                first_metas = part.metas
            end
        end
    end

    local full_content = table.concat(content_parts)
    clear_long_sms_buffer(phone_number, sms_id)

    if callback then
        local ok, err = pcall(callback, phone_number, full_content, first_metas, first_time, true)
        if not ok then log.error("long_sms", "回调异常", err) end
    end
end

function handle_timeout(phone_number, sms_id, callback)
    local entry = long_sms_buffer[phone_number] and long_sms_buffer[phone_number][sms_id]
    if not entry then return end

    local received = 0
    for _, v in pairs(entry.parts) do received = received + 1 end

    log.warn("long_sms", string.format("超时未收全: %s ID: %s (%d/%d)", phone_number, sms_id, received, entry.total_parts))
    assemble_and_send_long_sms(phone_number, sms_id, callback)
end

local function cleanup_expired_buffers()
    local now_sec = now()
    local total_count, cleaned_count = 0, 0
    local candidates = {}

    for phone, sms_map in pairs(long_sms_buffer) do
        for sms_id, entry in pairs(sms_map) do
            total_count = total_count + 1
            local age = now_sec - (entry.create_time or now_sec)
            if age > CONFIG.MAX_AGE_SEC then
                log.info("long_sms", "清理过期:", phone, sms_id, age)
                clear_long_sms_buffer(phone, sms_id)
                cleaned_count = cleaned_count + 1
            else
                table.insert(candidates, {phone = phone, sms_id = sms_id, age = age})
            end
        end
    end

    if total_count - cleaned_count > CONFIG.MAX_BUFFER_SIZE then
        table.sort(candidates, function(a, b) return a.age > b.age end)
        local over = total_count - math.floor(CONFIG.MAX_BUFFER_SIZE * 0.7)
        for i = 1, over do
            clear_long_sms_buffer(candidates[i].phone, candidates[i].sms_id)
            cleaned_count = cleaned_count + 1
        end
    end

    if cleaned_count > 0 then
        log.info("long_sms", "清理完成", cleaned_count)
    end
end

-- 判断是否是长短信
local function is_long_sms(metas)
    return metas and metas.long and metas.long.total and metas.long.total > 1
end

local function get_long_sms_info(metas)
    if not is_long_sms(metas) then return nil end
    local id = metas.long.id
    if not id then
        id = tostring(metas.recv_tick or now()) .. "_" .. metas.long.current
    end
    return {
        total_parts = metas.long.total,
        current_part = metas.long.current,
        sms_id = id
    }
end

function long_sms_handler.process_sms(sender_number, sms_content, metas, callback)
    local time = string.format("%d/%02d/%02d %02d:%02d:%02d", metas.year + 2000, metas.mon, metas.day, metas.hour, metas.min, metas.sec)

    if not is_long_sms(metas) then
        log.info("sms", "普通短信", sender_number, time)
        if callback then callback(sender_number, sms_content, metas, time, false) end
        return
    end

    local info = get_long_sms_info(metas)
    if not info then
        log.error("long_sms", "无法解析长短信")
        return
    end

    log.info("long_sms", string.format("收到长短信片段: %s ID: %s [%d/%d]", sender_number, info.sms_id, info.current_part, info.total_parts))

    long_sms_buffer[sender_number] = long_sms_buffer[sender_number] or {}
    local buffer = long_sms_buffer[sender_number][info.sms_id]

    if not buffer then
        buffer = {
            parts = {},
            total_parts = info.total_parts,
            create_time = now(),
            callback = callback
        }
        long_sms_buffer[sender_number][info.sms_id] = buffer
        sys.timerStart(handle_timeout, CONFIG.TIMEOUT_SEC * 1000, sender_number, info.sms_id, callback)
        buffer.timeout_timer = true
    end

    if buffer.parts[info.current_part] then
        log.warn("long_sms", "重复片段", sender_number, info.sms_id, info.current_part)
        return
    end

    buffer.parts[info.current_part] = {
        id = info.current_part,
        content = sms_content,
        time = time,
        metas = metas
    }

    local count = 0
    for _ in pairs(buffer.parts) do count = count + 1 end
    log.debug("long_sms", string.format("缓存进度 %d/%d", count, buffer.total_parts))

    if count >= buffer.total_parts then
        log.info("long_sms", "已收齐所有片段", sender_number, info.sms_id)
        assemble_and_send_long_sms(sender_number, info.sms_id, callback)
    end

    if math.random(1, 10) == 1 then
        cleanup_expired_buffers()
    end
end

function long_sms_handler.start_cleanup_task()
    sys.timerLoopStart(cleanup_expired_buffers, CONFIG.CLEANUP_INTERVAL_SEC * 1000)
    log.info("long_sms", "启动定期清理:", CONFIG.CLEANUP_INTERVAL_SEC, "秒")
end

return long_sms_handler