# 경어체 블라인드 A/B (ab_pairs.md)

평가자 안내: 벤더명은 제거됐고 문항별로 A/B가 무작위 배정됐다.
배정표는 ab_key.json에 있으니 평가 완료 전에는 열지 말 것.
vi 문항의 admin_guide_native 원문은 육안 점검 대상(조사 페이지 §11, 2026-07-06 사전등록).

## 문항 1 — situation=absence, lang=vi

[입력] Ngày mai con tôi bị sốt nên có lẽ không thể đến trường được ạ.

### A

- output_ko:

```
선생님, 안녕하세요. 1학년 저희 아이가 열이 나서 내일은 학교에 가기 어려울 것 같아 연락드렸습니다. 갑작스럽게 결석하게 되어 죄송합니다. 병원에 다녀오고 아이가 회복하는 대로 등교시키겠습니다. 감사합니다.
```

- admin_guide_native:

```
Hướng dẫn thủ tục khi học sinh nghỉ ốm tại Hàn Quốc: 1. Khi con đi học lại, phụ huynh cần điền và nộp 'Đơn xin phép nghỉ học' (결석계) cho giáo viên chủ nhiệm. 2. Phụ huynh nhớ giữ lại đơn thuốc, biên lai nhà thuốc hoặc giấy xác nhận của bác sĩ (처방전/진료확인서) để nộp kèm làm minh chứng. 3. Giấy tờ này thường cần nộp trong vòng 3 đến 5 ngày sau khi con đi học trở lại để được nhà trường công nhận là nghỉ ốm hợp lệ.
```

### B

- output_ko:

```
안녕하세요, 선생님. 저는 1학년 학부모입니다.

내일 아이가 열이 나서 등교가 어려울 것 같아 미리 연락드립니다. 갑작스럽게 결석하게 되어 죄송합니다.

건강이 회복되는 대로 등교할 수 있도록 하겠습니다. 감사합니다.
```

- admin_guide_native:

```
📋 Hướng dẫn thủ tục hành chính tại trường tiểu học Hàn Quốc khi con vắng học

1. Thông báo vắng học
- Hãy liên hệ với giáo viên chủ nhiệm trước hoặc vào buổi sáng ngày con vắng học (qua tin nhắn, điện thoại hoặc ứng dụng liên lạc của trường).
- Nêu rõ lý do vắng học (ví dụ: sốt, bệnh) và dự kiến thời gian nghỉ.

2. Đơn xin vắng học (결석계)
- Khi con quay lại trường, phụ huynh cần nộp đơn xin vắng học (결석계) cho giáo viên chủ nhiệm.
- Mẫu đơn thường có thể xin tại văn phòng nhà trường hoặc do giáo viên cung cấp.

3. Trường hợp vắng vì bệnh (병결)
- Nếu con nghỉ từ 3 ngày trở lên hoặc theo yêu cầu của nhà trường, bạn có thể cần nộp kèm giấy chứng nhận của bác sĩ (진단서) hoặc hóa đơn khám bệnh (영수증).
- Hãy giữ lại các giấy tờ y tế phòng khi nhà trường yêu cầu.

4. Lưu ý
- Mỗi trường có thể có quy định riêng, vì vậy nếu chưa rõ, hãy hỏi trực tiếp giáo viên chủ nhiệm hoặc văn phòng nhà trường.
- Việc thông báo sớm giúp nhà trường sắp xếp và hỗ trợ con bạn tốt hơn khi quay lại học.
```

## 문항 2 — situation=sick_note, lang=zh

[입력] 医生说需要休息三天，诊断书明天提交可以吗？

### A

- output_ko:

```
안녕하세요 선생님, 2학년 아이 학부모입니다. 병원 진료 결과, 의사 선생님께서 아이가 3일 정도 휴식을 취해야 한다고 하십니다. 진단서는 내일 학교에 제출해도 괜찮을까요? 감사합니다.
```

- admin_guide_native:

```
在韩国小学，因病请假（病假）需要向学校提交证明材料（如诊断书、处方笺或就诊确认书）和缺勤申请书（결석계），这样才能被认定为“疾病缺勤”而不影响出勤率。通常证明材料在孩子返校后的5天内提交即可，所以明天提交是完全可以的。请务必妥善保管好医院开具的证明或药店收据。
```

