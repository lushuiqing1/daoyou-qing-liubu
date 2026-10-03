# 战斗反馈素材

1.2.1 的剑气、命中笔触、法术圆环、盾形、退场与登场均由原生 Godot 绘制与 Tween 动画实现，见 `scripts/combat_effect.gd`、`scripts/game_ui.gd`。沿用现有独立角色与怪物插画，没有整屏静态界面、人物姓名贴图或新字体文件。

`assets/audio/` 六个短音效为本项目原创本地合成：swing（挥剑）、impact（命中）、defeat（击破）、entry（登场／蓄力）、heal（恢复）、guard（护盾）。由固定随机噪声与正弦波生成，PCM WAV、22050 Hz、单声道、16 bit，时长0.13–0.33秒。不含外部录音、语音、音乐采样或第三方素材。生成过程保存在工作区 `outputs/upgrade-godot-combat-feedback.py`。

音量使用运行时 AudioStreamPlayer 调整；设置中的“战斗音效”直接控制原有 sound 存档字段。“减少动态效果”关闭飞行、前冲与震动，保留静态命中、短暂颜色提示、血条变化和接战提示。
