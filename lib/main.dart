import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // 用来保证手机屏幕常亮，防止计时因锁屏而中断

// ==================== 0. 全局配置与工具 ====================

class AppColors {
  static const Color primary = Color(0xFF4F46E5); // Indigo 600
  static const Color primaryLight = Color(0xFF818CF8); // Indigo 400
  static const Color bg = Color(0xFFF9FAFB);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF1F2937); // Gray 800
  static const Color textGray = Color(0xFF6B7280); // Gray 500
}

final List<Color> taskColors = [
  const Color(0xFFF87171), // Red
  const Color(0xFFFBBF24), // Amber
  const Color(0xFF34D399), // Emerald
  const Color(0xFF60A5FA), // Blue
  const Color(0xFF818CF8), // Indigo
  const Color(0xFFA78BFA), // Violet
  const Color(0xFFF472B6), // Pink
  const Color(0xFFFB923C), // Orange
  const Color(0xFFA3E635), // Lime
  const Color(0xFF2DD4BF), // Teal
  const Color(0xFF22D3EE), // Cyan
  const Color(0xFFE879F9), // Fuchsia
  const Color(0xFF94A3B8), // Slate
];

// ==================== 1. 数据模型 (Models) ====================

enum TaskType { timer, daily, normal }

enum TimerMode { stopwatch, countdown }

class TaskItem {
  String id;
  String title;
  TaskType type;

  // 计时专用
  int colorIndex;
  TimerMode timerMode;
  int durationSeconds;
  int? targetSeconds;

  // 记事专用
  bool isCompleted;
  DateTime? deadline;
  List<String> tags;
  DateTime? finishedAt;

  TaskItem({
    required this.id,
    required this.title,
    required this.type,
    this.colorIndex = 0,
    this.timerMode = TimerMode.stopwatch,
    this.durationSeconds = 0,
    this.targetSeconds,
    this.isCompleted = false,
    this.deadline,
    this.tags = const [],
    this.finishedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type.index,
    'colorIndex': colorIndex,
    'timerMode': timerMode.index,
    'durationSeconds': durationSeconds,
    'targetSeconds': targetSeconds,
    'isCompleted': isCompleted,
    'deadline': deadline?.toIso8601String(),
    'tags': tags,
    'finishedAt': finishedAt?.toIso8601String(),
  };

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'],
      title: json['title'],
      type: TaskType.values[json['type']],
      colorIndex: json['colorIndex'] ?? 0,
      timerMode: TimerMode.values[json['timerMode'] ?? 0],
      durationSeconds: json['durationSeconds'] ?? 0,
      targetSeconds: json['targetSeconds'],
      isCompleted: json['isCompleted'] ?? false,
      deadline: json['deadline'] != null
          ? DateTime.parse(json['deadline'])
          : null,
      tags: List<String>.from(json['tags'] ?? []),
      finishedAt: json['finishedAt'] != null
          ? DateTime.parse(json['finishedAt'])
          : null,
    );
  }
}

// ==================== 2. 状态管理 (Provider) ====================

class AppProvider with ChangeNotifier {
  final List<TaskItem> _timerTasks = [];
  final List<TaskItem> _dailyTasks = [];
  final List<TaskItem> _normalTasks = [];

  Timer? _timer;
  String? _activeTimerId;

  List<TaskItem> get timerTasks => _timerTasks;
  List<TaskItem> get dailyTasks => _dailyTasks;
  List<TaskItem> get normalTasks => _normalTasks;
  String? get activeTimerId => _activeTimerId;

  AppProvider() {
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastOpenDate = prefs.getString('lastOpenDate');
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    void loadList(String key, List<TaskItem> list) {
      String? jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        list.clear();
        list.addAll(
          (jsonDecode(jsonStr) as List).map((e) => TaskItem.fromJson(e)),
        );
      }
    }

    loadList('timerTasks', _timerTasks);
    loadList('dailyTasks', _dailyTasks);
    loadList('normalTasks', _normalTasks);

