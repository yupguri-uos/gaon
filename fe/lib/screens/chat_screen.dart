import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_lang.dart';
import '../data/app_nav.dart';
import '../data/locator.dart';
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
  const ChatScreen({super.key});

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
  // 홈(빈 상태)의 '다가오는 일정' — 리빌드마다 재요청하지 않게 캐시
  late Future<List<CalendarEvent>> _upcoming = repository.getCalendarEvents();

  @override
  void initState() {
    super.initState();
    childrenVersion.addListener(_reloadChildren);
    _reloadChildren();
  }

  @override
  void dispose() {
    childrenVersion.removeListener(_reloadChildren);
    _pollTimer?.cancel();
    super.dispose();
  }

  // 설정에서 자녀 정보가 바뀌면(childrenVersion) 이 탭도 다시 불러온다 —
  // IndexedStack이 이 화면을 계속 살려두므로 initState는 앱 켤 때 한 번뿐이라
  // 별도 신호 없이는 자녀 수정 결과가 반영되지 않는다.
  void _reloadChildren() {
    repository.getChildren().then((children) {
      if (!mounted) return;
      final currentId = _selectedChild?.childId;
      Child? matched;
      for (final c in children) {
        if (c.childId == currentId) {
          matched = c;
          break;
        }
      }
      setState(() {
        _children = children;
        _selectedChild = matched ?? children.firstOrNull;
      });
    });
  }

  /// F-DOC-1: 사진 소스 선택 — 카메라 촬영 / 갤러리 / 데모 알림장.
  Future<void> _pickAndUpload() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: GaonColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GaonRadius.xxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                biLine('알림장 사진', 'Ảnh thông báo', '通知单照片'),
                style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: GaonSpace.sm),
              for (final (value, icon, ko, native) in [
                (
                  'camera',
                  Icons.photo_camera_rounded,
                  '카메라로 촬영',
                  bi('Chụp ảnh', '拍照'),
                ),
                (
                  'gallery',
                  Icons.photo_library_rounded,
                  '갤러리에서 선택',
                  bi('Chọn từ thư viện', '从相册选择'),
                ),
                (
                  'demo',
                  Icons.description_rounded,
                  '데모 알림장 사용',
                  bi('Dùng ảnh mẫu', '使用示例通知单'),
                ),
              ])
                ListTile(
                  onTap: () => Navigator.of(context).pop(value),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GaonRadius.md),
                  ),
                  leading: IconCircle(
                    bg: GaonColors.primaryLight,
                    child: Icon(icon, size: 16, color: GaonColors.textPrimary),
                  ),
                  title: Text(
                    native,
                    style: GaonType.bodyLg.copyWith(
                      color: GaonColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    ko,
                    style: GaonType.micro.copyWith(
                      color: GaonColors.textSecondary,
                    ),
                  ),
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
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        // 카메라 원본은 수 MB라 nginx client_max_body_size(기본 1MB)에 걸려
        // 업로드가 413으로 즉시 실패했다 — 여기서 확실히 1MB 아래로 줄인다.
        // (근본 해결은 서버 nginx 한도 상향. 그때 이 값은 다시 올릴 수 있다.)
        maxWidth: 1280, // 손글씨 파싱에 충분 + 업로드 용량 안전
        imageQuality: 80,
      );
      if (picked == null) return; // 사용자가 취소
      imageRef = PickedImageStore.register(await picked.readAsBytes());
    }
    if (!mounted) return;
    await _upload(imageRef);
  }

  /// 홈(초기 화면)으로 — 잘못 진입했거나 새 알림장을 분석할 때(시연 가드).
  void _resetToHome() {
    _pollTimer?.cancel();
    setState(() {
      _phase = _Phase.idle;
      _upcoming = repository.getCalendarEvents(); // 저장분 반영
    });
  }

  /// 분석 중 홈 복귀는 실수로 흐름을 잃기 쉬워 확인을 받는다(QA 2026-07-11).
  Future<void> _confirmAbortAnalysis() async {
    final abort = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GaonColors.surface,
        title: Text(
          biLines('분석을 중단할까요?', 'Dừng phân tích thông báo?', '要中断分析吗？'),
          style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
        ),
        content: Text(
          biLines(
            '진행 중인 알림장 분석이 사라져요',
            'Phân tích đang chạy sẽ bị mất',
            '正在进行的分析将会丢失',
          ),
          style: GaonType.caption.copyWith(color: GaonColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              biLine('계속 분석', 'Tiếp tục', '继续分析'),
              style: GaonType.body.copyWith(color: GaonColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              biLine('중단', 'Dừng', '中断'),
              style: GaonType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: GaonColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
    if (abort == true && mounted) _resetToHome();
  }

  /// 업로드·폴링 실패 시 안내 후 초기 화면 복귀(시연 가드 — 멈춘 화면 방지).
  void _failBack(String message) {
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      // 원인을 터미널에 남긴다(413=사진 용량, SocketException=네트워크/서버).
      debugPrint('[upload] 실패: $e');
      // nginx client_max_body_size 초과(413)는 '네트워크'가 아니라 용량 문제 —
      // 사용자에게 원인에 맞는 안내를 준다(ApiException.toString()='API 413: ...').
      final tooLarge = e.toString().contains('413');
      _failBack(
        tooLarge
            ? biLines(
                '사진 용량이 너무 커요 — 다시 시도해 주세요',
                'Ảnh quá lớn — hãy thử lại',
                '照片太大——请重试',
              )
            : biLines(
                '업로드에 실패했어요 — 네트워크를 확인해 주세요',
                'Tải lên thất bại — hãy kiểm tra mạng',
                '上传失败——请检查网络',
              ),
      );
      return;
    }
    if (!mounted) return;
    // 실서버 Chain A는 LLM 호출이라 폴링 간격을 1초로(과호출 방지).
    var pollMisses = 0; // 일시적 네트워크/게이트웨이 오류 허용 횟수
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      try {
        final updated = await repository.getDocument(doc.documentId);
        if (!mounted) return;
        pollMisses = 0;
        setState(() => _status = updated.status);
        if (updated.status == DocStatus.failed) {
          t.cancel();
          _failBack(
            biLines(
              '알림장을 읽지 못했어요 — 알림장 사진이 맞는지 확인 후 다시 시도해 주세요',
              'Không đọc được thông báo — hãy kiểm tra ảnh và thử lại',
              '无法识别通知单——请确认照片后重试',
            ),
          );
          return;
        }
        if (updated.status == DocStatus.done) {
          t.cancel();
          // 타이머를 먼저 취소하므로 결과 조회 실패가 catch로 떨어지면 다음
          // tick이 없어 분석 화면에 영구 고착됐다(적대적 리뷰 A-1) —
          // 재시도·실패 안내가 있는 전용 경로로 처리해 반드시 벗어나게 한다.
          await _loadAnalysisOrFail(doc.documentId);
        }
      } catch (e) {
        // 분석이 오래 걸리는 동안 한두 번 응답이 튀어도 바로 포기하지 않는다
        if (++pollMisses < 5) return;
        t.cancel();
        _failBack(
          biLines(
            '분석 상태를 확인하지 못했어요 — 네트워크를 확인해 주세요',
            'Không kiểm tra được tiến trình — hãy kiểm tra mạng',
            '无法确认分析状态——请检查网络',
          ),
        );
      }
    });
  }

  /// done 이후 결과 조회 — 일시 오류(네트워크·§18.4 결과 미준비 방어)를
  /// 3회까지 1초 간격 재시도하고, 그래도 실패하면 _failBack으로 명시 안내.
  /// (폴링 타이머는 이미 취소된 뒤라 여기서 스스로 탈출을 보장해야 한다.)
  Future<void> _loadAnalysisOrFail(String documentId) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final analysis = await repository.getDocumentAnalysis(documentId);
        if (!mounted) return;
        setState(() {
          _analysis = analysis;
          _phase = _Phase.result;
        });
        return;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
      }
    }
    _failBack(
      biLines(
        '분석 결과를 불러오지 못했어요 — 잠시 후 다시 시도해 주세요',
        'Không tải được kết quả — hãy thử lại sau',
        '无法加载分析结果——请稍后再试',
      ),
    );
  }

  Future<void> _pickChild() async {
    final picked = await showModalBottomSheet<Child>(
      context: context,
      backgroundColor: GaonColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GaonRadius.xxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                biLine('자녀 선택', 'Chọn con', '选择孩子'),
                style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: GaonSpace.sm),
              // 다자녀가 많아도 시트가 넘치지 않게 목록만 스크롤(QA: 10명 overflow)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _children)
                      ListTile(
                        onTap: () => Navigator.of(context).pop(c),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(GaonRadius.md),
                        ),
                        tileColor: c.childId == _selectedChild?.childId
                            ? GaonColors.primaryLight
                            : null,
                        title: Text(
                          _childLabel(c),
                          style: GaonType.bodyLg.copyWith(
                            color: GaonColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
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
              vertical: GaonSpace.sm,
              horizontal: GaonSpace.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: BiText(
                    native: switch (_phase) {
                      _Phase.idle => bi('Thông báo', '通知单'),
                      _Phase.analyzing => bi('Đang phân tích...', '分析中…'),
                      _Phase.result => bi('Dịch xong', '翻译完成'),
                    },
                    ko: switch (_phase) {
                      _Phase.idle => '알림장',
                      _Phase.analyzing => '알림장 분석 중...',
                      _Phase.result => '번역 완료',
                    },
                    nativeStyle: GaonType.h3,
                    koStyle: GaonType.micro,
                  ),
                ),
                // 분석 중 = 취소 버튼(확인 팝업 후 이탈, QA D-2) ·
                // 결과 화면 = 홈 복귀 버튼(새 알림장 분석).
                if (_phase != _Phase.idle) ...[
                  Material(
                    color: GaonColors.primaryLight,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _phase == _Phase.analyzing
                          ? _confirmAbortAnalysis
                          : _resetToHome,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          _phase == _Phase.analyzing
                              ? Icons.close_rounded
                              : Icons.home_rounded,
                          size: 16,
                          color: GaonColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: GaonSpace.xs),
                ],
                if (_selectedChild != null)
                  Material(
                    color: GaonColors.textPrimary,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                    child: InkWell(
                      onTap: _pickChild,
                      borderRadius: BorderRadius.circular(GaonRadius.pill),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _childLabel(_selectedChild!),
                              style: GaonType.label.copyWith(
                                color: GaonColors.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: GaonColors.onPrimary,
                            ),
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
              _Phase.idle => _EmptyState(
                onUpload: _pickAndUpload,
                upcoming: _upcoming,
              ),
              _Phase.analyzing => _LoadingState(status: _status),
              _Phase.result => _ResultState(
                analysis: _analysis!,
                onGoHome: _resetToHome,
              ),
            },
          ),
        ],
      ),
    );
  }
}

