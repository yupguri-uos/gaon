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
    // 언어 전환 시 탭 전체를 새로 그린다(아래 KeyedSubtree와 한 쌍)
    appLanguage.addListener(_onTabChanged);
    // 병기 언어 = 사용자 모국어(vi/zh)
    repository.getCurrentUser().then(
      (u) => appLanguage.value = u.nativeLanguage,
    );
  }

  @override
  void dispose() {
    mainTabIndex.removeListener(_onTabChanged);
    appLanguage.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      // const 화면은 리빌드를 건너뛰므로, 언어가 바뀌면 key로 탭 전체를 재생성
      // (bi()가 build 시점에 평가돼 — 재생성 없이는 옛 언어가 남는다)
      body: KeyedSubtree(
        key: ValueKey(appLanguage.value),
        child: IndexedStack(
          index: _index,
          children: [
            const ChatScreen(),
            const CalendarScreen(),
            const MessageScreen(),
            const SettingsScreen(),
          ],
        ),
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
                label: bi('Thông báo', '通知单'),
                sub: '알림장',
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
                label: bi('Lịch', '日历'),
                sub: '캘린더',
                icon: Icon(
                  Icons.calendar_month_rounded,
                  size: 20,
                  color: _color(1),
                ),
              ),
              _tab(
                2,
                label: bi('Tin nhắn', '短信'),
                sub: '문자',
                icon: Icon(Icons.chat_rounded, size: 20, color: _color(2)),
              ),
              _tab(
                3,
                label: bi('Cài đặt', '设置'),
                sub: '설정',
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

  // 탭 라벨 — 모국어(주) + 한국어(병기, 더 작게)
  Widget _tab(
    int i, {
    required String label,
    required String sub,
    required Widget icon,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () => mainTabIndex.value = i,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: _index == i ? FontWeight.w700 : FontWeight.w400,
                  color: _color(i),
                ),
              ),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 8,
                  color: GaonColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