    if (lastOpenDate != todayStr) {
      for (var t in _dailyTasks) {
        t.isCompleted = false;
      }
      for (var t in _timerTasks) {
        t.durationSeconds = 0;
      }

      prefs.setString('lastOpenDate', todayStr);
      _saveData();
    }
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
      'timerTasks',
      jsonEncode(_timerTasks.map((e) => e.toJson()).toList()),
    );
    prefs.setString(
      'dailyTasks',
      jsonEncode(_dailyTasks.map((e) => e.toJson()).toList()),
    );
    prefs.setString(
      'normalTasks',
      jsonEncode(_normalTasks.map((e) => e.toJson()).toList()),
    );
    prefs.setString(
      'lastOpenDate',
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
  }

  void addTimerTask(String title, TimerMode mode, int? target) {
    _timerTasks.add(
      TaskItem(
        id: const Uuid().v4(),
        title: title,
        type: TaskType.timer,
        timerMode: mode,
        targetSeconds: target,
        colorIndex: _timerTasks.length % taskColors.length,
      ),
    );
    _saveData();
    notifyListeners();
  }

  void renameTimerTask(String id, String newName) {
    final index = _timerTasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _timerTasks[index].title = newName;
      _saveData();
      notifyListeners();
    }
  }

  void resetTimerTask(String id) {
    final index = _timerTasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      if (_activeTimerId == id) stopTimer();
      _timerTasks[index].durationSeconds = 0;
      _saveData();
      notifyListeners();
    }
  }

  void deleteTimerTask(String id) {
    if (_activeTimerId == id) stopTimer();
    _timerTasks.removeWhere((t) => t.id == id);
    _saveData();
    notifyListeners();
  }

  void clearAllTimerTasks() {
    stopTimer();
    _timerTasks.clear();
    _saveData();
    notifyListeners();
  }

  void toggleTimer(String id) {
    if (_activeTimerId == id) {
      stopTimer();
    } else {
      stopTimer();
      _startTimer(id);
    }
  }

  void _startTimer(String id) {
    _activeTimerId = id;

    // 开启屏幕常亮
    WakelockPlus.enable();

    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      int index = _timerTasks.indexWhere((t) => t.id == id);
      if (index == -1) {
        stopTimer();
        return;
      }
      var task = _timerTasks[index];

      if (task.timerMode == TimerMode.stopwatch) {
        task.durationSeconds++;
      } else {
        if (task.durationSeconds < (task.targetSeconds ?? 0)) {
          task.durationSeconds++;
          if (task.durationSeconds >= (task.targetSeconds ?? 0)) {
            stopTimer();
            _playAlarm();
          }
        }
      }
      if (task.durationSeconds % 5 == 0) _saveData();
      notifyListeners();
    });
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _activeTimerId = null;

    // 关闭屏幕常亮（恢复系统自动息屏）
    WakelockPlus.disable();

    _saveData();
    notifyListeners();
  }

  void _playAlarm() {
    FlutterRingtonePlayer().playNotification(
      looping: false,
      volume: 1.0,
      asAlarm: true,
    );
    HapticFeedback.heavyImpact();
  }

  void addTodoTask(
    String title,
    TaskType type, {
    DateTime? deadline,
    List<String> tags = const [],
  }) {
    final t = TaskItem(
      id: const Uuid().v4(),
      title: title,
      type: type,
      deadline: deadline,
      tags: tags,
    );
    (type == TaskType.daily ? _dailyTasks : _normalTasks).add(t);
    _saveData();
    notifyListeners();
  }

  void updateTodoTask(
    TaskItem task,
    String newTitle,
    DateTime? newDeadline,
    List<String> newTags,
  ) {
    task.title = newTitle;
    task.deadline = newDeadline;
    task.tags = newTags;
    _saveData();
    notifyListeners();
  }

  void toggleTodo(TaskItem t) {
    t.isCompleted = !t.isCompleted;
    t.finishedAt = t.isCompleted ? DateTime.now() : null;
    _saveData();
    notifyListeners();
  }

  void deleteTodo(TaskItem t) {
    (t.type == TaskType.daily ? _dailyTasks : _normalTasks).removeWhere(
      (x) => x.id == t.id,
    );
    _saveData();
    notifyListeners();
  }

  void clearTodos({required bool completedOnly}) {
    _dailyTasks.removeWhere((t) => t.isCompleted == completedOnly);
    _normalTasks.removeWhere((t) => t.isCompleted == completedOnly);
    _saveData();
    notifyListeners();
  }
}

