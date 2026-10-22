# AI 연구소 탈출 (수퍼베이스 버전)

중학교 「인공지능의 학습」 단원 방탈출 웹 게임입니다. 예전 구글 앱스스크립트 + 구글시트 버전을 **수퍼베이스(Supabase)** 로 옮겼고, **깃허브 페이지(GitHub Pages)** 에서 바로 열 수 있어요.

## 새로 생긴 기능
- **실시간 접속자 현황** — 결과판(`?view=board`)에 지금 접속한 학생 카드가 보여요: 이름 · 학번 · 지금 있는 방 · 모은 코드 조각 · 경과 시간. 학생 화면 상단에는 "N명 도전 중"이 떠요.
- **탈출 팝업** — 누군가 탈출하면 결과판과 같은 학교 학생 화면에 바로 팝업이 떠요. 결과판 순위도 새로 고침 없이 바로 바뀌어요.

## 주소 (깃허브 페이지 기준)
| 용도 | 주소 |
|---|---|
| 학생 게임 | `…/index.html` |
| 학교 고정 링크 | `…/?s=장성중학교` |
| 반 고정 링크 | `…/?c=3` (함께 쓰기: `?s=장성중학교&c=3`) |
| 실시간 결과판 (전자칠판) | `…/?view=board` |
| 관리자 | `…/?view=admin` (처음 비밀번호 `1234`, 들어가서 꼭 바꾸세요) |

예전 주소 형식(`#board`, `#admin`, `#c3`, `#s=학교`)도 그대로 돼요.

## 수퍼베이스 테이블
| 예전 시트 탭 | 테이블 | 비고 |
|---|---|---|
| 학교목록 | `escape_schools` | `sort_order` 순서로 표시 |
| 탈출기록 | `escape_records` | 18개 열 그대로. 실시간 알림 켜짐 |
| 설정 | `escape_settings` | 항목/값 |
| 학생명단 | `escape_students` | 지금 게임에서는 쓰지 않음 |
| (스크립트 속성 ADMIN_PW) | `escape_admin` | 비밀번호 암호화 저장, 학생은 읽을 수 없음 |

서버 함수: `escape_submit`(기록 저장 · 회차 계산), `escape_admin_login`, `escape_save_config`, `escape_delete_result`, `escape_clear_results`.
전체 SQL은 `supabase/setup_functions.sql` 에 있어요.

## 깃허브 페이지로 올리기
1. 이 폴더의 `index.html` 을 저장소에 올려요.
2. 저장소 **Settings → Pages → Branch: main / (root)** 를 고르고 Save.
3. 1~2분 뒤 `https://<아이디>.github.io/<저장소>/` 로 열려요.

`index.html` 안의 `SUPABASE_KEY` 는 공개용(anon) 키라 깃허브에 올려도 괜찮아요. 관리자 기능은 서버 함수가 비밀번호를 확인합니다.
