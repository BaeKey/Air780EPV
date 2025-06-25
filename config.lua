return {
    -- 通知类型
    NOTIFY_TYPE = {"bark"},

    BARK_API = "https://api.day.app",
    BARK_KEY = "",

    -- 开机通知 (会消耗流量)
    BOOT_NOTIFY = true,
    -- 通知最大重发次数
    NOTIFY_RETRY_MAX = 3,
    -- 开启低功耗模式, USB 断开连接无法查看日志, RNDIS 网卡会断开
    LOW_POWER_MODE = false,
}
