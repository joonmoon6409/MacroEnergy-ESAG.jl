#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
main.py  --  NZK MACRO national -> provincial demand 변환 실행 스크립트

폴더 구조
    ./Input_data/     입력 파일 (national CSV, 지역 프로파일 xlsx, weights CSV)
    ./output_files/   출력 CSV
    downscale.py      변환 로직 (라이브러리)
    main.py           이 파일 -- 설정 + 실행

사용법
    아래 CONFIG 를 수정한 뒤:
        python main.py

    또는 명령줄로 덮어쓰기:
        python main.py --method 3 --sheet "regional_hourly_load_profile_20"
        python main.py --list-sheets
        python main.py --methods 1,2,3,4        # 여러 방식 한 번에 비교 생성

    CONFIG 파일명은 Input_data/ 기준 상대경로로 해석됩니다 (절대경로도 가능).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

import downscale as ds

# ============================================================================
# CONFIG  --  여기만 고치면 됩니다
# ============================================================================

ROOT = Path(__file__).resolve().parent
INPUT_DIR = ROOT / "Input_data"
OUTPUT_DIR = ROOT / "output_files"

CONFIG = {
    # --- 1) 입력 demand 파일 -------------------------------------------------
    "national_file": "demand_national_8760.csv",

    # --- 2) 지역 프로파일 + 참조 탭 ------------------------------------------
    #     탭 목록은  python main.py --list-sheets  로 확인
    #     'provincial shape'                 : 시각별 비율 (method 1/2/4 용)
    #     'regional_hourly_load_profile_20'  : 실측 MW      (method 3 권장)
    #     '2025_ref' / '2030_NDC' 등         : 시나리오 탭 (MW, 자동 정규화)
    
    "profile_file": "regional_hourly_load_profile_2024_analysis.xlsx",
    "profile_sheet": "provincial shape",

    # --- 3) downscale 방식 ---------------------------------------------------
    #     1 population      P_p(t) = N(t) * w_p        (시간불변 인구 비중)
    #     2 national-shape  P_p(t) = N(t) * W_p        (national 형상 유지)
    #     3 regional-shape  P_p(t) = E_tot * R_p(t)/S  (연간 총량만 + 시도별 형상)
    #     4 hourly-share    P_p(t) = N(t) * s_p(t)     (매시각 비율)
    "method": "4",

    # method 1 전용. None 이면 내장 인구 비중 사용.
    # CSV 예:  province,weight  /  Seoul,0.2044  /  ...
    "weights_file": None,

    # method 4 전용. profile 과 national 길이가 다를 때의 매칭 방식.
    #   'hourly' | 'hour_of_day' | 'hour_of_week'
    "shape_mode": "hourly",

    # --- 4) 시간축 ------------------------------------------------------------
    # national 을 이 길이까지 순환 반복 (336시간 대표패턴 -> 8760). None 이면 그대로.
    "repeat_to": 8760,
    "drop_leap_day": True,      # 프로파일이 8784행이면 2/29 제거

    # --- 5) 컬럼 --------------------------------------------------------------
    "families": None,           # None = 자동탐지 (예: ["Demand_MW", "Demand_heat"])
    "tags": None,               # None = 자동탐지 (예: ["", "25", "30", "35"])
    "flat_families": None,      # None = national에서 상수인 family 자동 (Demand_heat 등)
    "province_order": "nzk",    # "nzk" (기존 파일과 동일) | "official" (행정코드순)
    "keep_national_cols": True,
    "decimals": 2,

    # --- 6) 출력 --------------------------------------------------------------
    # None 이면  demand_provincial_{method}_{행수}.csv  로 자동 생성
    "output_file": None,
}

# ============================================================================


def resolve_in(name) -> Path | None:
    if name is None:
        return None
    p = Path(name)
    return p if p.is_absolute() else INPUT_DIR / p