### B

- output_ko:

```
안녕하세요, 선생님. 저는 2학년 학부모입니다.

아이가 몸이 좋지 않아 병원을 다녀왔는데, 의사 선생님께서 3일간 안정이 필요하다고 하셨습니다.

진단서는 내일 제출해도 괜찮을지 여쭤보고 싶습니다. 혹시 제출 방법이나 절차에 대해 안내해 주실 수 있으시면 감사하겠습니다.

바쁘신 중에 번거롭게 해 드려 죄송합니다. 감사합니다.
```

- admin_guide_native:

```
【韩国小学病假相关行政手续说明】

1. 诊断书提交时间：一般情况下，诊断书需在病假结束后或返校时尽快提交。如需次日提交，建议提前通过短信或联络本告知班主任，获得确认后再提交。

2. 提交方式：诊断书通常以纸质原件或复印件的形式，通过联络本（알림장）或直接交给班主任提交。部分学校也接受拍照后通过学校APP（예: 하이클래스、아이엠스쿨等）发送，请提前与老师确认。

3. 病假申请（결석계）：病假期间一般需填写
```

## 문항 3 — situation=consultation, lang=vi

[입력] Tôi muốn xin gặp cô giáo để trao đổi về việc con tôi bị bạn trêu ở lớp.

### A

- output_ko:

```
안녕하세요 선생님, 3학년 [아이 이름] 학부모입니다. 다름이 아니오라, 아이가 교실에서 친구들에게 놀림을 받는 일이 있는 것 같아 선생님과 상담을 하고 싶어 연락드렸습니다. 바쁘시겠지만, 통화나 방문 상담이 가능하신 시간을 알려주시면 그 시간에 맞추겠습니다. 항상 아이들을 위해 애써주셔서 감사합니다.
```

- admin_guide_native:

```
Hướng dẫn về việc xin tư vấn tại trường học Hàn Quốc: 1. Đặt lịch hẹn: Phụ huynh nên nhắn tin trước để đặt lịch hẹn tư vấn. Giáo viên thường không thể nghe điện thoại trong giờ học, vì vậy hãy để lại tin nhắn chờ giáo viên phản hồi. 2. Vấn đề bạn bè trêu chọc: Việc trao đổi trước với giáo viên chủ nhiệm là bước đầu tiên rất quan trọng. Giáo viên sẽ tìm hiểu tình hình thực tế trên lớp. Nếu vấn đề nghiêm trọng, nhà trường sẽ có quy trình xử lý bạo lực học đường chính thức, nhưng trước mắt hãy thảo luận cởi mở với giáo viên để tìm hướng giải quyết.
```

### B

- output_ko:

```
안녕하세요, 선생님. 저는 3학년 학부모입니다.

다름이 아니라, 최근 저희 아이가 학급에서 친구들에게 놀림을 받고 있는 것 같아 걱정이 되어 연락드립니다. 이 부분에 대해 선생님과 직접 말씀을 나누고 싶어 상담을 요청드리고자 합니다.

선생님의 일정에 맞추어 상담 시간을 잡아 주시면 감사하겠습니다. 편하신 날짜와 시간을 알려 주시면 최대한 맞추도록 하겠습니다.

바쁘신 중에 번거롭게 해 드려 죄송하며, 아이를 위해 도움 주시면 정말 감사하겠습니다. 잘 부탁드립니다.
```

- admin_guide_native:

