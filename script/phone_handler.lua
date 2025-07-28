local phone_handler = {}

-- 模块状态
local state = {
    ring_count = 0,
    current_number = nil,
    is_initialized = false,
    notification_sent = false  -- 新增：标记是否已发送通知
}

-- 重置通话状态
local function reset_call_state()
    state.ring_count = 0
    state.current_number = nil
    state.notification_sent = false  -- 重置通知状态
end

-- 发送来电通知
function phone_handler.send(phone_number)
    if not phone_number or phone_number == "" then
        log.warn("phone_handler", "电话号码为空，跳过通知")
        return false
    end

    local timestamp = os.time()
    local formatted_time = os.date("%Y/%m/%d %H:%M:%S", timestamp)

    if util_notify and util_notify.add then
        util_notify.add({
            "#PHONE",
            "",
            phone_number .. " 给您来电",
            "",
            "来电时间: " .. formatted_time
        })
        log.info("phone_handler", "已发送来电通知:", phone_number)
        return true
    else
        log.error("phone_handler", "util_notify 模块不可用")
        return false
    end
end

-- 处理来电事件
local function handle_incoming_call()
    local current_num = cc.lastNum()
    
    if not current_num or current_num == "" then
        log.warn("phone_handler", "无法获取来电号码")
        return
    end
    
    -- 如果是新的来电，重置计数和通知状态
    if state.current_number ~= current_num then
        log.info("phone_handler", "检测到新来电:", current_num)
        reset_call_state()
        state.current_number = current_num
    end
    
    state.ring_count = state.ring_count + 1
    log.info("phone_handler", string.format("来电响铃 %d 次: %s", state.ring_count, current_num))
    
    -- 响铃3次且未发送过通知时才发送通知
    if state.ring_count >= 3 and not state.notification_sent then
        if phone_handler.send(current_num) then
            state.notification_sent = true  -- 标记已发送通知，但不重置其他状态
            log.info("phone_handler", "已为号码 " .. current_num .. " 发送通知，不再重复发送")
        end
    end
end

-- 处理通话状态变化
local function handle_call_state(call_state)
    log.info("phone_handler", "通话状态变化:", call_state)
    
    if call_state == "READY" then
        sys.publish("CC_READY")
        reset_call_state()  -- 通话准备就绪时重置状态
        
    elseif call_state == "INCOMINGCALL" then
        handle_incoming_call()
        
    elseif call_state == "DISCONNECTED" or call_state == "IDLE" then
        -- 通话结束时重置状态
        log.info("phone_handler", "通话结束，重置状态")
        reset_call_state()
    end
end

-- 初始化模块
function phone_handler.init()
    if state.is_initialized then
        log.warn("phone_handler", "模块已经初始化，跳过重复初始化")
        return true
    end
    
    log.info("phone_handler", "开始初始化电话功能模块")
    
    -- 初始化通话功能
    local init_result = cc.init(0)
    if not init_result then
        log.error("phone_handler", "通话功能初始化失败")
        return false
    end
    
    -- 重置初始状态
    reset_call_state()
    
    -- 监听通话事件
    sys.subscribe("CC_IND", handle_call_state)
    
    state.is_initialized = true
    log.info("phone_handler", "电话功能模块初始化完成")
    return true
end

return phone_handler