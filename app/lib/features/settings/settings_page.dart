import 'package:flutter/material.dart';

import '../../widgets/page_frame.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const PageFrame(
    title: '设置',
    subtitle: '首版设置入口。',
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('外观'),
        subtitle: Text('跟随 macOS 系统'),
      ),
      Divider(height: 1),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('运行与数据'),
        subtitle: Text('日志保留与本地数据设置将在后续阶段开放'),
      ),
    ],
  );
}
