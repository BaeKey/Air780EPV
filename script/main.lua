PROJECT = "air780epv_forwarder"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

sys = require("sys")
require "sysplus"

wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)

socket.setDNS(nil, 1, "119.29.29.29")
socket.setDNS(nil, 2, "223.5.5.5")

mobile.ipv6(true)
mobile.setAuto(10000, 30000, 8, true, 60000)

log.info("main", "短信转发服务工作中...")

config = require "config"
util_http = require "util_http"
util_notify = require "util_notify"
qyapi = require "lib_qyapi"
sms_handler = require("sms_handler")
phone_handler = require("phone_handler")

-- 短信处理回调函数
local function handle_complete_sms(sender_number, sms_content, metas, time, is_assembled_long_sms)
    log.info("smsCallback", time, sender_number, sms_content)
    
    if is_assembled_long_sms then
        log.info("smsCallback", "这是组装后的长短信")
    end

    -- 短信控制（远程控制设备发送短信给指定号码）
    local is_sms_ctrl = false
    local pattern = "^" .. config.SMS_CTRL_IDENTIFIER .. ",(%+?%d+),(.+)$"
    local receiver_number, sms_content_to_be_sent = sms_content:match(pattern)
    
    -- 如果匹配成功，提取接收号码和短信内容并进行转发
    receiver_number, sms_content_to_be_sent = receiver_number or "", sms_content_to_be_sent or ""
    if sms_content_to_be_sent ~= "" and receiver_number ~= "" and #receiver_number >= 5 and #receiver_number <= 20 then
        sms.send(receiver_number, sms_content_to_be_sent)
        is_sms_ctrl = true
    end

    -- 发送通知
    util_notify.add(
        {
            "#SMS" .. (is_sms_ctrl and " #CTRL" or ""),
            "",
            sms_content,
            "",
            "发件号码: " .. sender_number,
            "发件时间: " .. time
        }
    )
end

-- 设置短信回调
sms.setNewSmsCb(
    function(sender_number, sms_content, metas)
        -- 使用短信处理模块处理短信
        sms_handler.process_sms(sender_number, sms_content, metas, handle_complete_sms)
    end
)

-- 创建并启动一个任务协程
sys.taskInit(
    function()
        -- 等待网络环境准备就绪
        local result, data = sys.waitUntil("IP_READY", 30000)
        if result then
            log.info("Network Ready", data)
        else
            log.error("Timeout")
        end
        
        -- 初始化电话功能模块
        phone_handler.init()
        local cc_ready = sys.waitUntil("CC_READY", 10000)
        if cc_ready then
            log.info("电话功能已准备就绪")
        else
            log.warn("电话功能初始化超时，可能影响通话功能")
        end

        -- 开机通知
        if config.BOOT_NOTIFY then
            util_notify.add("设备已成功开机")
        end

        -- 开启低功耗模式
        if config.LOW_POWER_MODE then
            sys.wait(1000 * 15)
            log.warn("main", "即将关闭 usb 电源, 如需查看日志请在配置中关闭低功耗模式")
            sys.wait(1000 * 5)
            gpio.setup(23, nil)
            gpio.close(33)
            pm.power(pm.USB, false) -- 关闭 USB
            pm.power(pm.GPS, false)
            pm.power(pm.GPS_ANT, false)
            pm.power(pm.DAC_EN, false)
            pm.force(pm.LIGHT) -- 进入休眠
        end
    end
)

-- 用户代码已结束---------------------------------------------
sys.run()