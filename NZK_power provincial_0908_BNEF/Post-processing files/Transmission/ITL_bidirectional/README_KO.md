# Interface Transfer Limit 기반 도간(양방향) 송전용량

이 폴더는 NZK 지방 모델의 도간 송전 자산 파일
`outputs/transmission_v2_2021_ITL_bidir.csv` 를 **어떻게 만들었는지 재현·학습**할 수
있게 모아둔 **자기완결 패키지**입니다. 회랑 용량을 회선 열적정격 단순합이 아니라
**Interface Transfer Limit(ITL, 인터페이스 전송한계)** 으로 산정했습니다.

*(영어판은 `README.md`)*

---

## 1. 왜 회선 정격을 그냥 더하면 안 되나

모델은 17개 도(zone)와 32개 도간 회랑으로 구성됩니다. 회랑마다 숫자 하나가 필요합니다:
그 도 경계를 넘어 얼마만큼의 전력이 흐를 수 있는가.

기존 모델 파일(`inputs/transmission_v2_2021_MODEL_TEMPLATE.csv`)은 그 값을
**그 경계를 지나는 모든 송전선의 열적정격(Rate A)을 전압단계 구분 없이 단순 합산**한
값으로 넣었습니다. 이건 실제 전달가능량을 과대추정합니다:

* 망상(meshed) AC 계통에서 전력조류는 Kirchhoff 법칙(loop flow)을 따릅니다. 어떤
  회선이 다른 회선보다 먼저 정격에 도달하므로, 병렬 회선을 동시에 정격까지 다 쓸 수
  없습니다.
* 안전 derating 없음: 실제 운영은 임의의 단일 설비 고장(**N-1**)을 견뎌야 하므로,
  사고 전 전송량은 산술합보다 훨씬 아래로 제한됩니다.
* 방향 의존: 같은 인터페이스라도 방향에 따라 전송 가능량이 크게 다릅니다.

한국의 경우: 정격합 파일은 32개 회랑 합계 **≈418 GW** — 전국 최대수요의 약 4.6배,
단일 회랑이 71 GW에 달하기도 했습니다.

## 2. 방법 — NREL zonal Interface Transfer Limit

`reference/2308.03612v1_NREL_zonal_ITL_method.pdf`
Brown, Barrows, Wright, Brinkman, Dalvi, Zhang, Mai (NREL), *"A general method
for estimating zonal transmission interface limits from nodal network data"*,
arXiv:2308.03612 (2023).

두 zone 사이의 각 인터페이스에 대해, 각 방향마다,
**nodal 계통의 DC 조류(PTDF) 표현** 위에서 선형계획(LP)을 풉니다:

```
        최대화(정방향) / 최소화(역방향)     Σ_{l ∈ 경계 통과선}  F(l)

제약
        F(l) = Σ_b PTDF[l, b] · G(b)              # DC 조류 (Kirchhoff)
        −정격(l) ≤ F(l) ≤ 정격(l)  ∀ 회선        # 전 계통 열적 제약
        G(b) ≥ 0   발전 모선                      # 주입만 가능
        G(b) ≤ 0   부하 모선                      # 인출만 가능
        G(b) = 0   순수 통과 모선
        Σ_b G(b) = 0                              # 전력 균형
```

* `F(l)` = 회선 `l`의 조류, `G(b)` = 모선 `b`의 순주입. 둘 다 결정변수. `PTDF` 행렬은
  회선 리액턴스 + 망 토폴로지에서 계산합니다.
* **`n-0`** ITL: 전 회선 정상.
  **`n-1`** ITL: 경계 통과선 중 조류가 가장 큰 1개를 제거하고 PTDF 재구성 후 재풀이.
  (전체 N-1 스윕에 대한 논문 자체의 단순화)
* 인터페이스는 비대칭이므로 LP를 **양방향** 독립적으로 풉니다.