```
Hướng dẫn thủ tục hành chính tại trường học Hàn Quốc (dành cho phụ huynh):

📌 Cách xin gặp giáo viên chủ nhiệm để tư vấn:

1. **Gửi tin nhắn hoặc liên hệ trước**: Tại Hàn Quốc, phụ huynh thường liên hệ với giáo viên qua ứng dụng nhắn tin của trường (ví dụ: 학교알리미, Class123, Naver Band, hoặc tin nhắn điện thoại) để xin lịch hẹn trước. Không nên đến trường đột xuất mà không báo trước.

2. **Thời gian tư vấn**: Giáo viên thường có thể gặp phụ huynh trước hoặc sau giờ học, hoặc vào giờ nghỉ trưa. Hãy hỏi giáo viên về thời gian thuận tiện cho cả hai bên.

3. **Nội dung cần chuẩn bị**: Trước khi gặp, hãy ghi lại cụ thể những sự việc mà con bạn kể lại (thời gian, địa điểm, tên bạn nếu biết, nội dung bị trêu chọc) để giáo viên có thể nắm rõ tình huống.

4. **Vấn đề bị bạn trêu chọc (따돌림/놀림)**: Đây là vấn đề nghiêm túc tại trường học Hàn Quốc. Nếu sự việc nghiêm trọng hoặc kéo dài, nhà trường có thể kích hoạt quy trình xử lý bạo lực học đường (학교폭력 처리 절차). Phụ huynh có quyền yêu cầu nhà trường điều tra và xử lý chính thức.

5. **Thông dịch viên**: Nếu bạn gặp khó khăn về ngôn ngữ, bạn có thể liên hệ Trung tâm Gia đình Đa văn hóa (다문화가족지원센터) gần nhất để được hỗ trợ thông dịch miễn phí khi gặp giáo viên.

⚠️ Lưu ý: Hãy giữ bình tĩnh và trao đổi thân thiện với giáo viên. Mục tiêu là cùng nhau tìm giải pháp tốt nhất cho con bạn.
```

## 문항 4 — situation=custom, lang=zh

[입력] 孩子把同学的水壶弄坏了，我想道歉并赔偿，该怎么说？

### A

- output_ko:

```
선생님, 안녕하세요. 1학년 저희 아이가 친구의 물병을 망가뜨렸다는 이야기를 들었습니다. 피해를 입은 학생과 학부모님께 정말 죄송한 마음입니다. 제가 직접 사과드리고 물병을 변상해 드리고 싶은데, 혹시 상대방 학부모님께 제 연락처를 전달해 주시거나 연락할 방법을 여쭤봐 주실 수 있으실까요? 바쁘신 중에 번거로운 부탁을 드려 정말 죄송하고 감사합니다.
```

- admin_guide_native:

```
在韩国学校，由于《个人信息保护法》，老师通常不能直接将其他家长的联系方式告诉您。因此，处理此类事件的最佳方法是请老师代为转达您的歉意，并请老师将您的联系方式转交给对方家长。等对方家长联系您时，您可以直接向他们道歉并协商赔偿（如购买同款新水壶或转账赔偿）。一年级孩子之间经常发生小摩擦，诚恳的沟通通常能圆满解决问题。
```

### B

- output_ko:

```
안녕하세요, 선생님. 저는 1학년 학부모입니다.

다름이 아니라, 저희 아이가 같은 반 친구의 물통을 실수로 파손하게 되었다는 사실을 알게 되었습니다. 먼저 진심으로 사과의 말씀을 드리며, 해당 학생과 학부모님께도 깊이 사과드리고 싶습니다.

파손된 물통에 대해서는 변상할 의사가 있으며, 선생님께서 중간에서 도움을 주신다면 정말 감사하겠습니다. 상대 학부모님과 연락을 취할 수 있도록 안내해 주시거나, 적절한 방법을 알려 주시면 그에 따르겠습니다.

아이에게도 친구의 물건을 소중히 다루어야 한다는 점을 잘 타일렀습니다. 앞으로 이런 일이 없도록 가정에서도 더욱 지도하겠습니다.

바쁘신 중에 번거롭게 해 드려 죄송합니다. 감사합니다.
```

- admin_guide_native:

```
【关于孩子损坏同学物品的处理建议】

1. **告知班主任**：首先通过学校联络本（알림장）、短信或学校APP（예: 하이클래스、아이엠스쿨 등）联系班主任，说明情况并表达歉意，请老师协助协调。

2. **赔偿方式**：韩国学校通常不直接介入金钱赔偿，但老师可以帮助双方家长取得联系。赔偿一般由双方家长私下协商解决，可以购买同款或同等价值的物品进行赔偿，也可以直接支付相应金额。

3. **沟通礼仪**：与对方家长联系时，建议先以短信或电话表达诚意，再协商具体赔偿方式。态度诚恳、主动沟通，通常能得到对方理解。

4. **学校责任范围**：若事故发生在学校内，学校可能会有相关记录，但一般不强制介入赔偿流程。如双方协商困难，可请班主任或学교폭력 담당 교사（学校纠纷负责教师）协助调解。

5. **注意事项**：请保留与对方沟通的记录（短信截图等），以备日后参考。整个过程保持友好、冷静的态度，有助于顺利解决问题。
```

