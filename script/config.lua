return {
    -- 通知类型wecom, bark
    NOTIFY_TYPE = {"wecom","bark"},

    -- 企业微信应用通知配置
    -- 企业应用的id
    WECOM_AGENTID = "1000001",
    -- 企业ID
    WECOM_CORPID =  "",
    -- 应用的凭证密钥
    WECOM_CORPSECRET = "",
    -- 消息类型，默认text
    WECOM_MSGTYPE = "text",
    -- 指定接收消息的成员，默认@all
    WECOM_TOUSER = "@all",
    -- 企业微信代理API地址
    WECOM_URL = "https://qyapi.weixin.qq.com",

    -- Bark 通知配置
    BARK_API = "https://api.day.app",
    BARK_KEY = "",

    -- 开机通知 (会消耗流量)
    BOOT_NOTIFY = false,
    -- 每日定时重启配置
    -- 是否启用每日定时重启 (true/false)
    DAILY_RESTART_ENABLED = true,
    -- 重启时间，24小时制 (0-23)，默认凌晨3点
    DAILY_RESTART_HOUR = 3,
        
    -- 控制发送短信的标识符，大小写敏感，英文逗号分隔
    -- 比如 #FORD,13567890123,这是一条转发的短信
    SMS_CTRL_IDENTIFIER = "#FORD",
    -- 通知最大重发次数
    NOTIFY_RETRY_MAX = 3,
    -- 开启低功耗模式, USB 断开连接无法查看日志
    LOW_POWER_MODE = false,
}