NREL 논문은 Julia 패키지(`InterfaceLimits.jl`)를 제공합니다. 여기 `compute_itl.py` 는
**같은 LP(논문 식 1–4)를 파이썬으로 독립 재구현**한 것입니다. 논문의 5-bus 테스트로
검증했습니다 (`compute_itl.py --validate` → 인터페이스 1‖2 = 719 MW, 2‖3 = 240,
1‖3 = 400).

## 3. 파이프라인

```
  GIST nodal 계통  (inputs/gist_data_newest/)
    bus.csv   → 모선→도, 모선 유형 (발전 / 부하 / 통과)
    line.csv  → AC 회선 리액턴스 x_pu + 정격 rate_a_mva
    trafo2w.csv, trafo3w.csv → 변압기 (리액턴스, PTDF 망 구성용)
        │
        │  compute_itl.py
        ▼
  outputs/province_ITL.csv
    회랑별:  Σ회선정격,  ITL n-0 (A→B / B→A),  ITL n-1 (A→B / B→A)
        │
        │  build_transmission_ITL.py  (+ hvdc_lines.csv의 HVDC,
        │                               + 모델 템플릿의 거리/비용)
        ▼
  outputs/transmission_v2_2021_ITL_bidir.csv     ← 산출물
  outputs/transmission_v2_2021_ITL_oneway.csv    ← 방향별 변형, 참고용
```

### 단일 양방향 값을 어떻게 정했나

모델의 `TransmissionLink` 는 **양방향 모두**에 대해 성립해야 하는 용량 **하나**를
가집니다. 따라서 회랑마다:

```
    existing_capacity  =  min( ITL_ac(A→B, n-1),  ITL_ac(B→A, n-1) )  +  HVDC(A↔B)
```

* 두 방향 AC ITL의 `min(...)` → 양방향 모두 보장되는 한계 (보수적 선택). `max` 나
  평균을 쓰려면 `build_transmission_ITL.py` 의 표시된 한 줄(`ac_min = min(acs)`)만
  바꾸면 됩니다.
* **HVDC는 위에 가산, derating 안 함.** DC 링크 조류는 컨버터가 스케줄하며 AC loop
  flow의 영향을 받지 않으므로 가산적입니다 (논문 §2.3, Jesse 확인). 제주–전남 =
  900 MW (HVDC 3링크); 당진–고덕 3000 MW는 경기–충남 회랑에 포함.
* `n-1` 이 기본 AC 상정고장 수준입니다 (`build_transmission_ITL.py` 에서
  `LEVEL = "itl_n0"` 로 바꾸면 덜 보수적인 n-0).
* 용량 외 컬럼(`distance`, `loss_fraction`, `investment_cost`, `lifetime`, `wacc`,
  `max_capacity`, `can_expand`)은 `inputs/transmission_v2_2021_MODEL_TEMPLATE.csv`
  에서 그대로 복사됩니다.

### 결과

| | 32개 회랑 합계 |
|---|---|
| 기존 파일 (Σ열적정격, 양방향) | 418 GW |
| **bidir ITL 파일 (min방향 n-1 + HVDC)** | **171 GW** |
| oneway ITL 파일 (양방향 합) | 399 GW |

물리적으로 타당한지 점검:

* **경기–서울**: 29 GW → **14 GW**. 잘 알려진 수도권 유입한계 ~13–16 GW와 일치.
* **경남–울산**: 71 GW → **4 GW** (min 방향). 71 GW는 고리/신고리 765 kV 원전
  개폐소가 부산/울산/경남 3도 접점에 걸친 아티팩트였고, loop flow + N-1로 대부분
  제거됨.

## 4. 파일