## 문항 5 — situation=custom, lang=vi

[입력] Con tôi chưa nộp phiếu đồng ý vì tôi không hiểu nội dung, tôi có thể nộp muộn không ạ?

### A

- output_ko:

```
안녕하세요, 선생님. 저는 2학년 학부모입니다.

다름이 아니라, 최근에 가정통신문 동의서를 아직 제출하지 못하였습니다. 내용을 충분히 이해하는 데 시간이 걸려 늦어지게 되었습니다. 혹시 늦게 제출하는 것이 가능한지 여쭤보고 싶습니다.

불편을 드려 죄송합니다. 확인해 주시면 감사하겠습니다.

감사합니다.
```

- admin_guide_native:

```
Xin chào quý phụ huynh! Dưới đây là một số thông tin hành chính tại trường tiểu học Hàn Quốc liên quan đến việc nộp phiếu đồng ý (동의서) mà quý phụ huynh cần biết:

1. **Phiếu đồng ý (동의서) là gì?**
   Đây là loại giấy tờ nhà trường gửi về gia đình để xin ý kiến hoặc sự đồng ý của phụ huynh về các hoạt động, chương trình của trường (ví dụ: hoạt động ngoại khóa, sử dụng hình ảnh, v.v.).

2. **Nếu chưa nộp đúng hạn:**
   - Quý phụ huynh nên liên hệ trực tiếp với giáo viên chủ nhiệm (담임 선생님) để hỏi xem có thể nộp muộn không.
   - Thông thường, giáo viên sẽ linh hoạt nếu phụ huynh chủ động thông báo sớm.

3. **Nếu không hiểu nội dung phiếu:**
   - Quý phụ huynh có thể nhờ nhà trường hỗ trợ phiên dịch. Nhiều trường tiểu học có dịch vụ hỗ trợ đa văn hóa (다문화 지원) hoặc có thể liên hệ Trung tâm Gia đình đa văn hóa (다문화가족지원센터) gần nhất để được hỗ trợ dịch tài liệu.
   - Ngoài ra, có thể sử dụng ứng dụng dịch thuật để hiểu sơ bộ nội dung trước khi ký.

4. **Lưu ý:**
   - Không nên ký vào phiếu khi chưa hiểu rõ nội dung. Hãy hỏi giáo viên hoặc nhờ hỗ trợ dịch thuật trước.
   - Việc chủ động liên lạc với giáo viên thể hiện sự quan tâm của phụ huynh và thường được nhà trường đánh giá cao.
```

### B

- output_ko:

```
안녕하세요 선생님, 2학년 아이 학부모입니다. 다름이 아니오라, 학교에서 보내주신 동의서 내용을 제가 아직 잘 이해하지 못해서 제출하지 못했습니다. 혹시 내용을 조금 더 확인한 후에 늦게 제출해도 괜찮을지 여쭤보고 싶습니다. 한국어가 서툴러 제출이 늦어진 점 너른 양해 부탁드립니다. 감사합니다.
```

- admin_guide_native:

```
Ở các trường học Hàn Quốc, nhà trường thường gửi các bản thông báo (가정통신문) hoặc phiếu đồng ý yêu cầu phụ huynh ký tên và nộp lại đúng hạn. Nếu không hiểu nội dung do rào cản ngôn ngữ, phụ huynh có thể sử dụng các ứng dụng dịch thuật qua hình ảnh (như Papago) hoặc xem trên ứng dụng thông báo của trường (như e알리미, 아이엠스쿨) để dễ dịch hơn. Mặc dù thời hạn nộp rất quan trọng, nhưng nếu gặp khó khăn, phụ huynh nên nhắn tin báo trước cho giáo viên để xin nộp muộn. Giáo viên Hàn Quốc rất thấu hiểu và sẽ sẵn sàng hỗ trợ hoặc gia hạn thêm thời gian cho gia đình đa văn hóa.
```

