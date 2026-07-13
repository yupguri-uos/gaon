import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 받는 사람(교사) — **FE 로컬 전용 모델. shared-schema 엔티티가 아니다.**
/// 팀 결정(2026-07-13): Teacher는 스키마·DB·BE에 만들지 않고
/// 기기 로컬(shared_preferences)로만 관리한다.
class Teacher {
  const Teacher({required this.name, required this.role});

  final String name;
  final String role; // 직책/과목 (예: 3학년 1반 담임, 영어 전담)

  Map<String, dynamic> toJson() => {'name': name, 'role': role};

  factory Teacher.fromJson(Map<String, dynamic> json) =>
      Teacher(name: json['name'] as String, role: json['role'] as String);
}

/// 자녀별 교사 목록 저장소(F-TCH) — child_id를 키로 기기 로컬에 저장.
/// 초기 상태는 빈 목록(데모 교사 프리셋 제거, QA T-1) — 화면이 추가를 유도한다.
class TeacherStore {
  TeacherStore._();

  // v1(전역 단일 목록·데모 프리셋)은 폐기 — v2 = { child_id: [Teacher...] }
  static const _key = 'teachers.v2';

  /// child_id → 교사 목록. 화면은 이 노티파이어를 구독해 갱신을 반영한다.
  static final teachers = ValueNotifier<Map<String, List<Teacher>>>(const {});

  /// 앱 시작 시 1회 호출(main.dart) — 저장된 목록을 메모리로 올린다.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      teachers.value = {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          key: [
            for (final t in value as List)
              Teacher.fromJson(t as Map<String, dynamic>),
          ],
      };
    } catch (_) {} // 손상된 저장값은 무시 — 빈 목록에서 다시 시작
  }

  /// 해당 자녀의 교사 목록(없으면 빈 목록).
  static List<Teacher> forChild(String childId) =>
      teachers.value[childId] ?? const [];

  static Future<void> add(String childId, Teacher teacher) async {
    _set(childId, [...forChild(childId), teacher]);
    await _persist();
  }

  static Future<void> update(String childId, int index, Teacher teacher) async {
    final list = [...forChild(childId)];
    if (index < 0 || index >= list.length) return;
    list[index] = teacher;
    _set(childId, list);
    await _persist();
  }

  static Future<void> removeAt(String childId, int index) async {
    final list = [...forChild(childId)];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    _set(childId, list);
    await _persist();
  }

  static void _set(String childId, List<Teacher> list) {
    teachers.value = {...teachers.value, childId: list};
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final MapEntry(:key, :value) in teachers.value.entries)
            key: [for (final t in value) t.toJson()],
        }),
      );
    } catch (_) {} // 영속화 실패해도 세션 내 목록은 유지
  }

  /// 테스트 전용 — 메모리 상태 초기화.
  @visibleForTesting
  static void reset() => teachers.value = const {};
}
