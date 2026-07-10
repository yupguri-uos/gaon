import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_lang.dart';
import '../models/schema.dart' as schema;

/// 잠금화면 리마인드 알림 (F-PRO-2·3의 FE 로컬 표면).
///
/// 정식 설계는 BE 스케줄러 + FCM 푸시(SSOT §3·§11)이고 그건 P2에서 배선한다.
/// 이 서비스는 앱 내 캘린더 일정 기반의 **로컬 예약 알림**으로,
/// FCM 없이도 마감 D-2 리마인드가 잠금화면에 뜨게 한다(데모 필수 경로).
/// FCM 수신이 붙어도 로컬 리마인드는 오프라인 보완으로 공존 가능.
class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channel = AndroidNotificationDetails(
    'gaon_reminder',
    '가온 리마인드',
    channelDescription: '마감·행사 리마인드 알림',
    importance: Importance.max,
    priority: Priority.high,
  );

  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
    ),
  );

  /// 앱 시작 시 1회 호출. 웹은 로컬 알림 미지원이라 no-op.
  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );
    // Android 13+ 런타임 권한
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// 캘린더 저장(F-DOC-7) 시 호출 — 마감 이벤트는 D-2 09:00,
  /// 행사 이벤트는 전날 09:00에 리마인드를 예약한다(F-PRO-2·3).
  /// 이미 지난 시각은 조용히 건너뛴다(데모 고정 날짜 대응).
  Future<int> scheduleEventReminders(List<schema.CalendarEvent> events) async {
    if (kIsWeb) return 0;
    await init();
    var scheduled = 0;
    for (final e in events) {
      final isDeadline = e.type == schema.CalendarEventType.deadline;
      final fireDate = e.date.subtract(Duration(days: isDeadline ? 2 : 1));
      final fireAt = tz.TZDateTime(
        tz.local,
        fireDate.year,
        fireDate.month,
        fireDate.day,
        9,
      );
      if (fireAt.isBefore(tz.TZDateTime.now(tz.local))) continue;

      await _plugin.zonedSchedule(
        id: e.hashCode & 0x7fffffff, // 이벤트별 안정 id
        title: isDeadline
            ? '⏰ 마감 임박 (D-2) · ${bi('Sắp đến hạn', '截止临近')}'
            : '📅 내일 일정 · ${bi('Ngày mai', '明天日程')}',
        body: '${e.title} — ${e.date.month}/${e.date.day}',
        scheduledDate: fireAt,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      scheduled++;
    }
    return scheduled;
  }

  /// 시연용 미리보기 — [delay] 후 알림 발화.
  /// 누르고 기기를 잠그면 잠금화면에서 확인할 수 있다.
  Future<void> schedulePreview(
    schema.Notification notification, {
    Duration delay = const Duration(seconds: 5),
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.zonedSchedule(
      id: 0,
      title: notification.titleNative,
      body: notification.bodyNative,
      scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
