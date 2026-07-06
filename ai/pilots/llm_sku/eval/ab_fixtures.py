"""
경어체 블라인드 A/B 고정 입력 5건 (§8). PII 없음 — ChildInfo(grade=...)만.

사과·민감 상담·기한 양해 등 경어체 난도가 다른 상황을 의도적으로 섞었다.
TeacherCommunicationAgent(QUALITY)에 그대로 주입한다(프롬프트 변형 금지).
"""

from __future__ import annotations

from gaon_shared import ChildInfo, TeacherCommInput

AB_FIXTURES: list[TeacherCommInput] = [
    # 1) 결석 통지(vi) — 기본 격식
    TeacherCommInput(
        situation="absence",
        native_language="vi",
        input_native="Ngày mai con tôi bị sốt nên có lẽ không thể đến trường được ạ.",
        child_info=ChildInfo(grade="elem_1"),
    ),
    # 2) 병결·진단서 기한 양해(zh)
    TeacherCommInput(
        situation="sick_note",
        native_language="zh",
        input_native="医生说需要休息三天，诊断书明天提交可以吗？",
        child_info=ChildInfo(grade="elem_2"),
    ),
    # 3) 민감 상담 요청(vi) — 아이가 반에서 놀림을 당해 상담 요청
    TeacherCommInput(
        situation="consultation",
        native_language="vi",
        input_native="Tôi muốn xin gặp cô giáo để trao đổi về việc con tôi bị bạn trêu ở lớp.",
        child_info=ChildInfo(grade="elem_3"),
    ),
    # 4) 사과·배상 의사(zh) — 경어체 난도 높음
    TeacherCommInput(
        situation="custom",
        native_language="zh",
        input_native="孩子把同学的水壶弄坏了，我想道歉并赔偿，该怎么说？",
        child_info=ChildInfo(grade="elem_1"),
    ),
    # 5) 동의서 내용을 몰라 늦게 제출(vi) — 기한 양해
    TeacherCommInput(
        situation="custom",
        native_language="vi",
        input_native=(
            "Con tôi chưa nộp phiếu đồng ý vì tôi không hiểu nội dung, "
            "tôi có thể nộp muộn không ạ?"
        ),
        child_info=ChildInfo(grade="elem_2"),
    ),
]
