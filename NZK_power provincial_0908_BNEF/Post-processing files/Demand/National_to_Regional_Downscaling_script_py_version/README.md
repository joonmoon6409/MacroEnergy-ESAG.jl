# NZK MACRO — national → provincial demand downscaling

## 폴더 구조

```
.
├── main.py                  실행 진입점 (설정 + CLI)
├── downscale.py             변환 로직 (라이브러리, 실행 불가)
├── Input_data/              모든 입력 파일
│   ├── demand_national_8760.csv
│   ├── regional_hourly_load_profile_2024_analysis.xlsx
│   └── (선택) pop_weights.csv
└── output_files/            모든 출력 CSV (없으면 자동 생성)
```

`main.py` 안의 파일명은 `Input_data/` 기준 상대경로로 해석됩니다. 절대경로도 그대로 동작합니다.

## 실행

```bash
python main.py                                  # CONFIG 설정대로 1회 실행
python main.py --list-sheets                    # 프로파일 탭 목록
python main.py -m 3 --sheet "regional_hourly_load_profile_20"
python main.py --methods 1,2,3,4                # 4가지 방식 비교 생성
```

CLI 인자는 `CONFIG` 를 덮어씁니다. 반복 작업은 `CONFIG` 를 고치고, 일회성 실험은 CLI를 쓰면 됩니다.

## Downscale method

| # | 이름 | 수식 | 시도별 형상 | Σ_p P_p(t) = N(t) |
|---|---|---|---|---|
| 1 | `population` | P_p(t) = N(t) · w_p | 전부 동일 | ✅ |
| 2 | `national-shape` | P_p(t) = N(t) · W_p | 전부 동일 | ✅ |
| 3 | `regional-shape` | P_p(t) = E_tot · R_p(t) / ΣΣR | 시도별 상이 | ❌ (연간 총량만) |
| 4 | `hourly-share` | P_p(t) = N(t) · s_p(t) | 시도별 상이 | ✅ |

- `w_p` — 시간불변 인구 기반 비중. 기본값은 기존 `demand_provincial_8760.csv` 에서 역산한 상수이며, `weights_file` 로 교체 가능합니다.
- `W_p` — 프로파일의 연간 전력량 비중.
- `s_p(t)` — 프로파일의 매시각 비율 (행 합 = 1).
- `R_p(t)` — 프로파일의 절대 MW. **method 3 전용**이며, 비율만 있는 탭을 지정하면 같은 워크북에서 national 기준계열을 자동으로 찾아 곱합니다.

method 3은 national의 시간 형상을 완전히 버리므로, 매 시각 17개 시도 합계가 national 수요와 어긋납니다. MACRO처럼 시각별 수급균형을 푸는 모델에서는 이 편차가 결과 해석에 영향을 줍니다. 시도별 형상 차이는 살리되 시각별 합계는 보존하고 싶다면 method 4를 쓰십시오.

## 주요 CONFIG 항목

| 키 | 설명 |
|---|---|
| `national_file` | 입력 demand CSV |
| `profile_file`, `profile_sheet` | 지역 프로파일 파일 + 참조 탭 |
| `method` | `"1"`~`"4"` 또는 이름 |
| `weights_file` | method 1용 비중 CSV (`province,weight`). `None` = 내장 기본값 |
| `shape_mode` | method 4용. `hourly` / `hour_of_day` / `hour_of_week` |
| `repeat_to` | national을 순환 반복할 길이 (336 → 8760). `None` = 그대로 |
| `drop_leap_day` | 프로파일이 8784행이면 2/29 제거 |
| `families`, `tags` | `None` = 자동탐지 |
| `flat_families` | 시간 형상 없이 상수 비중만 적용할 family. `None` = national에서 상수인 것 자동 |
| `province_order` | `"nzk"` (기존 파일과 동일) / `"official"` (행정코드순) |
| `output_file` | `None` = `demand_provincial_m{method}_{행수}.csv` 자동 생성 |

## 탭 선택 가이드

| 탭 | 내용 | 용도 |
|---|---|---|
| `provincial shape` | 시각별 비율 (행 합 = 1), 8784행 | method 1/2/4 |
| `regional_hourly_load_profile_20` | 실측 MW + national 열, 8784행 | method 3 |
| `2021_ref` … `2035_NDC` | 시나리오별 MW | 자동 정규화 후 사용 가능 |

시나리오 탭은 8784행 달력 위에 8760개 값만 채워져 있어 12/31이 비어 있습니다. 즉 2/29 이후 시각 라벨이 하루 밀려 있습니다. 스크립트가 경고를 띄우고 빈 행을 제거하지만, 비중 추출에는 `provincial shape` 또는 `regional_hourly_load_profile_20` 탭을 권장합니다.

## 검증 출력

매 실행마다 아래를 출력합니다.

- **연간 총량 검증** — family/tag별 national 합계 대비 시도 합계 상대오차
- **시각별 합계 최대 편차** — method 3에서만 0이 아님
- **시도별 부하율** (mean/peak) — method 1·2는 전 시도 동일, 3·4는 상이

## 라이브러리로 직접 쓰기

```python
import downscale as ds

prof = ds.load_profile("Input_data/regional_hourly_load_profile_2024_analysis.xlsx",
                       sheet="provincial shape")
nat  = ds.load_national("Input_data/demand_national_8760.csv", repeat_to=8760)
out  = ds.downscale(nat, prof, method="4")
print("\n".join(ds.validate(out, nat)["lines"]))
```
