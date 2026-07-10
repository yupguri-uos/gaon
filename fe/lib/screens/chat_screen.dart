import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/locator.dart';
import '../data/notification_service.dart';
import '../data/picked_image_store.dart';
import '../data/repository.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'action_card_screen.dart';

/// 알림장 탭 = Chain A 허브. 한 화면에서 상태 전환:
/// S4 빈 상태(업로드) → S5 분석 중(Document.status 폴링) → S6 번역 결과.
/// S7 단어 해설 바텀시트 · S8 캘린더 저장 다이얼로그 포함.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.onGoToCalendar});

  /// 캘린더 저장 후 캘린더 탭으로 전환 (셸이 주입).
  final VoidCallback? onGoToCalendar;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _Phase { idle, analyzing, result }

class _ChatScreenState extends State<ChatScreen> {
  _Phase _phase = _Phase.idle;
  DocStatus _status = DocStatus.uploaded;
  DocumentAnalysis? _analysis;
  List<Child> _children = const [];
  Child? _selectedChild;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    repository.getChildren().then((children) {
      if (!mounted) return;
      setState(() {
        _children = children;
        _selectedChild = children.firstOrNull;
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// F-DOC-1: 사진 소스 선택 — 카메라 촬영 / 갤러리 / 데모 알림장.
  Future<void> _pickAndUpload() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: GaonColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('알림장 사진 · Ảnh thông báo',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.sm),
              for (final (value, icon, ko, vi) in const [
                ('camera', Icons.photo_camera_rounded, '카메라로 촬영', 'Chụp ảnh'),
                ('gallery', Icons.photo_library_rounded, '갤러리에서 선택',
                    'Chọn từ thư viện'),
                ('demo', Icons.description_rounded, '데모 알림장 사용',
                    'Dùng ảnh mẫu'),
              ])
                ListTile(
                  onTap: () => Navigator.of(context).pop(value),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GaonRadius.md)),
                  leading: IconCircle(
                    bg: GaonColors.primaryLight,
                    child:
                        Icon(icon, size: 16, color: GaonColors.textPrimary),
                  ),
                  title: Text(ko,
                      style: GaonType.bodyLg
                          .copyWith(color: GaonColors.textPrimary)),
                  subtitle: Text(vi,
                      style: GaonType.micro
                          .copyWith(color: GaonColors.textSecondary)),
                ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    String imageRef;
    if (source == 'demo') {
      imageRef = 'demo://notice.jpg';
    } else {
      final picked = await ImagePicker().pickImage(
        source:
            source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600, // LLM 파싱에 충분 + 업로드 용량 절약
        imageQuality: 85,
      );
      if (picked == null) return; // 사용자가 취소
      imageRef = PickedImageStore.register(await picked.readAsBytes());
    }
    if (!mounted) return;
    await _upload(imageRef);
  }

  /// 업로드·폴링 실패 시 안내 후 초기 화면 복귀(시연 가드 — 멈춘 화면 방지).
  void _failBack(String message) {
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _upload(String imageRef) async {
    setState(() {
      _phase = _Phase.analyzing;
      _status = DocStatus.uploaded;
    });
    final Document doc;
    try {
      doc = await repository.uploadDocument(
        imageRef: imageRef,
        childId: _selectedChild?.childId,
      );
    } catch (e) {
      _failBack('업로드에 실패했어요 — 네트워크를 확인해 주세요');
      return;
    }
    if (!mounted) return;
    // 실서버 Chain A는 LLM 호출이라 폴링 간격을 1초로(과호출 방지).
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      try {
        final updated = await repository.getDocument(doc.documentId);
        if (!mounted) return;
        setState(() => _status = updated.status);
        if (updated.status == DocStatus.failed) {
          t.cancel();
          _failBack('분석에 실패했어요 — 다시 시도해 주세요');
          return;
        }
        if (updated.status == DocStatus.done) {
          t.cancel();
          final analysis =
              await repository.getDocumentAnalysis(doc.documentId);
          if (!mounted) return;
          setState(() {
            _analysis = analysis;
            _phase = _Phase.result;
          });
        }
      } catch (e) {
        t.cancel();
        _failBack('분석 상태를 확인하지 못했어요 — 네트워크를 확인해 주세요');
      }
    });
  }

  Future<void> _pickChild() async {
    final picked = await showModalBottomSheet<Child>(
      context: context,
      backgroundColor: GaonColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('자녀 선택 · Chọn con',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.sm),
              for (final c in _children)
                ListTile(
                  onTap: () => Navigator.of(context).pop(c),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GaonRadius.md)),
                  tileColor: c.childId == _selectedChild?.childId
                      ? GaonColors.primaryLight
                      : null,
                  title: Text(_childLabel(c),
                      style: GaonType.bodyLg
                          .copyWith(color: GaonColors.textPrimary)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _selectedChild = picked);
  }

  String _childLabel(Child c) {
    final gradeNo = c.grade.wire.split('_').last;
    final cls = c.classNo != null ? ' $gradeNo학년 ${c.classNo}반' : '';
    return '${c.name ?? '자녀'} ·$cls';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // 헤더 — 자녀 선택기
          Container(
            decoration: const BoxDecoration(
              color: GaonColors.surface,
              border: Border(bottom: BorderSide(color: GaonColors.border)),
            ),
            padding: const EdgeInsets.symmetric(
                vertical: GaonSpace.sm, horizontal: GaonSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      switch (_phase) {
                        _Phase.idle => '알림장',
                        _Phase.analyzing => '알림장 분석 중...',
                        _Phase.result => '번역 완료',
                      },
                      style: GaonType.h3
                          .copyWith(color: GaonColors.textPrimary)),
                ),
                if (_selectedChild != null)
                  Material(
                    color: GaonColors.textPrimary,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                    child: InkWell(
                      onTap: _pickChild,
                      borderRadius: BorderRadius.circular(GaonRadius.pill),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_childLabel(_selectedChild!),
                                style: GaonType.label
                                    .copyWith(color: GaonColors.onPrimary)),
                            const SizedBox(width: 6),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 14, color: GaonColors.onPrimary),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: switch (_phase) {
              _Phase.idle => _EmptyState(onUpload: _pickAndUpload),
              _Phase.analyzing => _LoadingState(status: _status),
              _Phase.result => _ResultState(
                  analysis: _analysis!,
                  onGoToCalendar: widget.onGoToCalendar,
                ),
            },
          ),
        ],
      ),
    );
  }
}

