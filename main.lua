PROJECT = "air780epv_forwarder"
VERSION = "0.0.1"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require "sysplus" -- http库需要这个sysplus

-- 添加硬狗防止程序卡死
wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)

-- 设置 DNS
socket.setDNS(nil, 1, "119.29.29.29")
socket.setDNS(nil, 2, "223.5.5.5")

-- 开启 IPv6
mobile.ipv6(true)

-- SIM 自动恢复时间(单位: 毫秒), 周期性获取小区信息(单位: 毫秒), 搜索小区时最大搜索时间(单位: 秒)
-- 网络遇到严重故障时尝试自动恢复，定时检测网络是否正常(单位: 毫秒)
mobile.setAuto(10000, 30000, 8, true, 60000)

log.info("main", "短信转发服务工作中...")

-- 加载自定义模块
config = require "config"
util_http = require "util_http"
util_notify = require "util_notify"

-- 短信接收回调
sms.setNewSmsCb(
    -- num 手机号码
    -- txt 文本内容
    -- metas 短信的元数据,例如发送的时间,长短信编号
    function(sender_number, sms_content, m)
        -- 格式：2025/05/15 15:30:22
        local time = string.format("%d/%02d/%02d %02d:%02d:%02d", m.year + 2000, m.mon, m.day, m.hour, m.min, m.sec)
        log.info("smsCallback", time, sender_number, sms_content)

        -- 短信控制（远程控制设备发送短信给指定号码）
        local is_sms_ctrl = false
        local pattern = "^" .. config.SMS_CTRL_IDENTIFIER .. ",(+?%d+),(.+)$"
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
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!