// ── S4: 빈 상태 (홈 역할 — 업로드 + 다가오는 일정 요약) ─────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onUpload, required this.upcoming});

  final VoidCallback onUpload;
  final Future<List<CalendarEvent>> upcoming;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(GaonSpace.xl),
      children: [
        const SizedBox(height: GaonSpace.lg),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: GaonColors.primary,
              boxShadow: GaonShadow.dark,
            ),
            child: const Icon(
              Icons.photo_camera_rounded,
              size: 38,
              color: GaonColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: GaonSpace.md),
        Text(
          bi('Gửi ảnh thông báo từ trường', '请上传学校发的通知单'),
          textAlign: TextAlign.center,
          style: GaonType.h2.copyWith(color: GaonColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          '알림장을 올려주세요',
          textAlign: TextAlign.center,
          style: GaonType.body.copyWith(color: GaonColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          biLine(
            '사진 촬영 또는 갤러리에서 선택',
            'Chụp ảnh hoặc chọn từ thư viện',
            '拍照或从相册选择',
          ),
          textAlign: TextAlign.center,
          style: GaonType.caption.copyWith(color: GaonColors.textSecondary),
        ),
        const SizedBox(height: GaonSpace.md),
        GaonButton(
          label: bi('Tải ảnh lên', '上传照片'),
          subLabel: '사진 올리기',
          icon: const Icon(
            Icons.upload_rounded,
            size: 16,
            color: GaonColors.onPrimary,
          ),
          onTap: onUpload,
        ),
        const SizedBox(height: GaonSpace.lg),
        // 다가오는 일정 — 저장된 캘린더 요약(홈에서 바로 확인, 실패 시 숨김).
        // GET /calendar/events는 과거 포함 전체를 주므로(캘린더 탭 누적 조회용)
        // 홈에서는 오늘 이후만 골라 보여준다.
        FutureBuilder<List<CalendarEvent>>(
          future: upcoming,
          builder: (context, snap) {
            final now = repository.now();
            final today = DateTime(now.year, now.month, now.day);
            final events =
                (([...(snap.data ?? const <CalendarEvent>[])]
                          ..sort((a, b) => a.date.compareTo(b.date)))
                        .where((e) => !e.date.isBefore(today))
                        .take(3))
                    .toList();
            if (events.isEmpty) return const SizedBox.shrink();
            return SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: BiText(
                          ko: '다가오는 일정',
                          native: bi('Lịch sắp tới', '即将到来的日程'),
                          nativeStyle: GaonType.h3,
                          koStyle: GaonType.micro,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => goToCalendar(),
                        child: Text(
                          '${biLine('전체 보기', 'Xem tất cả', '查看全部')} →',
                          style: GaonType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: GaonColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GaonSpace.sm),
                  for (final (i, e) in events.indexed) ...[
                    if (i > 0) const GaonDivider(),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: e.type == CalendarEventType.deadline
                                ? GaonColors.warningLight
                                : GaonColors.primaryLight,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${e.date.month}/${e.date.day}',
                            style: GaonType.nano.copyWith(
                              fontWeight: FontWeight.w700,
                              color: e.type == CalendarEventType.deadline
                                  ? GaonColors.warning
                                  : GaonColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: GaonSpace.sm),
                        Expanded(
                          child: Text(
                            e.title,
                            style: GaonType.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: GaonColors.textPrimary,
                            ),
                          ),
                        ),
                        if (e.type == CalendarEventType.deadline)
                          GaonBadge(
                            label: biLine('마감', 'Hạn chót', '截止'),
                            color: GaonColors.warning,
                            bg: GaonColors.warningLight,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── S5: 분석 중 (F-DOC-1·4 — status 폴링) ─────────────────────────
class _LoadingState extends StatefulWidget {
  const _LoadingState({required this.status});

  final DocStatus status;

  @override
  State<_LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<_LoadingState>
    with TickerProviderStateMixin {
  List<({String ko, String native})> get _steps => [
    (ko: '글자 읽기', native: bi('Đọc chữ', '识别文字')),
    (ko: '정보 정리', native: bi('Sắp xếp', '整理信息')),
    (ko: '번역 중', native: bi('Đang dịch...', '翻译中…')),
    (ko: '할 일 추출', native: bi('Tạo việc', '提取待办')),
  ];

  int get _activeStep => switch (widget.status) {
    DocStatus.uploaded => 0,
    DocStatus.parsing => 1,
    DocStatus.translating => 2,
    DocStatus.action => 3,
    DocStatus.done => 4,
    DocStatus.failed => 0,
  };

  /// 상태별 진행 구간 — 실서버는 한 status에 수십 초 머무르므로
  /// 고정 퍼센트 대신 구간 상한을 향해 계속 차오르게 한다.
  (double, double) _bandFor(DocStatus s) => switch (s) {
    DocStatus.uploaded => (0.02, 0.30),
    DocStatus.parsing => (0.30, 0.62),
    DocStatus.translating => (0.62, 0.86),
    DocStatus.action => (0.86, 0.97),
    DocStatus.done => (0.97, 1.0),
    DocStatus.failed => (0.0, 0.0),
  };

  // 크리프: 구간 상한을 향해 서서히(처음엔 빠르게) 차오름 · 펄스: 로고 숨쉬기
  late final AnimationController _creep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..forward();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  double _from = 0.02;

  double get _value {
    final t = Curves.easeOutQuad.transform(_creep.value);
    return _from + (_bandFor(widget.status).$2 - _from) * t;
  }

  @override
  void didUpdateWidget(covariant _LoadingState old) {
    super.didUpdateWidget(old);
    if (old.status == widget.status) return;
    // 현재 표시값(이전 구간 기준)에서 끊김 없이 이어 차오르게
    final t = Curves.easeOutQuad.transform(_creep.value);
    _from = _from + (_bandFor(old.status).$2 - _from) * t;
    _creep
      ..duration = widget.status == DocStatus.done
          ? const Duration(milliseconds: 500)
          : const Duration(seconds: 40)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _creep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GaonSpace.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 발자국 로고 — 퍼센트가 멈추지 않고 계속 차오른다
          AnimatedBuilder(
            animation: Listenable.merge([_creep, _pulse]),
            builder: (context, _) => Column(
              children: [
                Transform.scale(
                  scale: 0.98 + 0.04 * _pulse.value,
                  child: CustomPaint(
                    size: const Size(110, 130),
                    painter: _PawFillPainter(progress: _value),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(_value * 100).round()}%',
                  style: GaonType.h3.copyWith(
                    fontWeight: FontWeight.w700,
                    color: GaonColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: GaonSpace.lg),

          // 단계 카드
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: GaonSpace.xs,
              horizontal: GaonSpace.md,
            ),
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
                              bottom: BorderSide(color: GaonColors.border),
                            )
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
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: GaonColors.onPrimary,
                                )
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
                              Text(
                                s.native,
                                style: GaonType.body.copyWith(
                                  fontWeight: i < _activeStep
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: i < _activeStep
                                      ? GaonColors.textPrimary
                                      : GaonColors.textSecondary,
                                ),
                              ),
                              Text(
                                s.ko,
                                style: GaonType.micro.copyWith(
                                  color: GaonColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (i == _activeStep)
                          GaonBadge(
                            label: biLine('진행중', 'Đang chạy', '进行中'),
                            color: GaonColors.textPrimary,
                            bg: GaonColors.primary,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: GaonSpace.md),
          Text(
            bi('Sắp xong rồi, chờ chút nhé ☺', '快好了，请稍等 ☺'),
            style: GaonType.label.copyWith(color: GaonColors.textSecondary),
          ),
          Text(
            '거의 다 됐어요, 잠시만요',
            style: GaonType.micro.copyWith(color: GaonColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 가온 발자국(꽃) 로고 — 아래에서 위로 차오르는 진행 그래픽.
class _PawFillPainter extends CustomPainter {
  const _PawFillPainter({required this.progress});

  final double progress;

  void _drawPaw(
    Canvas canvas,
    Size size, {
    required Color toe,
    required Color pad,
  }) {
    final w = size.width / 100;
    final h = size.height / 118;
    final toePaint = Paint()..color = toe;
    final padPaint = Paint()..color = pad;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(35 * w, 30 * h),
        width: 30 * w,
        height: 40 * h,
      ),
      toePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(65 * w, 30 * h),
        width: 30 * w,
        height: 40 * h,
      ),
      toePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(30 * w, 78 * h),
        width: 46 * w,
        height: 60 * h,
      ),
      padPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(70 * w, 78 * h),
        width: 46 * w,
        height: 60 * h,
      ),
      padPaint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 미채움(연한 톤)
    _drawPaw(
      canvas,
      size,
      toe: GaonColors.successLight,
      pad: GaonColors.primaryLight,
    );
    // 채움(진한 톤) — 아래에서 progress만큼만
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        0,
        size.height * (1 - progress),
        size.width,
        size.height * progress,
      ),
    );
    _drawPaw(
      canvas,
      size,
      toe: GaonColors.primary,
      pad: GaonColors.textPrimary,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PawFillPainter old) => old.progress != progress;
}

// ── S6: 번역 결과 ─────────────────────────────────────────────────
class _ResultState extends StatelessWidget {
  const _ResultState({required this.analysis, this.onGoHome});

  final DocumentAnalysis analysis;
  final VoidCallback? onGoHome;

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
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => _showTermSheet(context, term),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 5),
              decoration: BoxDecoration(
                color: GaonColors.textPrimary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                term.termKo,
                style: GaonType.label.copyWith(color: GaonColors.onPrimary),
              ),
            ),
          ),
        ),
      );
      cursor = nextIndex + term.termKo.length;
    }
    return spans;
  }

  // ── S7: 단어 해설 바텀시트 (Term = F-DOC-5) ──
  void _showTermSheet(BuildContext context, Term term) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: GaonColors.barrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GaonRadius.xxl),
        ),
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
                    Text(
                      term.termKo,
                      style: GaonType.h1.copyWith(
                        fontWeight: FontWeight.w800,
                        color: GaonColors.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      term.literalNative,
                      style: GaonType.caption.copyWith(
                        color: GaonColors.primary,
                      ),
                    ),
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
                    Text(
                      biLine('설명', 'Giải thích', '解释'),
                      style: GaonType.micro.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      term.explanationNative,
                      style: GaonType.body.copyWith(
                        color: GaonColors.textPrimary,
                        height: 1.65,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GaonSpace.md),
              GaonButton(
                label: biLine('확인', 'Đóng', '关闭'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 저장 결과 안내 — 저장은 이미 완료된 상태(QA D-3a: 닫아도 저장 유지).
  /// "캘린더 보기"를 누르면 저장된 일정의 월로 캘린더 이동.
  void _showSavedConfirm(BuildContext context, List<CalendarEvent> saved) {
    showDialog<void>(
      context: context,
      barrierColor: GaonColors.barrier,
      builder: (dialogContext) => Dialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GaonRadius.xxl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 28)),
              const SizedBox(height: GaonSpace.xs),
              Text(
                bi('Đã thêm vào lịch', '已添加到日历'),
                style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                biLine(
                  '캘린더에 추가되었습니다 — 일정 ${saved.length}개 저장',
                  'Đã lưu ${saved.length} lịch',
                  '已保存 ${saved.length} 个日程',
                ),
                style: GaonType.caption.copyWith(
                  color: GaonColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // 저장은 이미 완료 — 이 창은 안내용일 뿐임을 명시(QA D-3a)
                biLines(
                  '이 창을 닫아도 저장은 유지돼요',
                  'Đã lưu xong — đóng cửa sổ này cũng không mất',
                  '已保存完成——关闭此窗口也不会丢失',
                ),
                textAlign: TextAlign.center,
                style: GaonType.caption.copyWith(color: GaonColors.textSecondary),
              ),
              const SizedBox(height: GaonSpace.md),
              Row(
                children: [
                  Expanded(
                    child: GaonButton(
                      variant: GaonButtonVariant.ghost,
                      label: bi('Đóng', '关闭'),
                      subLabel: '닫기',
                      onTap: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: GaonSpace.xs),
                  Expanded(
                    flex: 2,
                    child: GaonButton(
                      label: biLine('캘린더 보기', 'Xem lịch', '查看日历'),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        // 저장된 첫 일정의 월·일로 캘린더 포커스 이동
                        goToCalendar(saved.firstOrNull?.date);
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

  // ── S8: 캘린더 저장 다이얼로그 — 체크박스로 골라 저장(QA D-3b) ──
  // '저장하기'를 누른 시점에 API 호출이 완료된다(QA D-3a) — 후속 창은 안내용.
  void _showCalSaveDialog(BuildContext context) {
    final rootContext = context; // 다이얼로그 pop 이후 결과 안내 다이얼로그용
    // 자녀 미지정(child_id=null) 일정도 포함 — AI가 child_id를 안 채우면
    // 목록이 통째로 비어 보이던 필터 완화(QA D-3 조사 중 발견).
    final events = analysis.actionCard.calendarEvents
        .where(
          (e) => e.childId == null || e.childId == analysis.document.childId,
        )
        .toList();
    final selected = {...events}; // 기본 전체 선택
    var saving = false;
    showDialog<void>(
      context: context,
      barrierColor: GaonColors.barrier,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: GaonColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GaonRadius.xxl),
          ),
          child: Padding(
            padding: const EdgeInsets.all(GaonSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: GaonColors.textPrimary,
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    size: 26,
                    color: GaonColors.onPrimary,
                  ),
                ),
                const SizedBox(height: GaonSpace.sm),
                Text(
                  bi('Lưu vào lịch không?', '要保存到日历吗？'),
                  style: GaonType.h2.copyWith(color: GaonColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '캘린더에 저장할까요?',
                  style: GaonType.label.copyWith(
                    color: GaonColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  biLine('저장할 일정을 선택하세요', 'Chọn lịch muốn lưu', '请选择要保存的日程'),
                  style: GaonType.micro.copyWith(
                    color: GaonColors.textSecondary,
                  ),
                ),
                const SizedBox(height: GaonSpace.md),
                // 일정이 많아도 다이얼로그가 넘치지 않게 목록만 스크롤
                // (적대적 리뷰 B-1 — 하단 버튼 Row는 고정)
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in events) ...[
                          _EventRow(
                            event: e,
                            selected: selected.contains(e),
                            onTap: () => setDialogState(() {
                              selected.contains(e)
                                  ? selected.remove(e)
                                  : selected.add(e);
                            }),
                          ),
                          const SizedBox(height: GaonSpace.xs),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GaonSpace.xs),
                Row(
                  children: [
                    Expanded(
                      child: GaonButton(
                        variant: GaonButtonVariant.ghost,
                        label: bi('Bỏ qua', '跳过'),
                        subLabel: '건너뛰기',
                        onTap: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    const SizedBox(width: GaonSpace.xs),
                    Expanded(
                      flex: 2,
                      child: GaonButton(
                        label: saving
                            ? biLine('저장 중...', 'Đang lưu...', '保存中…')
                            : '✓ ${biLine('저장하기 (${selected.length})', 'Lưu', '保存')}',
                        // 선택 0개·저장 중엔 비활성
                        onTap: selected.isEmpty || saving
                            ? null
                            : () async {
                                setDialogState(() => saving = true);
                                // F-DOC-7: 버튼 탭 즉시 확정 저장(QA D-3a) —
                                // 선택한 (title, date)만 저장(QA D-3b)
                                final List<CalendarEvent> saved;
                                try {
                                  saved = await repository.saveCalendarEvents(
                                    documentId: analysis.document.documentId,
                                    selected: selected.toList(),
                                  );
                                } catch (_) {
                                  if (dialogContext.mounted) {
                                    setDialogState(() => saving = false);
                                  }
                                  if (rootContext.mounted) {
                                    ScaffoldMessenger.of(
                                      rootContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          biLines(
                                            '캘린더 저장에 실패했어요 — 네트워크를 확인해 주세요',
                                            'Lưu lịch thất bại — hãy kiểm tra mạng',
                                            '保存日历失败——请检查网络',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                // 로컬 리마인드 예약 제거(결정 #11 — 선제 알림 비활성)
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                                // 결과 안내(닫아도 저장 유지) + 캘린더 이동 선택지
                                if (!rootContext.mounted) return;
                                _showSavedConfirm(rootContext, saved);
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
              Text(
                biLine('원문 한국어', 'Bản gốc tiếng Hàn', '韩语原文'),
                style: GaonType.micro.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GaonColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: _highlightedRawText(context)),
                style: GaonType.body.copyWith(
                  color: GaonColors.textPrimary,
                  height: 1.7,
                ),
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
              Text(
                biLine('번역', 'Bản dịch (Tiếng Việt)', '译文（中文）'),
                style: GaonType.micro.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GaonColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                analysis.translated.summaryNative,
                style: GaonType.body.copyWith(
                  color: GaonColors.textPrimary,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GaonSpace.sm),

        // 단어 해설 칩
        Text(
          biLine('단어 해설', 'Giải thích từ', '词语解释'),
          style: GaonType.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: GaonColors.textSecondary,
          ),
        ),
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
                      vertical: 7,
                      horizontal: 14,
                    ),
                    child: Text(
                      // 단어 뒤 ' ?' 리터럴 제거(요청) — 칩은 탭으로 해설을 연다.
                      term.termKo,
                      style: GaonType.label.copyWith(
                        color: GaonColors.onPrimary,
                      ),
                    ),
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
                label: '📅 ${bi('Lưu lịch', '存日历')}',
                subLabel: '캘린더 저장',
                onTap: () => _showCalSaveDialog(context),
              ),
            ),
            const SizedBox(width: GaonSpace.xs),
            Expanded(
              child: GaonButton(
                variant: GaonButtonVariant.secondary,
                label: '📋 ${bi('Việc cần làm', '待办')}',
                subLabel: '할 일 보기',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ActionCardScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: GaonSpace.xs),
        // 홈 복귀 — 새 알림장을 분석하거나 잘못 진입했을 때
        GaonButton(
          variant: GaonButtonVariant.ghost,
          label: '🏠 ${biLine('처음으로', 'Về đầu', '回到首页')}',
          onTap: onGoHome,
        ),
      ],
    );
  }
}

/// 저장 다이얼로그의 일정 행 — 날짜·제목·타입(마감/행사)을 함께 표시(QA D-5).
/// [selected]가 null이면 표시 전용, 아니면 체크박스 토글(QA D-3b).
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, this.selected, this.onTap});

  final CalendarEvent event;
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final urgent = event.type == CalendarEventType.deadline;
    return Material(
      color: urgent ? GaonColors.warningLight : GaonColors.bg,
      borderRadius: BorderRadius.circular(GaonRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: GaonSpace.xs,
            horizontal: GaonSpace.sm,
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
                child: Text(
                  '${event.date.month}/${event.date.day}',
                  style: GaonType.micro.copyWith(
                    fontWeight: FontWeight.w700,
                    color: GaonColors.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: GaonSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: GaonType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.textPrimary,
                      ),
                    ),
                    // 마감/행사 구분 병기 — 날짜만으론 출처를 알 수 없다(QA D-5)
                    Text(
                      urgent
                          ? biLine('마감', 'Hạn chót', '截止')
                          : biLine('행사', 'Sự kiện', '活动'),
                      style: GaonType.micro.copyWith(
                        color: urgent
                            ? GaonColors.warning
                            : GaonColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected == null
                    ? Icons.check_rounded
                    : (selected!
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded),
                size: selected == null ? 16 : 20,
                color: urgent ? GaonColors.warning : GaonColors.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
