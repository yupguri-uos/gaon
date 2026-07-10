import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 받는 사람(교사) 목록 — Teacher 엔티티가 schema에 없어(SSOT 결정 대기)
/// 기기 로컬에서 관리한다. BE 엔드포인트가 생기면 이 저장소만 교체하면 된다.
class TeacherStore {
  static const _key = 'teachers.v1';

  static final teachers = ValueNotifier<List<({String name, String role})>>([
    (name: '박지수 선생님', role: '2학년 3반 담임'),
    (name: '김민정 선생님', role: '영어 전담'),
    (name: '이현우 선생님', role: '체육 전담'),
  ]);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = [
        for (final e in jsonDecode(raw) as List)
          (name: e['name'] as String, role: e['role'] as String),
      ];
      if (list.isNotEmpty) teachers.value = list;
    } catch (_) {} // 손상된 저장값은 무시하고 기본 목록 유지
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key,
        jsonEncode([
          for (final t in teachers.value) {'name': t.name, 'role': t.role},
        ]));
  }

  static Future<void> add(String name, String role) async {
    teachers.value = [...teachers.value, (name: name, role: role)];
    await _persist();
  }

  static Future<void> removeAt(int index) async {
    if (teachers.value.length <= 1) return; // 최소 1명 유지
    teachers.value = [...teachers.value]..removeAt(index);
    await _persist();
  }
}
