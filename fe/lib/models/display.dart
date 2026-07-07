import 'schema.dart';

/// 값 타입의 화면 표기 — FE 전용(스키마 아님).
/// 확장값(country/language/grade)이 늘어나면 여기도 함께 늘린다.

extension OriginCountryDisplay on OriginCountry {
  String get label => switch (this) {
        OriginCountry.vn => 'Việt Nam 🇻🇳',
        OriginCountry.cn => 'Trung Quốc 🇨🇳',
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
        ChildGrade.elem1 => 'Lớp 1 / 초1',
        ChildGrade.elem2 => 'Lớp 2 / 초2',
        ChildGrade.elem3 => 'Lớp 3 / 초3',
      };
}

extension MessageSituationDisplay on MessageSituation {
  (String vi, String ko) get label => switch (this) {
        MessageSituation.absence => ('Nghỉ học', '결석'),
        MessageSituation.sickNote => ('Giấy khám bệnh', '진단서'),
        MessageSituation.consultation => ('Tư vấn', '상담'),
        MessageSituation.custom => ('Khác', '기타'),
      };
}
