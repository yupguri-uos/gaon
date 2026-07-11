import 'package:flutter/material.dart';

import '../data/app_lang.dart';
import '../data/app_nav.dart';
import '../data/locator.dart';
import '../theme/tokens.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'message_screen.dart';
import 'settings_screen.dart';

/// 하단 탭 셸 — 알림장(챗봇) / 캘린더 / 문자 / 설정.
/// v2 디자인: 챗봇이 메인 허브(Chain A), 문자 탭이 Chain B.
/// 탭 상태는 app_nav.mainTabIndex와 동기화(외부 화면에서 탭 전환 가능).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int get _index => mainTabIndex.value;

  @override
  void initState() {
    super.initState();
    mainTabIndex.addListener(_onTabChanged);
    // 병기 언어 = 사용자 모국어(vi/zh)
    repository.getCurrentUser().then(
      (u) => appLanguage.value = u.nativeLanguage,
    );
  }

  @override
  void dispose() {
    mainTabIndex.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          const ChatScreen(),
          const CalendarScreen(),
          const MessageScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: GaonColors.surface,
          border: Border(top: BorderSide(color: GaonColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _tab(
                0,
                label: '알림장',
                icon: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/gaon_icon.png',
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              _tab(
                1,
                label: '캘린더',
                icon: Icon(
                  Icons.calendar_month_rounded,
                  size: 20,
                  color: _color(1),
                ),
              ),
              _tab(
                2,
                label: '문자',
                icon: Icon(Icons.chat_rounded, size: 20, color: _color(2)),
              ),
              _tab(
                3,
                label: '설정',
                icon: Icon(Icons.settings_rounded, size: 20, color: _color(3)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _color(int i) =>
      _index == i ? GaonColors.textPrimary : GaonColors.textSecondary;

  Widget _tab(int i, {required String label, required Widget icon}) {
    return Expanded(
      child: InkWell(
        onTap: () => mainTabIndex.value = i,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: _index == i ? FontWeight.w700 : FontWeight.w400,
                  color: _color(i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
