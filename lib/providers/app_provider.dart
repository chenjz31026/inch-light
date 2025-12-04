import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart'; // [新增] 音频插件
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../constants/app_colors.dart';
import '../models/task_model.dart';

class AppProvider with ChangeNotifier {
  final List<TaskItem> _timerTasks = [];
  final List<TaskItem> _dailyTasks = [];
  final List<TaskItem> _normalTasks = [];
  final List<CycleTask> _cycleTasks = [];

  Timer? _timer; // 主计时器
  Timer? _focusModeTrigger; // [新增] 聚焦模式触发器
  String? _activeTimerId;

  bool _hasLoaded = false;
  bool _isFocusMode = false; // [新增] 是否处于聚焦模式

  // [新增] 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<TaskItem> get timerTasks => _timerTasks;
  List<TaskItem> get dailyTasks => _dailyTasks;
  List<TaskItem> get normalTasks => _normalTasks;
  List<CycleTask> get cycleTasks => _cycleTasks;
  String? get activeTimerId => _activeTimerId;
  bool get isFocusMode => _isFocusMode; // Getter

  AppProvider() {
    _initData();
  }

  // ==================== 数据持久化 ====================

  Future<void> _initData() async {
    await _loadData();
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // 辅助加载函数
    void safeLoad(
      String key,
      List<dynamic> list,
      Function(Map<String, dynamic>) factory,
    ) {
      String? jsonStr = prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(jsonStr) as List;
          list.clear();
          for (var item in decoded) {
            try {
              list.add(factory(item));
            } catch (e) {
              debugPrint("跳过损坏数据: $e");
            }
          }
        } catch (e) {
          debugPrint("加载 $key 失败: $e");
        }
      }
    }

    // 1. 加载数据
    safeLoad('timerTasks', _timerTasks, (e) => TaskItem.fromJson(e));
    safeLoad('dailyTasks', _dailyTasks, (e) => TaskItem.fromJson(e));
    safeLoad('normalTasks', _normalTasks, (e) => TaskItem.fromJson(e));
    safeLoad('cycleTasks', _cycleTasks, (e) => CycleTask.fromJson(e));

    // 2. 每日重置逻辑 (正常版)
    String? lastOpenDate = prefs.getString('lastOpenDate');
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 只有当“上次打开日期”不等于“今天”时，才重置
    if (lastOpenDate != todayStr) {
      for (var t in _dailyTasks) {
        t.isCompleted = false;
      }
      for (var t in _timerTasks) {
        t.durationSeconds = 0; // 专注时长归零
      }

      // 更新本地存储的日期为今天
      prefs.setString('lastOpenDate', todayStr);
    }

    // 3. 重新计算周期
    _recalcAllCycles();

    // 4. 标记加载完成
    _hasLoaded = true;
    notifyListeners();
  }

  // 每日重置逻辑抽离
  void _checkDailyReset(SharedPreferences prefs) {
    String? lastOpenDate = prefs.getString('lastOpenDate');
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (lastOpenDate != todayStr) {
      for (var t in _dailyTasks) t.isCompleted = false;
      // [需求] 每日0点自动重置专注模块
      for (var t in _timerTasks) t.durationSeconds = 0;

      prefs.setString('lastOpenDate', todayStr);
      // 注意：此处不直接 save，依赖后续操作或 _hasLoaded 后的保存
    }
  }

  Future<void> _saveData() async {
    if (!_hasLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'timerTasks',
      jsonEncode(_timerTasks.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      'dailyTasks',
      jsonEncode(_dailyTasks.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      'normalTasks',
      jsonEncode(_normalTasks.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      'cycleTasks',
      jsonEncode(_cycleTasks.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      'lastOpenDate',
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
  }

  // ==================== 导入导出 (保持原样) ====================
  String exportDataToJson() {
    final Map<String, dynamic> data = {
      'timerTasks': _timerTasks.map((e) => e.toJson()).toList(),
      'dailyTasks': _dailyTasks.map((e) => e.toJson()).toList(),
      'normalTasks': _normalTasks.map((e) => e.toJson()).toList(),
      'cycleTasks': _cycleTasks.map((e) => e.toJson()).toList(),
      'version': '1.0.4',
      'exportTime': DateTime.now().toIso8601String(),
    };
    return jsonEncode(data);
  }

  Future<bool> importDataFromJson(String jsonStr) async {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      List<TaskItem> tempTimer = [];
      List<TaskItem> tempDaily = [];
      List<TaskItem> tempNormal = [];
      List<CycleTask> tempCycle = [];

      if (data['timerTasks'] != null)
        tempTimer = (data['timerTasks'] as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      if (data['dailyTasks'] != null)
        tempDaily = (data['dailyTasks'] as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      if (data['normalTasks'] != null)
        tempNormal = (data['normalTasks'] as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      if (data['cycleTasks'] != null)
        tempCycle = (data['cycleTasks'] as List)
            .map((e) => CycleTask.fromJson(e))
            .toList();

      _timerTasks.clear();
      _timerTasks.addAll(tempTimer);
      _dailyTasks.clear();
      _dailyTasks.addAll(tempDaily);
      _normalTasks.clear();
      _normalTasks.addAll(tempNormal);
      _cycleTasks.clear();
      _cycleTasks.addAll(tempCycle);

      _hasLoaded = true;
      await _saveData();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== 专注计时逻辑 (核心修改) ====================

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

  // [新增] 手动退出聚焦模式
  void exitFocusMode() {
    _isFocusMode = false;
    notifyListeners();
  }

  void _startTimer(String id) async {
    _activeTimerId = id;
    WakelockPlus.enable();

    // 1. 启动后台服务保活
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) service.startService();
    } catch (e) {
      debugPrint("服务启动失败: $e");
    }

    // 2. 【核心修复】记录“锚点”：点击开始时的系统时间
    DateTime sessionStartTime = DateTime.now();

    // 获取任务当前的初始进度（作为基准值）
    int index = _timerTasks.indexWhere((t) => t.id == id);
    if (index == -1) return;
    int initialDuration = _timerTasks[index].durationSeconds;

    // 3. 【功能保留】启动聚焦模式倒计时 (保留你原本的逻辑)
    _focusModeTrigger?.cancel();
    // 这里设置为 30秒 (根据你之前的需求)，如果需要40秒可自行修改
    _focusModeTrigger = Timer(const Duration(seconds: 30), () {
      _isFocusMode = true;
      notifyListeners();
    });

    notifyListeners();

    // 4. 启动高频定时器 (200ms 检查一次，比 1s 更精准，防止卡顿漏秒)
    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      int index = _timerTasks.indexWhere((t) => t.id == id);
      if (index == -1) {
        stopTimer();
        return;
      }
      var task = _timerTasks[index];

      // 5. 【功能保留】跨天重置检测
      final prefs = await SharedPreferences.getInstance();
      String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (prefs.getString('lastOpenDate') != todayStr) {
        _checkDailyReset(prefs);
        notifyListeners();
        stopTimer(); // 跨天了，停止计时防止逻辑错乱
        return;
      }

      // 6. 【核心修复】绝对时间计算法 (解决计时变慢 BUG)
      // 公式：当前进度 = 初始进度 + (当前系统时间 - 开始系统时间)
      DateTime now = DateTime.now();
      int sessionElapsed = now.difference(sessionStartTime).inSeconds;
      int newDuration = initialDuration + sessionElapsed;

      // 如果计算结果没变（因为是200ms检查一次，可能还没过1秒），就不更新 UI
      if (newDuration == task.durationSeconds) return;

      // 更新数据
      task.durationSeconds = newDuration;

      // 7. 倒计时结束判断
      if (task.timerMode == TimerMode.countdown) {
        if (task.durationSeconds >= (task.targetSeconds ?? 0)) {
          task.durationSeconds = task.targetSeconds ?? 0;
          stopTimer(); // 停止计时
          _playAlarm(); // 播放铃声
        }
      }

      // 8. 数据保存 (减少 IO，逢 5 的倍数保存)
      if (task.durationSeconds % 5 == 0) _saveData();

      notifyListeners();
    });
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _activeTimerId = null;

    // [新增] 停止计时时，取消聚焦模式和触发器
    _focusModeTrigger?.cancel();
    _isFocusMode = false;

    // [新增] 停止播放音乐
    _audioPlayer.stop();

    WakelockPlus.disable();
    try {
      final service = FlutterBackgroundService();
      service.invoke("stopService");
    } catch (e) {}

    _saveData();
    notifyListeners();
  }

  void _playAlarm() async {
    try {
      // 1. 先停止之前可能正在播放的声音，防止重叠
      await _audioPlayer.stop();

      // 2. 设置为“停止模式”（播完一次就停）
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);

      // 设置为“媒体播放模式”
      // 默认的 lowLatency 模式容易切掉结尾，mediaPlayer 模式会完整缓冲
      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);

      // 3. 播放
      await _audioPlayer.play(AssetSource('audio/alarm0.wav'));

      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint("播放音效失败: $e");
    }
  }

  // ==================== 待办 & 周期 (保持不变) ====================
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

  void addCycleTask(
    String title,
    CycleFrequency freq,
    DateTime time,
    int? val,
  ) {
    DateTime next = _calculateNextRun(freq, time, val);
    _cycleTasks.add(
      CycleTask(
        id: const Uuid().v4(),
        title: title,
        frequency: freq,
        time: time,
        specificValue: val,
        nextRunTime: next,
      ),
    );
    _sortCycles();
    _saveData();
    notifyListeners();
  }

  void updateCycleTask(
    CycleTask task,
    String title,
    CycleFrequency freq,
    DateTime time,
    int? val,
  ) {
    task.title = title;
    task.frequency = freq;
    task.time = time;
    task.specificValue = val;
    task.nextRunTime = _calculateNextRun(freq, time, val);
    _sortCycles();
    _saveData();
    notifyListeners();
  }

  void deleteCycleTask(String id) {
    _cycleTasks.removeWhere((t) => t.id == id);
    _saveData();
    notifyListeners();
  }

  DateTime _calculateNextRun(CycleFrequency freq, DateTime time, int? val) {
    DateTime now = DateTime.now();
    DateTime target = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    switch (freq) {
      case CycleFrequency.daily:
        if (target.isBefore(now)) target = target.add(const Duration(days: 1));
        break;
      case CycleFrequency.weekly:
        int diff = (val ?? 1) - now.weekday;
        if (diff < 0 || (diff == 0 && target.isBefore(now))) diff += 7;
        target = target.add(Duration(days: diff));
        break;
      case CycleFrequency.monthly:
        target = DateTime(
          now.year,
          now.month,
          val ?? 1,
          time.hour,
          time.minute,
        );
        if (target.isBefore(now))
          target = DateTime(
            now.year,
            now.month + 1,
            val ?? 1,
            time.hour,
            time.minute,
          );
        break;
      case CycleFrequency.yearly:
        target = DateTime(
          now.year,
          time.month,
          time.day,
          time.hour,
          time.minute,
        );
        if (target.isBefore(now))
          target = DateTime(
            now.year + 1,
            time.month,
            time.day,
            time.hour,
            time.minute,
          );
        break;
    }
    return target;
  }

  void _sortCycles() {
    _cycleTasks.sort((a, b) => a.nextRunTime.compareTo(b.nextRunTime));
  }

  void _recalcAllCycles() {
    for (var t in _cycleTasks) {
      t.nextRunTime = _calculateNextRun(t.frequency, t.time, t.specificValue);
    }
    _sortCycles();
  }
}