```
README.md / README_KO.md          이 문서 (영/한)
run_all.sh                        한 번에: validate → compute_itl → build

compute_itl.py                    ITL 솔버 (PTDF-LP, 논문 식 1-4)
build_transmission_ITL.py         ITL + 템플릿 + HVDC  →  송전 CSV
build_province_transmission_capacity_DEMO.py
                                  GIST의 province_transmission_capacity.csv 가
                                  bus.csv + line.csv 에서 어떻게 유도되는지 시연 (배경 학습용)

inputs/
  transmission_v2_2021_MODEL_TEMPLATE.csv   현재 모델 송전 파일 (토폴로지, 거리, 비용)
                                            — 템플릿으로만 사용
  [MACRO example] transmission asset.csv    이 템플릿의 출처인 MacroEnergy 예제
  gist_data_newest/
    data/bus.csv line.csv trafo2w.csv trafo3w.csv gen.csv load.csv
    data/GIST_data_README.md                GIST 재구성 계통의 출처
    results/total_results/province_transmission_capacity.csv   회랑별 Σ정격
    results/results_by_voltage/hvdc_lines.csv                  HVDC 4개 링크

outputs/
  province_ITL.csv                          원시 ITL (n-0 & n-1, 양방향)
  transmission_v2_2021_ITL_bidir.csv        ← 메인: 32행, TransmissionLink
  transmission_v2_2021_ITL_oneway.csv       64행, OneWayTransmissionLink (방향별)
  itl_run.log                               compute_itl.py 실행 로그

reference/
  2308.03612v1_NREL_zonal_ITL_method.pdf    NREL 방법 논문
```

## 5. 실행 방법

```bash
# 솔버가 논문의 5-bus 예제를 재현하는지 빠른 확인
python3 compute_itl.py --validate

# 전체 재계산 (노트북에서 ~15-20분) + CSV 재생성
bash run_all.sh
```

의존성: `python3`, `numpy`, `scipy` (HiGHS LP 솔버는 scipy ≥1.9에 포함).

## 6. 주의 / 한계

* 이건 NREL 방법의 **재구현**이지 `InterfaceLimits.jl` 패키지가 아닙니다. 논문의
  5-bus 테스트는 통과하나, 대형 계통에서 패키지와 교차검증은 안 했습니다.
* **3권선 변압기**는 HV↔MV 브랜치 하나로 근사 (3차 권선은 통과조류 없음).
* **n-1** 은 망 전체가 아니라 *인터페이스 통과선* 중 최악 1개만 제거 — 논문 자체의
  단순화 (완전 N-1 스윕은 ~1000배 비쌈).
* 논문을 따라, 모선 주입은 설비 발전용량이나 관측 부하분담률로 **제한하지 않음** —
  ITL은 *망 자체*의 물리적 능력. 이 제약을 넣으면 ITL이 더 낮아집니다.
* **FACTS / 이상기 미모델링** (GIST 데이터에 FACTS 11개 존재) — 넣으면 일부 ITL이
  올라갈 수 있음.
* 결측/0 리액턴스는 작은 기본값(1e-4 pu)으로 대체.
* `loss_fraction` 은 전 회랑 템플릿의 균일 0.03 유지 — 기존 모델 이슈, 이번 범위 밖.
* GIST nodal 재구성 자체가 공개데이터 기반 모델(~2024 계통)이지 KEPCO 내부 케이스가
  아님. KEPCO 계통계획 담당자의 gut-check가 여전히 필요.
* `OneWayTransmissionLink`(방향별 변형)는 최신 MacroEnergy 릴리스에만 존재.
  양방향 `TransmissionLink` 파일이 안전한 기본값.

## 7. 참고문헌

1. Brown et al. (NREL), arXiv:2308.03612 (2023). 방법 논문. 코드:
   `github.com/NREL-Sienna/InterfaceLimits.jl`
2. Li & Bo (2010), *Small test systems for power system economic studies*,
   IEEE PES GM — 검증에 쓴 5-bus 계통.
3. GIST 공개데이터 한국 계통 재구성 — `inputs/gist_data_newest/data/GIST_data_README.md` 참조.
