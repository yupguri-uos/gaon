import '../data/app_lang.dart';
import 'schema.dart';

/// 값 타입의 화면 표기 — FE 전용(스키마 아님).
/// 확장값(country/language/grade)이 늘어나면 여기도 함께 늘린다.

extension OriginCountryDisplay on OriginCountry {
  String get label => switch (this) {
        OriginCountry.vn => '${bi('Việt Nam', '越南')} 🇻🇳',
        OriginCountry.cn => '${bi('Trung Quốc', '中国')} 🇨🇳',
      };
}

extension NativeLanguageDisplay on NativeLanguage {
  String get label => switch (this) {
        NativeLanguage.vi => 'Tiếng Việt',
        NativeLanguage.zh => '中文',
      };
}

extension ChildGradeDisplay on ChildGrade {
  String get label => switch (this) {
        ChildGrade.elem1 => '${bi('Lớp 1', '一年级')} / 초1',
        ChildGrade.elem2 => '${bi('Lớp 2', '二年级')} / 초2',
        ChildGrade.elem3 => '${bi('Lớp 3', '三年级')} / 초3',
        ChildGrade.elem4 => '${bi('Lớp 4', '四年级')} / 초4',
        ChildGrade.elem5 => '${bi('Lớp 5', '五年级')} / 초5',
        ChildGrade.elem6 => '${bi('Lớp 6', '六年级')} / 초6',
      };
}

extension MessageSituationDisplay on MessageSituation {
  (String vi, String ko) get label => switch (this) {
        MessageSituation.absence => (bi('Nghỉ học', '请假'), '결석'),
        MessageSituation.sickNote => (bi('Giấy khám bệnh', '诊断书'), '진단서'),
        MessageSituation.consultation => (bi('Tư vấn', '咨询'), '상담'),
        MessageSituation.custom => (bi('Khác', '其他'), '기타'),
      };
}
