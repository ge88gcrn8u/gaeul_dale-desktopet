# 🐿️ DAL-E ·  — macOS Desktop Pet

[![GitHub Release](https://img.shields.io/github/v/release/ge88gcrn8u/gaeul_dale-desktopet?label=Download&color=orange)](https://github.com/ge88gcrn8u/gaeul_dale-desktopet/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-12%2B-blue)]()

> 灵感来自 **IVE 金秋天（GAEUL）** 的官方角色「**DAL-E**」——一只戴着橡果项链的 Q 版松鼠。
> 本项目是粉丝自制的桌面宠物，**非官方周边**。

![DAL-E](squirrel.png)

## 🐿️ 关于 DAL-E

**DAL-E** 是 IVE 官方角色系列 **MINIVE（미니브）** 中，由成员 **金秋天（가을, Gaeul）** 亲手命名的松鼠角色：

- **名字由来**：**다람쥐（松鼠）** ＋ **가을（秋天）** → **DAL-E**
- **形象**：Q 版小松鼠，脖间佩戴 **橡果项链**，呼应松鼠主题
- **MINIVE 系列**：每位成员都有自己的对应角色——安宥真 GANGANJI、秋天 DAL-E、Rei NAORI、张员瑛 CHERRY、LIZ CHEEZ、Leeseo ERANG-E

这个桌面宠物，就是把「秋天的小松鼠 DAL-E」带到你的 macOS 桌面上，陪你工作、记提醒、一起度过每一天。

## ✨ 功能特点

- 🐿️ **Dal-E**：Q 版松鼠造型，大脑袋大眼睛，可爱比例
- 🖥️ **桌面层显示**：始终在桌面图标层，不遮挡应用窗口
- 🖱️ **可拖拽**：点击松鼠并拖拽到屏幕任意位置
- 👆 **互动点击**：点击松鼠 → 温柔“抱抱”动画 + 随机暖心话语（每次不重复）
- 💤 **待机动画**：左眼慵懒眨眼（4-10 秒随机）、摇尾巴（12-22 秒随机）
- 👁️ **真眨眼**：用与脸部同色的眼皮遮罩（`eyelid.png`）实现真正的眨眼——眼皮缓缓盖下 → 闭合休息 → 缓缓睁开（约 1 秒），闭合时有睫毛弧线，睁眼时完全隐形
- 🔘 **右键菜单**：暂停动画、重新显示、对话、提醒花园、提醒、开机启动、退出
- 💬 **对话窗**：温暖圆角气泡 + 圆润字体，DAL-E 在这里说话（韩语 + 中文）
- ⏰ **提醒功能**：一次性 + 重复提醒（每天 / 每周指定星期 / 每月指定日），完成 / 稍后 / 编辑 / 禁用 / 删除
- 🌰 **提醒花园**：卡片式提醒管理页，可爱状态徽章，可编辑 / 删除
- 🔔 **macOS 原生通知**：提醒到点由系统通知，按提醒 ID 去重；创建提醒时会请求通知权限（未开启会提示去系统设置开启），删除 / 完成后自动取消，启动时自动清理残留通知
- 🍂 **鼓励语**：双语治愈文案，按情境触发；点击 / 抱抱时随机抽取（不重复）
- 🚀 **开机启动**：支持 macOS Login Items 自动启动（macOS 13+ SMAppService）
- 🔍 **点击穿透**：点击松鼠以外的透明区域自动穿透到桌面
- 🔋 **节能设计**：单一事件驱动定时器（无轮询）、无活跃提醒时完全休眠；待机时暂停 SpriteKit 渲染（0 帧/秒），只在眨眼 / 摇尾巴 / 气泡等需要时短暂唤醒

## 提醒状态

```
scheduled（待提醒）→ due（到点）→ active（DAL-E 正在提醒）→ completed（已完成）
```

状态会持久化保存；重启后到点的提醒会自动重新唤醒 DAL-E。
重复提醒完成后不会变成 completed，而是自动推进到下一次出现时间（如 每天 08:00 → 明天 08:00）。

## 重复提醒数据

```json
{
  "id": "",
  "title": "Drink water",
  "scheduledAt": "下一次出现时间",
  "status": "scheduled",
  "frequency": "daily",
  "weekdays": [1, 3, 5],
  "dayOfMonth": 1,
  "hour": 8,
  "minute": 0,
  "enabled": true
}
```

- `once`：一次性，scheduledAt 为绝对时间
- `daily`：每天 hour:minute
- `weekly`：每周 weekdays（1=周一 … 7=周日）的 hour:minute；创建时可一键选「工作日/周末/每天」，也可单独勾选任意星期
- `monthly`：每月第 dayOfMonth 日 hour:minute

调度器与通知只关心下一次出现时间（scheduledAt），重复规则只用于计算下一次，因此依然只有一个定时器、事件驱动、无轮询。

## 操作说明

| 操作 | 效果 |
|------|------|
| **左键点击** | 温柔抱抱 + 随机暖心话语；有到期提醒时打开提醒卡片（完成 / 稍后 / 编辑 / 删除） |
| **左键拖拽** | 移动松鼠到屏幕任意位置 |
| **右键点击** | 打开菜单 |
| **右键 → 💬 打开对话** | 打开秋日对话窗（创建提醒 / 提醒花园 / 抱抱我） |
| **长时间未互动** | DAL-E 会安静地送上一句温暖的安慰 |
| **右键 → 🌰 提醒花园** | 卡片式提醒管理页（查看 / 编辑 / 删除） |
| **右键 → ⏰ 提醒 → 创建提醒** | 新建提醒：任务 + 重复频率（仅一次 / 每天 / 每周 / 每月）+ 时间 |
| **重复提醒** | 完成后自动计算下一次（如每天 08:00 → 明天 08:00），不会被删除 |
| **禁用 / 启用** | 提醒花园卡片上的 ⏸ / ▶️ 按钮；禁用后不通知、不唤醒 DAL-E，但保留数据 |
| **提醒到点** | macOS 通知 + DAL-E 出现在桌面并连续上下跳跃，直到被点击处理；重复提醒只计算下一次时间，事件驱动、无轮询 |
| **对话气泡** | 暖奶油底 + 均匀金边 + 小尾巴指向 DAL-E，圆角精致，带柔和阴影 |
| **闲置 4-10 秒** | 左眼慵懒眨眼（约 1 秒：眼皮缓缓盖下 → 闭合休息 → 缓缓睁开） |
| **闲置 12-22 秒** | 摇尾巴 |
| **其余时间** | 0 帧静止待机（省电） |

## 构建与运行

### 环境要求
- macOS 12.0+
- Xcode Command Line Tools (swiftc)

### 一键构建并启动

```bash
cd SquirrelPet
bash build.sh
```

### 手动构建

```bash
swiftc -framework AppKit -framework SpriteKit -framework ServiceManagement -framework UserNotifications -O \
    -o SquirrelPet \
    main.swift AppDelegate.swift PetWindow.swift PetView.swift SquirrelNode.swift \
    AnimationManager.swift LoginItemManager.swift \
    Reminder.swift ReminderStore.swift ReminderScheduler.swift \
    EncouragementDialogue.swift ReminderUI.swift \
    DalEStyle.swift ReminderNotifications.swift ChatWindow.swift ReminderGardenWindow.swift

# 创建 App Bundle
mkdir -p Dal-E.app/Contents/MacOS
mkdir -p Dal-E.app/Contents/Resources
cp SquirrelPet Dal-E.app/Contents/MacOS/
cp Info.plist Dal-E.app/Contents/
cp squirrel.png Dal-E.app/Contents/Resources/
cp eyelid.png Dal-E.app/Contents/Resources/
chmod +x Dal-E.app/Contents/MacOS/SquirrelPet

open Dal-E.app
```

## 项目结构

```
SquirrelPet/
├── main.swift                    # 应用入口
├── AppDelegate.swift             # 应用生命周期、窗口、通知授权、消息路由
├── PetWindow.swift               # 无边框透明桌面窗口
├── PetView.swift                 # SpriteKit 视图、鼠标事件、右键菜单、提醒交互
├── SquirrelNode.swift            # 松鼠精灵图加载（Q 版造型）
├── AnimationManager.swift        # 动画状态机（待机 + 互动 + 提醒跳跃）
├── LoginItemManager.swift        # 开机启动管理（SMAppService）
├── Reminder.swift                # 提醒模型与状态（scheduled/due/active/completed）
├── ReminderStore.swift           # 提醒持久化（UserDefaults + JSON）+ 变更通知
├── ReminderScheduler.swift       # 事件驱动提醒调度器（单定时器 + 队列）
├── ReminderNotifications.swift   # macOS 原生通知（UNUserNotificationCenter）
├── EncouragementDialogue.swift   # 固定鼓励语 + 轻量气泡
├── ReminderUI.swift              # 创建/编辑表单、提醒卡片、稍后选项
├── ChatWindow.swift              # 秋日对话窗（圆角气泡、圆润字体）
├── ReminderGardenWindow.swift    # 提醒花园（卡片式管理页）
├── DalEStyle.swift               # 共用视觉风格（暖秋配色 + 圆润字体）
├── Info.plist                    # App Bundle 配置
├── build.sh                      # 一键构建脚本
├── squirrel.png                  # DAL-E 松鼠精灵图
└── eyelid.png                    # 左眼眨眼眼皮遮罩（与脸部同色，闭合带睫毛弧线）
```

## 自定义

### 替换宠物图

想把 DAL-E 换成自己的小宠物（PNG），直接替换项目根目录的 `squirrel.png` 即可；
`SquirrelNode.swift` 会自动从 bundle / 可执行文件目录加载它。也可以用序列帧：

```swift
let texture = SKTexture(imageNamed: "squirrel_idle_01")
let sprite = SKSpriteNode(texture: texture)
```

### 眨眼

DAL-E 现在会**左眼眨眼**（慵懒 wink）：由 `eyelid.png` 眼皮遮罩驱动，颜色与脸部融合、闭合时带睫毛弧线。
想改成两只眼一起眨，在 `SquirrelNode.swift` 里给右眼加一片镜像眼皮即可（`attachLeftEyelid` 的右眼版本）。

## 技术细节

- **窗口层级**：`kCGDesktopIconWindowLevel + 1`（桌面图标层，低于普通窗口）
- **Dock 图标隐藏**：`LSUIElement = YES` + `.accessory` activation policy
- **点击穿透**：重写 `SKView.hitTest(_:)`，仅松鼠区域响应事件
- **开机启动**：macOS 13+ 使用 `SMAppService.mainApp.register()`
- **动画引擎**：`SKAction` 驱动的状态机；眨眼用与脸部同色的眼皮遮罩层（`eyelid.png`）实现真正的左眼眨眼；待机微动画（眨眼 / 摇尾巴）用墙钟 `DispatchWorkItem` 调度，空闲时暂停整个渲染循环，真正 0 帧待机
- **提醒调度**：`DispatchSourceTimer` 一次性定时器，指向下一个到期的提醒；无提醒时取消定时器并休眠
- **原生通知**：按提醒 ID 作为通知标识，天然去重；删除 / 完成 / 编辑时同步取消或更新
- **对话字体**：系统圆体（`.AppleSystemUIFont` 的 rounded design），韩语 / 中文自动回退，清晰可读

## 📌 免责声明

本项目是 **粉丝自制** 的桌面宠物，灵感来自 IVE 官方角色系列 MINIVE 中的「DAL-E」（金秋天角色）。
**与 IVE / STARSHIP Entertainment 无任何官方关联，也非官方周边**；角色名称与形象版权归原公司所有，应用内韩语鼓励文案为原创内容，代码部分为个人项目。
