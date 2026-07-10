import 'dart:typed_data';

/// 사용자가 고른 사진(F-DOC-1)을 업로드 전까지 메모리에 보관.
///
/// 화면(image_picker)과 저장소(ApiRepository) 사이에서 이미지 바이트를
/// `picked://<id>` 참조 문자열로 주고받는다 — GaonRepository 인터페이스
/// (imageRef: String)를 바꾸지 않으면서 웹(blob)·모바일(파일) 모두 동작.
abstract final class PickedImageStore {
  static final _images = <String, Uint8List>{};
  static int _seq = 0;

  /// 바이트를 등록하고 참조 문자열을 돌려준다.
  static String register(Uint8List bytes) {
    final ref = 'picked://${++_seq}';
    _images[ref] = bytes;
    return ref;
  }

  /// 업로드 시 1회 소비(메모리 해제). 없으면 null.
  static Uint8List? take(String ref) => _images.remove(ref);

  static bool isPickedRef(String ref) => ref.startsWith('picked://');
}
