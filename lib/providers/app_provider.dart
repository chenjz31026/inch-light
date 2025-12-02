import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../constants/app_colors.dart';
import '../models/task_model.dart';

class AppProvider with ChangeNotifier {
  final List<TaskItem> _timerTasks = [];
  final List<TaskItem> _dailyTasks = [];
  final List<TaskItem> _normalTasks = [];
  final List<CycleTask> _cycleTasks = [];

  Timer? _timer;
  String? _activeTimerId;

  // 【关键修复】数据加载完成标志位
  bool _hasLoaded = false;

  List<TaskItem> get timerTasks => _timerTasks;
  List<TaskItem> get dailyTasks => _dailyTasks;
  List<TaskItem> get normalTasks => _normalTasks;
  List<CycleTask> get cycleTasks => _cycleTasks;
  String? get activeTimerId => _activeTimerId;

  AppProvider() {
    _initData();
  }

  // ==================== 数据持久化 (重写版) ====================

  Future<void> _initData() async {
    await _loadData();
    _hasLoaded = true; // 只有加载完了，才允许保存
    notifyListeners();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // 辅助加载函数：带异常捕获，防止一条坏数据炸掉整个列表
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

    safeLoad('timerTasks', _timerTasks, (e) => TaskItem.fromJson(e));
    safeLoad('dailyTasks', _dailyTasks, (e) => TaskItem.fromJson(e));
    safeLoad('normalTasks', _normalTasks, (e) => TaskItem.fromJson(e));
    safeLoad('cycleTasks', _cycleTasks, (e) => CycleTask.fromJson(e));

    // 每日重置逻辑
    String? lastOpenDate = prefs.getString('lastOpenDate');
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (lastOpenDate != todayStr) {
      for (var t in _dailyTasks) t.isCompleted = false;
      for (var t in _timerTasks) t.durationSeconds = 0;
      prefs.setString('lastOpenDate', todayStr);
      // 这里不调用 _saveData，因为 _hasLoaded 还没变 true，我们只更新内存状态
    }

    _recalcAllCycles();
  }

  Future<void> _saveData() async {
    // 【严重BUG修复】如果数据还没加载完，绝对禁止写入，否则会把空列表覆盖到硬盘
    if (!_hasLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    // 使用 await 确保写入完成
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

  // ==================== 导入导出功能 ====================

  String exportDataToJson() {
    final Map<String, dynamic> data = {
      'timerTasks': _timerTasks.map((e) => e.toJson()).toList(),
      'dailyTasks': _dailyTasks.map((e) => e.toJson()).toList(),
      'normalTasks': _normalTasks.map((e) => e.toJson()).toList(),
      'cycleTasks': _cycleTasks.map((e) => e.toJson()).toList(),
      'version': '1.0.3',
      'exportTime': DateTime.now().toIso8601String(),
    };
    return jsonEncode(data);
  }

  Future<bool> importDataFromJson(String jsonStr) async {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      // 临时列表，防止解析一半失败导致数据丢失
      List<TaskItem> tempTimer = [];
      List<TaskItem> tempDaily = [];
      List<TaskItem> tempNormal = [];
      List<CycleTask> tempCycle = [];

      if (data['timerTasks'] != null) {
        tempTimer = (data['timerTasks'] as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      }
      if (data['dailyTasks'] != null) {
        tempDaily = (data['dailyTasks'] as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      }
      if (data['normalTasks'] != null) {
        tempNormal = (data['normalTasks'] as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      }
      if (data['cycleTasks'] != null) {
        tempCycle = (data['cycleTasks'] as List)
            .map((e) => CycleTask.fromJson(e))
            .toList();
      }

      // 解析成功，应用数据
      _timerTasks.clear();
      _timerTasks.addAll(tempTimer);
      _dailyTasks.clear();
      _dailyTasks.addAll(tempDaily);
      _normalTasks.clear();
      _normalTasks.addAll(tempNormal);
      _cycleTasks.clear();
      _cycleTasks.addAll(tempCycle);

      _hasLoaded = true; // 强制标记为已加载
      await _saveData(); // 立即保存
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("导入失败: $e");
      return false;
    }
  }

  // ==================== 业务逻辑 (保持不变，但每次操作都 await _saveData) ====================

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

  void toggleTimer(String id) {
    if (_activeTimerId == id) {
      stopTimer();
    } else {
      stopTimer();
      _startTimer(id);
    }
  }

  void _startTimer(String id) async {
    _activeTimerId = id;
    WakelockPlus.enable();

    // 尝试启动服务，如果失败不影响主逻辑
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        service.startService();
      }
    } catch (e) {
      debugPrint("服务启动失败: $e");
    }

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
    WakelockPlus.disable();

    try {
      final service = FlutterBackgroundService();
      service.invoke("stopService");
    } catch (e) {
      // 忽略服务停止错误
    }

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

  // 周期任务逻辑
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