// ── S4: 빈 상태 ────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GaonSpace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: GaonColors.primary,
              boxShadow: GaonShadow.dark,
            ),
            child: const Icon(Icons.photo_camera_rounded,
                size: 38, color: GaonColors.textPrimary),
          ),
          const SizedBox(height: GaonSpace.md),
          Text('알림장을 올려주세요',
              style: GaonType.h2.copyWith(color: GaonColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Gửi ảnh thông báo từ trường',
              style: GaonType.body.copyWith(color: GaonColors.textSecondary)),
          const SizedBox(height: 4),
          Text('사진 촬영 또는 갤러리에서 선택',
              style:
                  GaonType.caption.copyWith(color: GaonColors.textSecondary)),
          const SizedBox(height: GaonSpace.md),
          GaonButton(
            label: '사진 올리기',
            subLabel: 'Tải ảnh lên',
            icon: const Icon(Icons.upload_rounded,
                size: 16, color: GaonColors.onPrimary),
            onTap: onUpload,
          ),
        ],
      ),
    );
  }
}

// ── S5: 분석 중 (F-DOC-1·4 — status 폴링) ─────────────────────────
class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.status});

  final DocStatus status;

  static const _steps = [
    (label: '글자 읽기', vi: 'Đọc chữ'),
    (label: '정보 정리', vi: 'Sắp xếp'),
    (label: '번역 중', vi: 'Đang dịch...'),
    (label: '할 일 추출', vi: 'Tạo việc'),
  ];

  int get _activeStep => switch (status) {
        DocStatus.uploaded => 0,
        DocStatus.parsing => 1,
        DocStatus.translating => 2,
        DocStatus.action => 3,
        DocStatus.done => 4,
        DocStatus.failed => 0,
      };

  double get _progress => switch (status) {
        DocStatus.uploaded => 0.08,
        DocStatus.parsing => 0.33,
        DocStatus.translating => 0.66,
        DocStatus.action => 0.9,
        DocStatus.done => 1.0,
        DocStatus.failed => 0.0,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GaonSpace.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 발자국 로고가 아래에서 차오르는 진행 표시
          TweenAnimationBuilder<double>(
            tween: Tween(end: _progress),
            duration: const Duration(milliseconds: 400),
            builder: (context, value, _) => Column(
              children: [
                CustomPaint(
                  size: const Size(110, 130),
                  painter: _PawFillPainter(progress: value),
                ),
                const SizedBox(height: 2),
                Text('${(value * 100).round()}%',
                    style: GaonType.h3.copyWith(
                        fontWeight: FontWeight.w700,
                        color: GaonColors.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: GaonSpace.lg),

          // 단계 카드
          Container(
            padding: const EdgeInsets.symmetric(
                vertical: GaonSpace.xs, horizontal: GaonSpace.md),
            decoration: BoxDecoration(
              color: GaonColors.surface,
              borderRadius: BorderRadius.circular(GaonRadius.xl),
              boxShadow: GaonShadow.card,
            ),
            child: Column(
              children: [
                for (final (i, s) in _steps.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: i < _steps.length - 1
                          ? const Border(
                              bottom: BorderSide(color: GaonColors.border))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _activeStep
                                ? GaonColors.textPrimary
                                : GaonColors.primaryLight,
                          ),
                          child: i < _activeStep
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: GaonColors.onPrimary)
                              : Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: GaonColors.primary,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: GaonSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.label,
                                  style: GaonType.body.copyWith(
                                      fontWeight: i < _activeStep
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: i < _activeStep
                                          ? GaonColors.textPrimary
                                          : GaonColors.textSecondary)),
                              Text(s.vi,
                                  style: GaonType.micro.copyWith(
                                      color: GaonColors.textSecondary)),
                            ],
                          ),
                        ),
                        if (i == _activeStep)
                          const GaonBadge(
                              label: '진행중',
                              color: GaonColors.textPrimary,
                              bg: GaonColors.primary),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: GaonSpace.md),
          Text('거의 다 됐어요, 잠시만요 ☺',
              style: GaonType.label.copyWith(color: GaonColors.textSecondary)),
          Text('Sắp xong rồi...',
              style: GaonType.micro.copyWith(color: GaonColors.textSecondary)),
        ],
      ),
    );
  }
}

