import json

with open('Sources/SparkleRecorder/Localizable.xcstrings', 'r') as f:
    data = json.load(f)

new_keys = {
    "Disable Action": "禁用动作",
    "Enable Action": "启用动作",
    "Play From Here": "从这里开始播放",
    "Play This Action Only": "仅播放此动作",
    "Playing preview…": "正在播放预览…"
}

for en_key, zh_value in new_keys.items():
    if en_key not in data["strings"]:
        data["strings"][en_key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {
                    "stringUnit": {
                        "state": "translated",
                        "value": en_key
                    }
                },
                "zh-Hans": {
                    "stringUnit": {
                        "state": "translated",
                        "value": zh_value
                    }
                }
            }
        }

with open('Sources/SparkleRecorder/Localizable.xcstrings', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
