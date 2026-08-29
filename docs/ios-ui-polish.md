# iOS 界面精修计划

## 目标

优先优化 iPhone，并以 Apple Music 的原生信息密度、系统排版和触控反馈为质量基准。iOS 26 使用系统 TabView、底部 accessory 与 Liquid Glass；不在系统材质上重复叠加自定义玻璃层。

## Apple 官方规范校准

参考：

- [Human Interface Guidelines：Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Human Interface Guidelines：Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Human Interface Guidelines：Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Human Interface Guidelines：Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Apple Music iOS 26 官方界面](https://www.apple.com/newsroom/2025/06/apple-services-deliver-powerful-features-and-intelligent-updates-to-users-this-fall/)

落地规则：

- 页面主体遵循系统安全区，并以 16 pt 作为 iPhone 内容起始轴；横向滚动内容可以延伸到屏幕边缘，但静止位置仍与内容轴对齐。
- 44×44 pt 是默认控件触控尺寸，不用于强行撑高纯文本区块标题。
- 使用 Large Title、Title 2、Body、Subheadline、Footnote 等语义字号，不在 iOS 内容层使用固定字号模拟系统排版。
- Liquid Glass 只属于导航与控件功能层；专辑封面、内容卡片和列表不叠加玻璃、描边或装饰性材质。
- iOS 26 保留系统 TabView、独立搜索 Tab、滚动缩起行为和系统 bottom accessory，不复制自绘 Tab Bar。
- MiniPlayer 只保留当前歌曲标题、播放/暂停和下一首；内容滚动到其下方，由系统玻璃负责分层。
- 音乐封面保持干净，iPhone 信息流不覆盖播放量胶囊；补充信息放在封面下方或二级页面。
- 内容网格使用随可用宽度变化的双列布局，不能以固定 160 pt 卡片居中后产生不等左右边距。
- 信息流直接稳定出现，不使用逐卡片编排式入场动画；按压反馈即时、克制并尊重“减弱动态效果”。

## 本轮范围

- 建立 iPhone 统一布局令牌：16 pt 页面边距、44 pt 最小触控区域、稳定的区块节奏。
- 统一推荐页和精选页的标题、卡片文字、横向货架与筛选控件间距。
- 调整歌曲行在 iPhone 上的内容起点与操作区域，避免桌面端间距直接复用。
- 精修 iOS 26 底部迷你播放器的信息密度、字号与控制数量。
- 收敛非手势动效的回弹幅度，并尊重“减弱动态效果”。
- 区分无副标题的紧凑货架与含副标题的信息货架，避免固定高度制造空白。
- 将资料库改为 Apple Music 式 plain list：强调 SF Symbol、正文和系统分隔线，不使用分组卡片外观。

## 第三轮：真机截图定点修正

根据已登录 iPhone 真机截图，继续修正两个仍有明显自定义痕迹的页面：

- 漫游未开始时不再展示无信息的大尺寸占位封面，改用系统 `ContentUnavailableView` 组织功能说明与主操作。
- “开始漫游”不再使用渐变、白字、胶囊和外发光的组合；iOS 26 使用系统 `glassProminent`，旧系统使用 `borderedProminent`，仅通过 tint 表达品牌色。
- 漫游播放控件移除渐变圆形底和装饰阴影，使用 SF Symbol、标准触控区域和克制的按压反馈。
- 已登录资料库不再用多个 `Section` 的系统默认间距控制内容节奏；头像、快捷入口和歌单标题改为显式行内距与分隔线规则。
- 快捷入口目标高度为 52 pt，图标、正文和分隔线共享同一内容轴；歌单标题使用黑色 Title 2 层级，不继承灰色 Section Header 外观。
- 设置按钮继续使用系统 toolbar item，让 iOS 26 自动提供 Liquid Glass 外观，不在内容层复制圆形玻璃按钮。

## 不在本轮处理

- 不改变 API、播放队列、登录和账号逻辑。
- 不重做播放页的三种模式。
- 不改变 macOS 的布局尺寸。
- iOS 16–25 仅保持兼容，不作为主要视觉验收目标。

## 验收标准

- iPhone 17 Pro / iOS 26.5 下，导航大标题、区块标题和主要内容边缘形成一致视觉轴线。
- 所有新增或调整的按钮触控区域不小于 44×44 pt。
- 系统 Tab Bar 与底部播放 accessory 不出现嵌套材质。
- Dynamic Type、减少动态效果和 VoiceOver 语义不因本轮修改退化。
- iOS 模拟器 Debug 构建成功，并完成首页、精选页和底部播放区截图检查。