def resolve_out(name) -> Path:
    p = Path(name)
    return p if p.is_absolute() else OUTPUT_DIR / p


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="NZK MACRO: national demand -> 17개 시도 provincial demand",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="\n".join(["method:"] + ["  " + v for v in ds.METHOD_DESCRIPTIONS.values()]),
    )
    p.add_argument("--national", help="Input_data 내 national CSV 파일명")
    p.add_argument("--profile", help="Input_data 내 지역 프로파일 파일명")
    p.add_argument("--sheet", help="참조할 엑셀 탭 이름")
    p.add_argument("--method", "-m", help="1|2|3|4 (또는 이름)")
    p.add_argument("--methods", help="쉼표구분. 여러 방식을 한 번에 실행 (예: 1,2,3,4)")
    p.add_argument("--weights", help="method 1 용 비중 CSV 파일명")
    p.add_argument("--shape-mode", choices=list(ds.SHAPE_MODES))
    p.add_argument("--repeat-to", type=int)
    p.add_argument("--keep-leap-day", action="store_true")
    p.add_argument("--province-order", choices=["nzk", "official"])
    p.add_argument("--decimals", type=int)
    p.add_argument("--output", help="출력 파일명 (output_files 기준)")
    p.add_argument("--list-sheets", action="store_true", help="프로파일 탭 목록 출력 후 종료")
    return p.parse_args(argv)


def apply_overrides(cfg: dict, a) -> dict:
    cfg = dict(cfg)
    for key, val in [
        ("national_file", a.national), ("profile_file", a.profile),
        ("profile_sheet", a.sheet), ("method", a.method), ("weights_file", a.weights),
        ("shape_mode", a.shape_mode), ("repeat_to", a.repeat_to),
        ("province_order", a.province_order), ("decimals", a.decimals),
        ("output_file", a.output),
    ]:
        if val is not None:
            cfg[key] = val
    if a.keep_leap_day:
        cfg["drop_leap_day"] = False
    return cfg


def run_one(cfg: dict, national_raw: pd.DataFrame | None = None) -> Path:
    """설정 하나로 변환 1회 실행. 출력 경로를 반환."""
    method = ds.resolve_method(cfg["method"])
    print("=" * 78)
    print(f"method {cfg['method']}  ->  {ds.METHOD_DESCRIPTIONS[method]}")
    print("=" * 78)

    log: list[str] = []

    # --- 프로파일 먼저 (method 3 의 출력 길이 결정에 필요) ---------------------
    profile = ds.load_profile(
        resolve_in(cfg["profile_file"]),
        sheet=cfg["profile_sheet"],
        drop_leap_day=cfg["drop_leap_day"],
        need_absolute=(method == "regional-shape"),
        log=log,
    )

    repeat_to = cfg["repeat_to"]
    if method == "regional-shape" and (repeat_to is None or repeat_to != len(profile)):
        repeat_to = len(profile)
        log.append(f"method 3 -> 출력 길이를 프로파일 길이 {repeat_to} 로 맞춥니다.")

    national = ds.load_national(resolve_in(cfg["national_file"]), repeat_to=repeat_to, log=log)

    weights = ds.load_weights(resolve_in(cfg["weights_file"])) if cfg["weights_file"] else None
    order = (ds.PROVINCE_ORDER_NZK if cfg["province_order"] == "nzk"
             else ds.PROVINCE_ORDER_OFFICIAL)

    out = ds.downscale(
        national, profile, cfg["method"],
        weights=weights,
        shape_mode=cfg["shape_mode"],
        families=cfg["families"],
        tags=cfg["tags"],
        flat_families=set(cfg["flat_families"]) if cfg["flat_families"] else None,
        province_order=order,
        decimals=cfg["decimals"],
        keep_national_cols=cfg["keep_national_cols"],
        log=log,
    )

    for line in log:
        print("  " + line)

    report = ds.validate(out, national)
    print()
    for line in report["lines"]:
        print(line)

    name = cfg["output_file"] or f"demand_provincial_m{cfg['method']}_{len(out)}.csv"
    path = resolve_out(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(path, index=False)
    print(f"\n저장: {path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}"
          f"  ({len(out)}행 x {len(out.columns)}열)")
    if not report["ok"]:
        print("경고: 총량 오차가 허용범위를 넘습니다.", file=sys.stderr)
    print()
    return path


def main(argv=None) -> int:
    a = parse_args(argv)
    cfg = apply_overrides(CONFIG, a)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    if not INPUT_DIR.exists():
        print(f"오류: 입력 폴더가 없습니다 -> {INPUT_DIR}", file=sys.stderr)
        return 1

    if a.list_sheets:
        path = resolve_in(cfg["profile_file"])
        print(f"{path.name} 탭 목록:")
        for s in ds.list_sheets(path):
            print(f"  - {s}")
        return 0

    methods = [m.strip() for m in a.methods.split(",")] if a.methods else [cfg["method"]]
    try:
        for m in methods:
            c = dict(cfg, method=m)
            if len(methods) > 1:
                c["output_file"] = None       # 방식별로 파일명 분리
            run_one(c)
    except ds.DownscaleError as e:
        print(f"\n오류: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())