/// 가온 발자국(꽃) 로고 — 아래에서 위로 차오르는 진행 그래픽.
class _PawFillPainter extends CustomPainter {
  const _PawFillPainter({required this.progress});

  final double progress;

  void _drawPaw(Canvas canvas, Size size,
      {required Color toe, required Color pad}) {
    final w = size.width / 100;
    final h = size.height / 118;
    final toePaint = Paint()..color = toe;
    final padPaint = Paint()..color = pad;
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(35 * w, 30 * h), width: 30 * w, height: 40 * h),
        toePaint);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(65 * w, 30 * h), width: 30 * w, height: 40 * h),
        toePaint);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(30 * w, 78 * h), width: 46 * w, height: 60 * h),
        padPaint);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(70 * w, 78 * h), width: 46 * w, height: 60 * h),
        padPaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 미채움(연한 톤)
    _drawPaw(canvas, size,
        toe: GaonColors.successLight, pad: GaonColors.primaryLight);
    // 채움(진한 톤) — 아래에서 progress만큼만
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
        0, size.height * (1 - progress), size.width, size.height * progress));
    _drawPaw(canvas, size, toe: GaonColors.primary, pad: GaonColors.textPrimary);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PawFillPainter old) => old.progress != progress;
}

// ── S6: 번역 결과 ─────────────────────────────────────────────────
class _ResultState extends StatelessWidget {
  const _ResultState({required this.analysis, this.onGoToCalendar});

  final DocumentAnalysis analysis;
  final VoidCallback? onGoToCalendar;

