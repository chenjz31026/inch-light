# inch-light
一个简单的记事本和多任务计时器



#### Tree

```
lib/
├── constants/              # 存放常量、颜色配置
│   └── app_colors.dart
├── models/                 # 数据模型
│   └── task_model.dart
├── providers/              # 状态管理逻辑
│   └── app_provider.dart
├── screens/                # 页面（屏幕）
│   ├── main_screen.dart
│   ├── timer_page.dart
│   └── todo_page.dart
├── widgets/                # 可复用的 UI 组件
│   ├── common_widgets.dart # 小组件集合 (Chip, Input, Header)
│   └── custom_date_picker.dart # 复杂的日期选择器组件
└── main.dart               # 程序入口
```



#### 待更新目录

- [ ] 倒计时专注任务建立后，可修改倒计时时长
- [ ] 数据可视化，可以选择周视图/月视图/年视图看到统计每日专注时长的比例条形图和折线图
- [ ] 可新增桌面组件，专注一个，清单一个
- [ ] 清单中截止时间的颜色改为绿色，超时后才变成黄色



 `PS：学业繁重，不一定会继续更新，真有需求的同志自己写代码吧`

