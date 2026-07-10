import 'package:flutter/foundation.dart';

import '../models/schema.dart';

/// 앱 병기 언어 = 사용자 모국어(vi/zh).
/// 온보딩 언어 선택·로그인 시 세팅되고, 루트(main.dart)가 구독해 전 화면을 리빌드한다.
final appLanguage = ValueNotifier<NativeLanguage>(NativeLanguage.vi);

/// UI 병기 텍스트 선택 — bi(베트남어, 중국어).
/// 서버 콘텐츠(번역 결과 등)는 이미 사용자 언어로 오므로 UI 크롬에만 쓴다.
String bi(String vi, String zh) =>
    appLanguage.value == NativeLanguage.zh ? zh : vi;
