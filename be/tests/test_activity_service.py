import uuid
from unittest.mock import MagicMock
from app.services import activity as activity_svc

def test_log_activity_inserts_row(monkeypatch):
    fake = MagicMock()
    monkeypatch.setattr(activity_svc, "SessionLocal", lambda: fake)
    uid = uuid.uuid4()
    
    activity_svc.log_activity(uid, "document_processed", related_id=None )
    
    fake.add.assert_called_once()
    row = fake.add.call_args.args[0] #add(row)로 넘어간 객체 
    
    assert row.user_id == uid
    assert row.activity_kind == "document_processed"
    assert row.occurred_at.tzinfo is not None
    #tz-aware 기본값
    fake.commit.assert_called_once()
    
def test_log_activity_swallows_failure(monkeypatch): 
    fake = MagicMock()
    fake.commit.side_effect = Exception("boom") #커밋 실패 유도
    monkeypatch.setattr(activity_svc, "SessionLocal", lambda: fake)
    
    activity_svc.log_activity(uuid.uuid4(),"item_missed") #예외가 새면 안 됨
    fake.rollback.assert_called_once()
    fake.close.assert_called_once()
