# 水墨按钮 · 1.2.2

新增20个独立、无字SVG，源文件在 `assets/ui/buttons/`，原创生成器在 `tools/generate_button_art.py`。宣纸底使用克制的纤维碎纹与淡色叠印，外缘为不规则墨线；朱砂主按钮使用干笔刷痕，选中项带暖纸色与无字小印记。未使用外部素材、语音、字体文件或整屏界面图。

四类按钮：cinnabar（朱砂主要操作）、paper（宣纸次要操作）、jade（青墨辅助操作）、selected（选中术式）。每类包含正常、悬停、按下；不可用状态统一灰纸墨线。另含透明朱砂焦点边、导航晕染与毛笔下划线、设置开关的开／关图标。

背景与边缘接入原生 StyleBoxTexture 九宫格缩放，文字和命中区域仍由真实 Button、CheckButton 控制。文案、禁用原因和所有事件沿用既有数据。不会将按钮或文字烘焙进主城背景，也不改变鼠标、键盘、焦点、血条、棋盘或攻击特效。

纹理丢失时使用原生纯色样式回退，功能与文字继续保留。工具预览 `tools/preview_buttons.gd` 输出 `verification/ink-buttons-style-sheet.png`，为原生控件样式对照，非游戏状态；各页面实际截图前缀为 `ink-buttons-`。

技术依据：[Godot StyleBoxTexture](https://docs.godotengine.org/en/stable/classes/class_styleboxtexture.html)、[CheckButton](https://docs.godotengine.org/en/stable/classes/class_checkbutton.html)。
