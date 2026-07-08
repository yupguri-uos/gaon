import uuid
from unittest.mock import MagicMock  # 가짜 객체를 만드는 것
from app.services import activity as activity_svc


def test_log_activity_inserts_row(monkeypatch):
    # 로그가 정상적으로 저장되는지 테스트
    fake = MagicMock()
    monkeypatch.setattr(
        activity_svc, "SessionLocal", lambda: fake
    )  # 원래 구동되야 하는 디비랑 세션 연결안되게 막는 것
    uid = uuid.uuid4()  # 가짜 user_id를 하나 만든다

    activity_svc.log_activity(uid, "document_processed", related_id=None)  # 테스트 함수 실행

    # add()가 정확히 한번 호출되었는지 검사
    fake.add.assert_called_once()
    row = fake.add.call_args.args[0]  # db.add(row)로 받은 객체를 꺼내옴

    # 맞게 들어갔는지 확인
    assert row.user_id == uid
    assert row.activity_kind == "document_processed"
    assert row.occurred_at.tzinfo is not None  # tz-aware 기본값

    # 커밋이 한번 실행됬는지 확인
    fake.commit.assert_called_once()


def test_log_activity_swallows_failure(monkeypatch):
    # db 저장 실패해도 함수가 죽지 않는지 테스트
    fake = MagicMock()

    # 커밋 실패 유도
    fake.commit.side_effect = Exception("boom")

    # db 세션 연결 막기
    monkeypatch.setattr(activity_svc, "SessionLocal", lambda: fake)

    # 이걸 실행하면 commit에서 exception이 발생
    activity_svc.log_activity(uuid.uuid4(), "item_missed")  # 예외가 새면 안 됨

    fake.rollback.assert_called_once()
    fake.close.assert_called_once()
