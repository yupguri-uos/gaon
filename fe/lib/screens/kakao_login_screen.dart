import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/api_config.dart';
import '../theme/tokens.dart';

/// 카카오 로그인 결과 — GAON JWT + 온보딩 필요 여부.
typedef KakaoLoginResult = ({String accessToken, bool needsOnboarding});

/// F-ON-3: 카카오 OAuth 웹뷰.
/// BE의 GET /auth/kakao/login(카카오로 302)을 열고, 콜백(/auth/kakao/callback)이
/// 반환하는 JSON(LoginResponse)에서 access_token을 회수해 pop으로 돌려준다.
/// 쿠키(state) 검증은 같은 웹뷰 세션 안에서 자동으로 통과된다.
class KakaoLoginScreen extends StatefulWidget {
  const KakaoLoginScreen({super.key});

  @override
  State<KakaoLoginScreen> createState() => _KakaoLoginScreenState();
}

class _KakaoLoginScreenState extends State<KakaoLoginScreen> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(GaonColors.bg)
    ..setNavigationDelegate(NavigationDelegate(
      onPageFinished: _onPageFinished,
    ))
    ..loadRequest(Uri.parse('$gaonApiBase/auth/kakao/login'));

  bool _handled = false;

  Future<void> _onPageFinished(String url) async {
    if (_handled || !url.contains('/auth/kakao/callback')) return;
    // 콜백 페이지 본문 = LoginResponse JSON — 웹뷰에서 그대로 읽는다.
    final raw = (await _controller
            .runJavaScriptReturningResult('document.body.innerText'))
        .toString();
    String body = raw;
    try {
      // 플랫폼에 따라 결과가 한 번 더 문자열로 감싸져 온다("{\"...\"}")
      final unwrapped = jsonDecode(raw);
      if (unwrapped is String) body = unwrapped;
    } catch (_) {}
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final token = json['access_token'] as String?;
      if (token == null || token.isEmpty) return;
      _handled = true;
      if (!mounted) return;
      Navigator.of(context).pop<KakaoLoginResult>((
        accessToken: token,
        needsOnboarding: json['needs_onboarding'] as bool? ?? true,
      ));
    } catch (_) {
      // 콜백이 에러 JSON/HTML이면 그대로 웹뷰에 노출 — 사용자가 닫고 재시도
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      appBar: AppBar(
        backgroundColor: GaonColors.surface,
        foregroundColor: GaonColors.textPrimary,
        title: Text('카카오 로그인',
            style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