  /// 원문에서 단어 해설 term을 하이라이트 span으로 변환.
  List<InlineSpan> _highlightedRawText(BuildContext context) {
    final raw = analysis.extractedItem.rawText;
    final terms = analysis.translated.terms;
    final spans = <InlineSpan>[];
    var cursor = 0;

    while (cursor < raw.length) {
      // 남은 텍스트에서 가장 먼저 나오는 term 탐색
      Term? nextTerm;
      var nextIndex = raw.length;
      for (final t in terms) {
        final idx = raw.indexOf(t.termKo, cursor);
        if (idx != -1 && idx < nextIndex) {
          nextIndex = idx;
          nextTerm = t;
        }
      }
      if (nextTerm == null) {
        spans.add(TextSpan(text: raw.substring(cursor)));
        break;
      }
      if (nextIndex > cursor) {
        spans.add(TextSpan(text: raw.substring(cursor, nextIndex)));
      }
      final term = nextTerm;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: () => _showTermSheet(context, term),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 5),
            decoration: BoxDecoration(
              color: GaonColors.textPrimary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(term.termKo,
                style: GaonType.label.copyWith(color: GaonColors.onPrimary)),
          ),
        ),
      ));
      cursor = nextIndex + term.termKo.length;
    }
    return spans;
  }

  // ── S7: 단어 해설 바텀시트 (Term = F-DOC-5) ──
  void _showTermSheet(BuildContext context, Term term) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: const Color(0x73011D14),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GaonColors.primary,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: GaonSpace.md),
              // 단어
              Container(
                padding: const EdgeInsets.all(GaonSpace.md),
                decoration: BoxDecoration(
                  color: GaonColors.textPrimary,
                  borderRadius: BorderRadius.circular(GaonRadius.xl),
                ),
                child: Column(
                  children: [
                    Text(term.termKo,
                        style: GaonType.h1.copyWith(
                            fontWeight: FontWeight.w800,
                            color: GaonColors.onPrimary)),
                    const SizedBox(height: 4),
                    Text(term.literalNative,
                        style: GaonType.caption
                            .copyWith(color: GaonColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: GaonSpace.md),
              // 설명
              Container(
                padding: const EdgeInsets.all(GaonSpace.sm),
                decoration: BoxDecoration(
                  color: GaonColors.bg,
                  borderRadius: BorderRadius.circular(GaonRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('설명 · Giải thích',
                        style: GaonType.micro.copyWith(
                            fontWeight: FontWeight.w600,
                            color: GaonColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(term.explanationNative,
                        style: GaonType.body.copyWith(
                            color: GaonColors.textPrimary, height: 1.65)),
                  ],
                ),
              ),
              const SizedBox(height: GaonSpace.md),
              GaonButton(
                label: '확인 · Đóng',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── S8: 캘린더 저장 다이얼로그 ──
  void _showCalSaveDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x73011D14),
      builder: (context) => Dialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GaonRadius.xxl)),
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: GaonColors.textPrimary),
                child: const Icon(Icons.calendar_month_rounded,
                    size: 26, color: GaonColors.onPrimary),
              ),
              const SizedBox(height: GaonSpace.sm),
              Text('캘린더에 저장할까요?',
                  style: GaonType.h2.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Lưu vào lịch không?',
                  style: GaonType.label
                      .copyWith(color: GaonColors.textSecondary)),
              const SizedBox(height: GaonSpace.md),
              for (final e in analysis.actionCard.calendarEvents.where(
                  (e) => e.childId == analysis.document.childId)) ...[
                _EventRow(event: e),
                const SizedBox(height: GaonSpace.xs),
              ],
              const SizedBox(height: GaonSpace.xs),
              Row(
                children: [
                  Expanded(
                    child: GaonButton(
                      variant: GaonButtonVariant.ghost,
                      label: '건너뛰기',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: GaonSpace.xs),
                  Expanded(
                    flex: 2,
                    child: GaonButton(
                      label: '✓ 저장하기 · Lưu',
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.of(context).pop();
                        // F-DOC-7: 앱 내 캘린더에 확정 저장
                        final saved = await repository.saveCalendarEvents(
                            documentId: analysis.document.documentId);
                        // F-PRO-2·3: 마감 D-2·행사 전날 잠금화면 리마인드 예약
                        await NotificationService.instance
                            .scheduleEventReminders(saved);
                        messenger.showSnackBar(SnackBar(
                            content: Text(
                                '일정 ${saved.length}개를 캘린더에 저장했어요 · Đã lưu')));
                        onGoToCalendar?.call();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(GaonSpace.md),
      children: [
        // 원문 — 단어 하이라이트
        Container(
          padding: const EdgeInsets.all(GaonSpace.sm),
          decoration: const BoxDecoration(
            color: GaonColors.primaryLight,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(GaonRadius.lg),
              topRight: Radius.circular(GaonRadius.lg),
              bottomRight: Radius.circular(GaonRadius.lg),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('원문 한국어',
                  style: GaonType.micro.copyWith(
                      fontWeight: FontWeight.w600,
                      color: GaonColors.textSecondary)),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: _highlightedRawText(context)),
                style: GaonType.body
                    .copyWith(color: GaonColors.textPrimary, height: 1.7),
              ),
            ],
          ),
        ),
        const SizedBox(height: GaonSpace.sm),

        // 번역
        Container(
          padding: const EdgeInsets.all(GaonSpace.sm),
          decoration: const BoxDecoration(
            color: GaonColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(GaonRadius.lg),
              bottomRight: Radius.circular(GaonRadius.lg),
              bottomLeft: Radius.circular(GaonRadius.lg),
            ),
            boxShadow: GaonShadow.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('번역 · Bản dịch (Tiếng Việt)',
                  style: GaonType.micro.copyWith(
                      fontWeight: FontWeight.w600,
                      color: GaonColors.textSecondary)),
              const SizedBox(height: 4),
              Text(analysis.translated.summaryNative,
                  style: GaonType.body
                      .copyWith(color: GaonColors.textPrimary, height: 1.7)),
            ],
          ),
        ),
        const SizedBox(height: GaonSpace.sm),

        // 단어 해설 칩
        Text('단어 해설 · Giải thích từ',
            style: GaonType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: GaonColors.textSecondary)),
        const SizedBox(height: GaonSpace.xs),
        Wrap(
          spacing: GaonSpace.xs,
          runSpacing: GaonSpace.xs,
          children: [
            for (final term in analysis.translated.terms)
              Material(
                color: GaonColors.textPrimary,
                borderRadius: BorderRadius.circular(GaonRadius.pill),
                child: InkWell(
                  onTap: () => _showTermSheet(context, term),
                  borderRadius: BorderRadius.circular(GaonRadius.pill),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 7, horizontal: 14),
                    child: Text('${term.termKo} ?',
                        style: GaonType.label
                            .copyWith(color: GaonColors.onPrimary)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: GaonSpace.md),

        // 액션
        Row(
          children: [
            Expanded(
              child: GaonButton(
                label: '📅 캘린더 저장',
                onTap: () => _showCalSaveDialog(context),
              ),
            ),
            const SizedBox(width: GaonSpace.xs),
            Expanded(
              child: GaonButton(
                variant: GaonButtonVariant.secondary,
                label: '📋 할 일 보기',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ActionCardScreen()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final urgent = event.type == CalendarEventType.deadline;
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: GaonSpace.xs, horizontal: GaonSpace.sm),
      decoration: BoxDecoration(
        color: urgent ? GaonColors.warningLight : GaonColors.bg,
        borderRadius: BorderRadius.circular(GaonRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: urgent ? GaonColors.warning : GaonColors.textPrimary,
            ),
            alignment: Alignment.center,
            child: Text('${event.date.month}/${event.date.day}',
                style: GaonType.micro.copyWith(
                    fontWeight: FontWeight.w700,
                    color: GaonColors.onPrimary)),
          ),
          const SizedBox(width: GaonSpace.sm),
          Expanded(
            child: Text(event.title,
                style: GaonType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: GaonColors.textPrimary)),
          ),
          Icon(Icons.check_rounded,
              size: 16,
              color: urgent ? GaonColors.warning : GaonColors.textPrimary),
        ],
      ),
    );
  }
}
