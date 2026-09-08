# NZK MACRO — national → provincial demand downscaling (Julia)

## 폴더 구조

```
.
├── main.jl                  실행 진입점 (CONFIG + CLI)
├── Downscale.jl             변환 로직 (module Downscale)
├── setup.jl                 최초 1회 패키지 설치
├── Input_data/              모든 입력 파일
│   ├── demand_national_8760.csv
│   ├── regional_hourly_load_profile_2024_analysis.xlsx
│   └── (선택) pop_weights.csv
└── output_files/            모든 출력 CSV (없으면 자동 생성)
```

`main.jl` 안의 파일명은 `Input_data/` 기준 상대경로로 해석됩니다. 절대경로도 그대로 동작합니다.

## 최초 1회

```bash
julia setup.jl
```

`CSV`, `DataFrames`, `XLSX` 를 이 폴더 전용 환경에 설치하고 `Project.toml` / `Manifest.toml` 을 생성합니다. `Dates`, `Printf`, `Statistics` 는 표준 라이브러리라 별도 설치가 필요 없습니다.

VS Code를 쓰신다면 이 폴더를 열고 하단 상태바의 Julia env를 이 폴더로 바꾸면 `--project` 없이 동작합니다.

## 실행

```bash
julia --project=. main.jl                                  # CONFIG 설정대로 1회 실행
julia --project=. main.jl --list-sheets                    # 프로파일 탭 목록
julia --project=. main.jl -m 3 --sheet "regional_hourly_load_profile_20"
julia --project=. main.jl --methods 1,2,3,4                # 4가지 방식 비교 생성
julia --project=. main.jl --help
```

CLI 인자는 `CONFIG` 를 덮어씁니다. 반복 작업은 `CONFIG` 를 고치고, 일회성 실험은 CLI를 쓰면 됩니다.

`main.jl` 은 `PROGRAM_FILE` 을 확인하므로, REPL이나 VS Code에서 `include("main.jl")` 해도 자동 실행되지 않습니다. 그때는 직접 호출하십시오.

```julia
include("main.jl")
main(["--methods", "1,4"])
```

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
| `weights_file` | method 1용 비중 CSV (`province,weight`). `nothing` = 내장 기본값 |
| `shape_mode` | method 4용. `"hourly"` / `"hour_of_day"` / `"hour_of_week"` |
| `repeat_to` | national을 순환 반복할 길이 (336 → 8760). `nothing` = 그대로 |
| `drop_leap_day` | 프로파일이 8784행이면 2/29 제거 |
| `families`, `tags` | `nothing` = 자동탐지 |
| `flat_families` | 시간 형상 없이 상수 비중만 적용할 family. `nothing` = national에서 상수인 것 자동 |
| `province_order` | `"nzk"` (기존 파일과 동일) / `"official"` (행정코드순) |
| `output_file` | `nothing` = `demand_provincial_m{method}_{행수}.csv` 자동 생성 |

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

```julia
include("Downscale.jl")
using .Downscale

prof = load_profile("Input_data/regional_hourly_load_profile_2024_analysis.xlsx";
                    sheet = "provincial shape")
nat  = load_national("Input_data/demand_national_8760.csv"; repeat_to = 8760)
res  = downscale(nat, prof, "4")

println(join(validate(res, nat).lines, "\n"))
CSV.write("output_files/out.csv", res.df)
```

주요 타입/함수

| 이름 | 설명 |
|---|---|
| `Profile` | `values::Matrix{Float64}` (시간 × 17, `PROVINCE_ORDER_OFFICIAL` 순), `datetime`, `national_ref`, `label` |
| `nrows`, `is_share`, `hourly_share`, `annual_weights` | `Profile` 조회 함수 |
| `DownscaleResult` | `df`, `method`, `groups`, `order`, `families` |
| `DownscaleError` | 입력/설정 오류. `main.jl` 이 잡아 메시지만 출력 |

## Python 버전과의 차이

로직·출력·CLI는 동일합니다. Julia 관례에 맞춘 부분만 다릅니다.

- `Profile.values` 가 DataFrame이 아니라 `Matrix{Float64}` 입니다. 행 합/정규화가 훨씬 간결해집니다.
- pandas의 `df.attrs` 가 없어 `DownscaleResult` 구조체로 메타데이터를 전달합니다.
- `None` → `nothing`, `dict` → `Dict{String,Any}`, `set` → `Set{String}`.
- argparse 대신 손으로 짠 파서를 씁니다. 외부 패키지 의존을 늘리지 않기 위해서입니다.