// ==================== 3. UI 界面 ====================

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppProvider())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '寸光',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.bg,
        primaryColor: AppColors.primary,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        textTheme: GoogleFonts.notoSansScTextTheme(),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = const [TimerPage(), TodoPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 16,
              24,
              16,
            ),
            color: AppColors.bg,
            child: Row(
              children: [
                Text(
                  "寸光",
                  style: GoogleFonts.zhiMangXing(
                    fontSize: 36,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textDark,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_done_outlined,
                        size: 14,
                        color: Colors.green[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "已同步",
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _pages[_currentIndex]),
          Container(
            width: double.infinity, // 占满宽度以保证居中
            color: AppColors.bg, // 背景色与页面一致
            padding: const EdgeInsets.only(top: 4, bottom: 8), // 上下留一点呼吸空间
            child: Text(
              "All rights reserved: Symplatt",
              textAlign: TextAlign.center, // 居中对齐
              style: GoogleFonts.notoSansSc(
                // 使用现有字体风格
                fontSize: 10, // 小字
                color: Colors.grey[400], // 灰色
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.white,
          elevation: 0,
          currentIndex: _currentIndex,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Colors.grey[400],
          selectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          onTap: (idx) => setState(() => _currentIndex = idx),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.hourglass_empty_rounded),
              activeIcon: Icon(Icons.hourglass_full_rounded),
              label: '专注',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted_rounded),
              activeIcon: Icon(Icons.checklist_rtl_rounded),
              label: '清单',
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 页面 1: 计时 ====================

class TimerPage extends StatelessWidget {
  const TimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Stack(
      children: [
        Column(
          children: [
            // ==================== 修改 1：移除顶部的“清空”按钮 ====================
            // 之前的清空按钮代码已删除
            Expanded(
              child: provider.timerTasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.timer_off_outlined,
                            size: 48,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "点击右下角添加专注任务",
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                      children: [
                        ...provider.timerTasks.map(
                          (task) => _buildTimerCard(context, task, provider),
                        ),
                      ],
                    ),
            ),
          ],
        ),

        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton(
            heroTag: "timer_add",
            backgroundColor: AppColors.textDark,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context),
          ),
        ),
      ],
    );
  }

  Widget _buildTimerCard(
    BuildContext context,
    TaskItem task,
    AppProvider provider,
  ) {
    bool isRunning = provider.activeTimerId == task.id;
    Color themeColor = taskColors[task.colorIndex];
    String timeStr = _formatDuration(task.durationSeconds);

    if (task.timerMode == TimerMode.countdown) {
      int remain = (task.targetSeconds ?? 0) - task.durationSeconds;
      if (remain < 0) remain = 0;
      timeStr = _formatDuration(remain);
    }

    // ==================== 修改 2：新增 Dismissible 实现侧滑删除 ====================
    return Dismissible(
      key: Key(task.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red[100],
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => provider.deleteTimerTask(task.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              if (isRunning)
                Positioned(
                  right: -20,
                  top: -20,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: themeColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => provider.toggleTimer(task.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isRunning ? themeColor : AppColors.bg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isRunning ? Icons.pause : Icons.play_arrow_rounded,
                          color: isRunning ? Colors.white : AppColors.textDark,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: themeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              task.timerMode == TimerMode.countdown
                                  ? "倒计时"
                                  : "正计时",
                              style: TextStyle(
                                fontSize: 10,
                                color: themeColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 24,
                            fontFamily: 'Monospace',
                            fontWeight: FontWeight.bold,
                            color: isRunning ? themeColor : Colors.grey[300],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showOptions(context, provider, task),
                          child: Icon(
                            Icons.more_horiz,
                            color: Colors.grey[400],
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, AppProvider provider, TaskItem task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Center(
          child: Text(
            task.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Center(child: Text("重命名")),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, provider, task);
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            ListTile(
              title: const Center(child: Text("重置时间")),
              onTap: () {
                provider.resetTimerTask(task.id);
                Navigator.pop(ctx);
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            ListTile(
              title: const Center(
                child: Text("删除任务", style: TextStyle(color: Colors.red)),
              ),
              onTap: () {
                provider.deleteTimerTask(task.id);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    TextEditingController tc = TextEditingController();
    TimerMode mode = TimerMode.stopwatch;
    int h = 0, m = 0, s = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "开启新专注",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: tc,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "给任务起个名字...",
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _ModeChip(
                    label: "正计时",
                    selected: mode == TimerMode.stopwatch,
                    onTap: () => setState(() => mode = TimerMode.stopwatch),
                  ),
                  const SizedBox(width: 12),
                  _ModeChip(
                    label: "倒计时",
                    selected: mode == TimerMode.countdown,
                    onTap: () => setState(() => mode = TimerMode.countdown),
                  ),
                ],
              ),
              if (mode == TimerMode.countdown) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _TimeInput(
                        label: "时",
                        onChanged: (v) => h = int.tryParse(v) ?? 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TimeInput(
                        label: "分",
                        onChanged: (v) => m = int.tryParse(v) ?? 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TimeInput(
                        label: "秒",
                        onChanged: (v) => s = int.tryParse(v) ?? 0,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    if (tc.text.isEmpty) return;
                    int? target = (mode == TimerMode.countdown)
                        ? (h * 3600 + m * 60 + s)
                        : null;
                    if (mode == TimerMode.countdown &&
                        (target == null || target == 0)) {
                      return;
                    }
                    Provider.of<AppProvider>(
                      context,
                      listen: false,
                    ).addTimerTask(tc.text, mode, target);
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    "开始行动",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    AppProvider provider,
    TaskItem task,
  ) {
    TextEditingController tc = TextEditingController(text: task.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("重命名"),
        content: TextField(
          controller: tc,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              if (tc.text.isNotEmpty) {
                provider.renameTimerTask(task.id, tc.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int sec) {
    Duration d = Duration(seconds: sec);
    return "${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }
}

// ==================== 页面 2: 记事清单 ====================

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});
  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  bool showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final daily = provider.dailyTasks
        .where((t) => t.isCompleted == showCompleted)
        .toList();
    final normal = provider.normalTasks
        .where((t) => t.isCompleted == showCompleted)
        .toList();

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  _FilterChip(
                    text: "未完成",
                    selected: !showCompleted,
                    onTap: () => setState(() => showCompleted = false),
                  ),
                  const SizedBox(width: 12),
                  _FilterChip(
                    text: "已完成",
                    selected: showCompleted,
                    onTap: () => setState(() => showCompleted = true),
                  ),

                  const Spacer(),
                  InkWell(
                    onTap: () => _confirmClear(context, () {
                      provider.clearTodos(completedOnly: showCompleted);
                    }),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.delete_sweep_outlined,
                        size: 22,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  if (daily.isNotEmpty) ...[
                    _SectionHeader(title: "每日打卡"),
                    ...daily.map((t) => _buildTodoCard(t, provider)),
                    const SizedBox(height: 20),
                  ],
                  if (normal.isNotEmpty) ...[
                    _SectionHeader(title: "任务清单"),
                    ...normal.map((t) => _buildTodoCard(t, provider)),
                  ],
                  if (daily.isEmpty && normal.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 100),
                        child: Text(
                          "暂无任务",
                          style: TextStyle(color: Colors.grey[300]),
                        ),
                      ),
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),

        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton(
            heroTag: "todo_add",
            backgroundColor: AppColors.textDark,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Icon(Icons.add),
            onPressed: () => _showAddTodo(context),
          ),
        ),
      ],
    );
  }

  void _confirmClear(BuildContext context, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("确认清空"),
        content: Text("确定清空所有${showCompleted ? "已完成" : "未完成"}的任务吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text("清空", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoCard(TaskItem task, AppProvider provider) {
    return Dismissible(
      key: Key(task.id),
      background: Container(
        color: Colors.red[100],
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => provider.deleteTodo(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Row(
            children: [
              InkWell(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
                onTap: () => provider.toggleTodo(task),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: task.isCompleted
                          ? AppColors.primary
                          : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: task.isCompleted
                            ? AppColors.primary
                            : Colors.grey[300]!,
                        width: 2,
                      ),
                    ),
                    child: task.isCompleted
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(16),
                  ),
                  onTap: () => _showEditTodo(context, provider, task),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 16,
                            color: task.isCompleted
                                ? Colors.grey[400]
                                : AppColors.textDark,
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: Colors.grey[400],
                          ),
                        ),
                        if (task.deadline != null || task.tags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                if (task.deadline != null) ...[
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 12,
                                    color: task.isCompleted
                                        ? Colors.grey[300]
                                        : Colors.red[300],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat(
                                      'MM-dd HH:mm',
                                    ).format(task.deadline!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: task.isCompleted
                                          ? Colors.grey[300]
                                          : Colors.red[400],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                ...task.tags.map(
                                  (tag) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(
                                      "#$tag",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[400],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 修改 3：改用 showDialog 将选择器居中显示 ====================
  Future<DateTime?> _showCustomDatePicker(
    BuildContext context, {
    DateTime? initialTime,
  }) async {
    DateTime tempDate = initialTime ?? DateTime.now();

    return await showDialog<DateTime>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 340, // 限制宽度，使其在任何屏幕上都保持优雅的卡片形态
          child: _CustomDateTimePickerWidget(initialDate: tempDate),
        ),
      ),
    );
  }

  void _showEditTodo(
    BuildContext context,
    AppProvider provider,
    TaskItem task,
  ) {
    final tc = TextEditingController(text: task.title);
    final tagC = TextEditingController(text: task.tags.join(" "));
    DateTime? dead = task.deadline;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "编辑任务",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: tc,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "任务名称",
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tagC,
                decoration: const InputDecoration(
                  labelText: "标签 (空格分隔)",
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: () async {
                  final result = await _showCustomDatePicker(
                    context,
                    initialTime: dead,
                  );
                  if (result != null) {
                    if (result.year == 0) {
                      setState(() => dead = null);
                    } else {
                      setState(() => dead = result);
                    }
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        color: dead == null
                            ? Colors.grey[400]
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        dead == null
                            ? "设置截止时间"
                            : DateFormat('yyyy-MM-dd HH:mm').format(dead!),
                        style: TextStyle(
                          color: dead == null
                              ? Colors.grey[500]
                              : AppColors.textDark,
                          fontWeight: dead == null
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (dead != null)
                        GestureDetector(
                          onTap: () => setState(() => dead = null),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.grey,
                          ),
                        )
                      else
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: Colors.grey,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    if (tc.text.isEmpty) return;
                    List<String> tags = tagC.text
                        .split(' ')
                        .where((s) => s.isNotEmpty)
                        .toList();
                    provider.updateTodoTask(task, tc.text, dead, tags);
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    "保存修改",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddTodo(BuildContext context) {
    final tc = TextEditingController();
    final tagC = TextEditingController();
    TaskType type = TaskType.normal;
    DateTime? dead;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "添加任务",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: tc,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "准备做什么？",
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _ModeChip(
                    label: "每日打卡",
                    selected: type == TaskType.daily,
                    onTap: () => setState(() => type = TaskType.daily),
                  ),
                  const SizedBox(width: 12),
                  _ModeChip(
                    label: "普通待办",
                    selected: type == TaskType.normal,
                    onTap: () => setState(() => type = TaskType.normal),
                  ),
                ],
              ),
              if (type == TaskType.normal) ...[
                const SizedBox(height: 20),
                TextField(
                  controller: tagC,
                  decoration: const InputDecoration(
                    labelText: "标签 (空格分隔)",
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final result = await _showCustomDatePicker(
                      context,
                      initialTime: dead,
                    );
                    if (result != null) {
                      if (result.year == 0) {
                        setState(() => dead = null);
                      } else {
                        setState(() => dead = result);
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          color: dead == null
                              ? Colors.grey[400]
                              : AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          dead == null
                              ? "设置截止时间"
                              : DateFormat('yyyy-MM-dd HH:mm').format(dead!),
                          style: TextStyle(
                            color: dead == null
                                ? Colors.grey[500]
                                : AppColors.textDark,
                            fontWeight: dead == null
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (dead != null)
                          GestureDetector(
                            onTap: () => setState(() => dead = null),
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey,
                            ),
                          )
                        else
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Colors.grey,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    if (tc.text.isEmpty) return;
                    List<String> tags = tagC.text
                        .split(' ')
                        .where((s) => s.isNotEmpty)
                        .toList();
                    Provider.of<AppProvider>(
                      context,
                      listen: false,
                    ).addTodoTask(tc.text, type, deadline: dead, tags: tags);
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    "确认添加",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 自定义日期选择器组件 (复刻截图) ====================

class _CustomDateTimePickerWidget extends StatefulWidget {
  final DateTime initialDate;
  const _CustomDateTimePickerWidget({required this.initialDate});

  @override
  State<_CustomDateTimePickerWidget> createState() =>
      _CustomDateTimePickerWidgetState();
}

class _CustomDateTimePickerWidgetState
    extends State<_CustomDateTimePickerWidget> {
  late int selectedYear;
  late int selectedMonth;
  late int selectedDay;
  late int selectedHour;
  late int selectedMinute;

  final FixedExtentScrollController _yearCtrl = FixedExtentScrollController();
  final FixedExtentScrollController _monthCtrl = FixedExtentScrollController();
  final FixedExtentScrollController _dayCtrl = FixedExtentScrollController();
  final FixedExtentScrollController _hourCtrl = FixedExtentScrollController();
  final FixedExtentScrollController _minuteCtrl = FixedExtentScrollController();

  final int minYear = 2020;
  final int maxYear = 2030;

  @override
  void initState() {
    super.initState();
    selectedYear = widget.initialDate.year;
    selectedMonth = widget.initialDate.month;
    selectedDay = widget.initialDate.day;
    selectedHour = widget.initialDate.hour;
    selectedMinute = widget.initialDate.minute;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _yearCtrl.jumpToItem(selectedYear - minYear);
      _monthCtrl.jumpToItem(selectedMonth - 1);
      _dayCtrl.jumpToItem(selectedDay - 1);
      _hourCtrl.jumpToItem(selectedHour);
      _minuteCtrl.jumpToItem(selectedMinute);
    });
  }

  int _getDaysInMonth(int year, int month) {
    if (month == 2) {
      final bool isLeap =
          (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return isLeap ? 29 : 28;
    }
    const List<int> days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month];
  }

  Widget _buildPicker(
    FixedExtentScrollController controller,
    List<int> items,
    ValueChanged<int> onChanged,
  ) {
    return Expanded(
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 40,
        magnification: 1.1,
        useMagnifier: true,
        backgroundColor: Colors.transparent,
        selectionOverlay: _CustomSelectionOverlay(),
        onSelectedItemChanged: (index) {
          onChanged(items[index]);
          HapticFeedback.selectionClick();
        },
        children: items
            .map(
              (e) => Center(
                child: Text(
                  e.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xFF4B5563),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = _getDaysInMonth(selectedYear, selectedMonth);
    // 修正日期溢出
    if (selectedDay > daysInMonth) selectedDay = daysInMonth;

    return Container(
      height: 420,
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "设置日期和时间",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 30),

          // 年 月 日
          SizedBox(
            height: 120,
            child: Row(
              children: [
                const SizedBox(width: 20),
                _buildPicker(
                  _yearCtrl,
                  List.generate(maxYear - minYear + 1, (i) => minYear + i),
                  (val) => setState(() => selectedYear = val),
                ),
                const SizedBox(width: 10),
                _buildPicker(
                  _monthCtrl,
                  List.generate(12, (i) => i + 1),
                  (val) => setState(() => selectedMonth = val),
                ),
                const SizedBox(width: 10),
                _buildPicker(
                  _dayCtrl,
                  List.generate(daysInMonth, (i) => i + 1),
                  (val) => setState(() => selectedDay = val),
                ),
                const SizedBox(width: 20),
              ],
            ),
          ),

          const SizedBox(height: 20), // 中间留白
          // 时 分
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                _buildPicker(
                  _hourCtrl,
                  List.generate(24, (i) => i),
                  (val) => setState(() => selectedHour = val),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    ":",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                _buildPicker(
                  _minuteCtrl,
                  List.generate(60, (i) => i),
                  (val) => setState(() => selectedMinute = val),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),

          const Spacer(),

          // 底部按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    // 返回特殊的 Year=0 表示清除
                    Navigator.pop(context, DateTime(0));
                  },
                  child: const Text(
                    "清除",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "取消",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                    final date = DateTime(
                      selectedYear,
                      selectedMonth,
                      selectedDay,
                      selectedHour,
                      selectedMinute,
                    );
                    Navigator.pop(context, date);
                  },
                  child: const Text(
                    "设置",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomSelectionOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
        ),
      ),
    );
  }
}

// ==================== 小组件 ====================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[400],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.textDark : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.textDark : Colors.grey[300]!,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.1) : AppColors.bg,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _TimeInput extends StatelessWidget {
  final String label;
  final ValueChanged<String> onChanged;
  const _TimeInput({required this.label, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        hintText: "0",
        hintStyle: TextStyle(color: Colors.grey[400]),
        suffixText: label,
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
