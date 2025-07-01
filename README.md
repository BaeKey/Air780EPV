## CORE

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

## API

文档地址：https://docs.openluat.com/osapi/core/

![](https://github.com/BaeKey/Air780EPV/blob/main/images/20250629111602.jpg)

## 功能

- 短信转发到 `Bark`、`企业微信应用`

- 来电响铃3声后，通知来电号码
- 自定义短信转发控制符号，比如 `#FORD,13567890123,这是一条转发的短信`

## 其他

来电接通语音回复的功能，使用TTL的话，包含TTL库的固件太大了，设备塞不下

使用audio库，核心固件存在问题，就算测试了最新的 `v2007` 同样存在问题（并且最新的v2007有短信重复发送死机的bug），具体见：[[🐛Bug]: 780EPV拨打电话后播放音频 只有噪音](https://gitee.com/openLuat/LuatOS/issues/IAIQG6)
