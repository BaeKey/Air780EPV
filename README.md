## 说明

### CORE

EC718PV，合宙Air780EPV 核心固件，支持的功能：gpio，wdt，pm，sms，cjson

```json
"component": {
      "@EC718PV": true,
      "@volte": true,
      "gpio": true,
      "wdt": true,
      "pm": true,
      "sms": true,
      "cjson": true,
      "@rev_release_v2002": true
   },
```

在线编译地址：https://luatos.com/zh_cn/my/build.html

经过测试最高只能编译 `V2002` 版本的，仅支持Air780EPV系列

> 仅Air780EPV系列支持(带V字母), 非Air780EPV系列不要选这个,会无法启动

![](https://github.com/BaeKey/Air780EPV/blob/main/images/20250629111602.jpg)

### 功能

- [x] 短信转发到 `Bark`、`企业微信应用`

- [x] 来电响铃3声后，通知来电号码
- [x] 自定义短信转发控制符号，比如 `#FORD,13567890123,这是一条转发的短信`

## 烧录

修改 `script` 目录下 `config.lua` 文件

下载调试工具：https://luatos.com/luatools/download/last

下载后打开，右上角项目管理测试

![](https://github.com/BaeKey/Air780EPV/blob/main/images/Snipaste_2025-08-04_11-15-23.jpg)

创建项目

![](https://github.com/BaeKey/Air780EPV/blob/main/images/Snipaste_2025-08-04_11-20-09.jpg)

## 其他

API文档地址：https://docs.openluat.com/osapi/core/

### 已知的问题

- 部分长短信没有分片标识（应该），我是自己手动合并的，判断依据是2s内的相同号码的短信会自动合并。具体逻辑见：`sms_handler.lua`，可能存在短信顺序错乱的问题
- 部分短信有重复接收的问题，不知道问题在哪里，所以做了去重处理，同样是2s内的短信内容相同会被丢弃
- 大概3天左右会有发不出消息的问题，在发送消息的模块里做了失败重置网络的处理，测试了一次可以正常运行7天，如果还有遇到这个问题的，可能需要在配置里面开启定时重启

来电接通语音回复的功能，使用TTL的话，包含TTL库的固件太大了，设备塞不下

使用audio库，核心固件存在问题，就算测试了最新的 `v2007` 同样存在问题（并且最新的v2007有短信重复发送死机的bug），具体见：[[🐛Bug]: 780EPV拨打电话后播放音频 只有噪音](https://gitee.com/openLuat/LuatOS/issues/IAIQG6)
