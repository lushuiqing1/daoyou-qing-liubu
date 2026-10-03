# 六项试炼获章操作重放

记录位于tests/trial_replays，由固定角色与seed630101至630106通过合法swap/card/endTurn求解。固定配置逐项见CONTENT-ROADMAP.md。

在源码项目目录，用已验证的Godot4.7.2 console执行：

```powershell
Godot --headless --path . --script tests/trial_runner.gd
```

测试从正式TrialSession初始化，逐个提交记录的动作，验证每步状态、最终条件、随机状态和交换数；不导入JSON里的任意战斗状态、不修改棋盘/气血/墨或伪造获章计数。仅使用隔离测试路径，真实progress-v2/trial-v1均不读写。具体通过项与实际结果见verification/trials-1.5.0.json及REPORT.md。

记录证明六项获章条件可达成，不代表最少步骤或人类胜率。守阵的返墨只在敌方实际击破正数护盾时计入，自然消散不算。重复同一试炼保留固定初始随机种子，可以自行学习与复现。