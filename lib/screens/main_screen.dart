import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 剪贴板
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import 'timer_page.dart';
import 'todo_page.dart';
import 'cycle_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = const [TimerPage(), TodoPage(), CyclePage()];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);

    return Scaffold(
      body: Column(
        children: [
          // 顶部导航栏
          Container(
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 16,
              24,
              16,
            ),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text(
                  "寸光",
                  style: TextStyle(
                    fontFamily: 'ArtFont', // 确保本地字体已配置
                    fontSize: 36,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),

                // 【新增】数据备份/恢复按钮
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'export') _handleExport(context, provider);
                    if (value == 'import') _handleImport(context, provider);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.copy, size: 18, color: AppColors.textDark),
                          SizedBox(width: 8),
                          Text("备份数据 (复制)"),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(
                            Icons.paste,
                            size: 18,
                            color: AppColors.textDark,
                          ),
                          SizedBox(width: 8),
                          Text("恢复数据 (粘贴)"),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.cloud_sync_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          "备份/恢复",
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(child: _pages[_currentIndex]),

          Container(
            width: double.infinity,
            color: AppColors.bg,
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              "All rights reserved: Symplatt",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[400],
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
            BottomNavigationBarItem(
              icon: Icon(Icons.update),
              activeIcon: Icon(Icons.history_toggle_off),
              label: '周期',
            ),
          ],
        ),
      ),
    );
  }

  // 导出逻辑
  void _handleExport(BuildContext context, AppProvider provider) {
    final jsonStr = provider.exportDataToJson();
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("数据已复制到剪贴板，请粘贴到备忘录保存")));
  }

  // 导入逻辑
  void _handleImport(BuildContext context, AppProvider provider) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("剪贴板为空")));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认恢复？"),
        content: const Text("这将覆盖当前所有数据，且无法撤销。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              bool success = await provider.importDataFromJson(data.text!);
              if (success && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("数据恢复成功！")));
              } else if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("数据格式错误，恢复失败")));
              }
            },
            child: const Text("确定覆盖", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
