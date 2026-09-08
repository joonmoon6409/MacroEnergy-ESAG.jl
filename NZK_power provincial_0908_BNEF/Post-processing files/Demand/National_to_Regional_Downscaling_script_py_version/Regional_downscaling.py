#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
downscale.py  --  NZK MACRO national -> provincial demand downscaling (라이브러리)

실행 진입점은 main.py 입니다. 이 모듈은 순수 함수/데이터만 제공합니다.

--------------------------------------------------------------------------
Downscale method
--------------------------------------------------------------------------
  1 | population       시간불변 인구 기반 비중 w_p 를 그대로 곱한다 (기존 방식).
                         P_p(t) = N(t) * w_p
                       모든 시도가 national과 똑같은 시간 형상을 갖는다.

  2 | national-shape   national 형상은 유지, 비중만 부하 기반으로 교체.
                         P_p(t) = N(t) * W_p,   W_p = 프로파일의 연간 전력량 비중
                       1과의 차이는 비중의 출처(인구 -> 실제 부하)뿐이다.

  3 | regional-shape   national은 '연간 총량'만 쓰고, 시간 형상은 시도별
                       프로파일을 개별 적용한다.
                         P_p(t) = E_total * R_p(t) / SUM(R)
                       시도별 첨두시각/부하율이 서로 달라진다. 대신 매 시각의
                       시도 합계는 N(t) 와 일치하지 않는다 (연간 총량만 일치).
                       절대 MW 프로파일이 필요하다.

  4 | hourly-share     매시각 비율을 그대로 적용 (1~3의 절충).
                         P_p(t) = N(t) * s_p(t)
                       시각별 시도 합계 = N(t) 를 만족하면서 시도별 형상 차이도
                       반영된다. 시각별 수급균형을 푸는 모델에는 보통 가장 안전.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

__all__ = [
    "PROVINCE_ORDER_OFFICIAL", "PROVINCE_ORDER_NZK", "DEFAULT_POPULATION_WEIGHTS",
    "METHOD_ALIASES", "METHOD_DESCRIPTIONS", "DownscaleError", "Profile",
    "list_sheets", "load_national", "load_profile", "load_weights",
    "detect_families_tags", "detect_flat_families", "downscale", "validate",
]


class DownscaleError(RuntimeError):
    """입력 데이터/설정 문제. main.py 에서 잡아 메시지만 출력한다."""


# ----------------------------------------------------------------------------
# 1. 시도 코드 / 상수
# ----------------------------------------------------------------------------

# 행정구역 코드 순
PROVINCE_ORDER_OFFICIAL = [
    "SEL", "PUS", "TAE", "INC", "KWJ", "DJJ", "USN", "SJG", "GGI",
    "GWN", "CNB", "CNA", "JNB", "JNA", "GNB", "GNA", "JEJ",
]

# 기존 demand_provincial_8760.csv 의 컬럼 순서 (drop-in 교체용)
PROVINCE_ORDER_NZK = [
    "SEL", "PUS", "TAE", "INC", "KWJ", "USN", "SJG", "GGI", "GWN",
    "CNA", "CNB", "DJJ", "JNB", "JNA", "GNB", "GNA", "JEJ",
]

# method 1 기본 비중: 기존 demand_provincial_8760.csv 에서 역산한 시간불변 상수.
# 부하 기반이 아니라 인구 분포에 가깝다 (SEL 20.4% vs 실제 부하 9.2%).
DEFAULT_POPULATION_WEIGHTS = {
    "SEL": 0.20440847, "PUS": 0.05715809, "TAE": 0.02650369, "INC": 0.05348305,
    "KWJ": 0.02340851, "DJJ": 0.01845247, "USN": 0.02865037, "SJG": 0.02040004,
    "GGI": 0.27001972, "GWN": 0.02604710, "CNB": 0.03758604, "CNA": 0.03962696,
    "JNB": 0.03477451, "JNA": 0.02941335, "GNB": 0.05908996, "GNA": 0.05921532,
    "JEJ": 0.01176234,
}

NAME_TO_CODE = {
    "seoul": "SEL", "서울": "SEL", "서울특별시": "SEL", "sel": "SEL",
    "busan": "PUS", "pusan": "PUS", "부산": "PUS", "부산광역시": "PUS", "pus": "PUS",
    "daegu": "TAE", "taegu": "TAE", "대구": "TAE", "대구광역시": "TAE", "tae": "TAE",
    "incheon": "INC", "인천": "INC", "인천광역시": "INC", "inc": "INC",
    "gwangju": "KWJ", "kwangju": "KWJ", "광주": "KWJ", "광주광역시": "KWJ", "kwj": "KWJ",
    "daejeon": "DJJ", "taejon": "DJJ", "대전": "DJJ", "대전광역시": "DJJ", "djj": "DJJ",
    "ulsan": "USN", "울산": "USN", "울산광역시": "USN", "usn": "USN",
    "sejong": "SJG", "세종": "SJG", "세종특별자치시": "SJG", "sjg": "SJG",
    "gyeonggi": "GGI", "gyeonggido": "GGI", "kyonggi": "GGI",
    "경기": "GGI", "경기도": "GGI", "ggi": "GGI",
    "gangwon": "GWN", "kangwon": "GWN", "강원": "GWN",
    "강원도": "GWN", "강원특별자치도": "GWN", "gwn": "GWN",
    "chungbuk": "CNB", "chungcheongbuk": "CNB", "chungcheongbukdo": "CNB",
    "충북": "CNB", "충청북도": "CNB", "cnb": "CNB",
    "chungnam": "CNA", "chungcheongnam": "CNA", "chungcheongnamdo": "CNA",
    "충남": "CNA", "충청남도": "CNA", "cna": "CNA",
    "jeonbuk": "JNB", "jeollabuk": "JNB", "jeollabukdo": "JNB", "chonbuk": "JNB",
    "전북": "JNB", "전라북도": "JNB", "전북특별자치도": "JNB", "jnb": "JNB",
    "jeonnam": "JNA", "jeollanam": "JNA", "jeollanamdo": "JNA", "chonnam": "JNA",
    "전남": "JNA", "전라남도": "JNA", "jna": "JNA",
    "gyeongbuk": "GNB", "gyeongsangbuk": "GNB", "gyeongsangbukdo": "GNB",
    "kyongbuk": "GNB", "경북": "GNB", "경상북도": "GNB", "gnb": "GNB",
    "gyeongnam": "GNA", "gyeongsangnam": "GNA", "gyeongsangnamdo": "GNA",
    "kyongnam": "GNA", "경남": "GNA", "경상남도": "GNA", "gna": "GNA",
    "jeju": "JEJ", "cheju": "JEJ", "제주": "JEJ",
    "제주도": "JEJ", "제주특별자치도": "JEJ", "jej": "JEJ",
}

METHOD_ALIASES = {
    "1": "population", "population": "population", "pop": "population",
    "2": "national-shape", "national-shape": "national-shape", "national_shape": "national-shape",
    "3": "regional-shape", "regional-shape": "regional-shape", "regional_shape": "regional-shape",
    "4": "hourly-share", "hourly-share": "hourly-share", "hourly_share": "hourly-share",
}

METHOD_DESCRIPTIONS = {
    "population":     "1 | P_p(t) = N(t) * w_p          시간불변 인구 비중 (기존 방식)",
    "national-shape": "2 | P_p(t) = N(t) * W_p          national 형상 유지 + 부하 기반 연간 비중",
    "regional-shape": "3 | P_p(t) = E_tot * R_p(t)/SUM  연간 총량만 사용 + 시도별 형상 개별 적용",
    "hourly-share":   "4 | P_p(t) = N(t) * s_p(t)       매시각 비율 적용 (시각별 합계 보존)",
}

SHAPE_MODES = ("hourly", "hour_of_day", "hour_of_week")


def normalize_name(s) -> str:
    return str(s).strip().lower().replace(" ", "").replace("-", "").replace("_", "")


def to_code(colname) -> str | None:
    return NAME_TO_CODE.get(normalize_name(colname))


def _is_national_col(colname) -> bool:
    n = normalize_name(colname)
    return ("national" in n) or n.startswith("demandmw") or n in ("total", "sum", "합계", "전국")


def resolve_method(method) -> str:
    key = str(method).strip()
    if key not in METHOD_ALIASES:
        raise DownscaleError(
            f"알 수 없는 method '{method}'. 가능한 값: 1/2/3/4 또는 "
            f"{sorted(set(METHOD_ALIASES.values()))}")
    return METHOD_ALIASES[key]


# ----------------------------------------------------------------------------
# 2. 프로파일 컨테이너
# ----------------------------------------------------------------------------

@dataclass
class Profile:
    """시도별 지역 프로파일."""
    values: pd.DataFrame                    # 17개 시도, 비율 또는 MW
    datetime: pd.Series | None = None
    national_ref: pd.Series | None = None   # 시트 안의 national 열 (있으면)
    label: str = ""
    log: list[str] = field(default_factory=list)

    def __len__(self) -> int:
        return len(self.values)

    @property
    def is_share(self) -> bool:
        return bool(np.allclose(self.values.sum(axis=1).values, 1.0, atol=1e-4))

    @property
    def hourly_share(self) -> pd.DataFrame:
        """매시각 비율 s_p(t), 행 합 = 1."""
        return self.values.div(self.values.sum(axis=1), axis=0)

    @property
    def annual_weights(self) -> pd.Series:
        """연간 전력량 비중 W_p, 합 = 1."""
        tot = self.values.sum(axis=0)
        return tot / tot.sum()


# ----------------------------------------------------------------------------
# 3. 로딩
# ----------------------------------------------------------------------------

def list_sheets(profile_path: Path) -> list[str]:
    return list(pd.ExcelFile(profile_path).sheet_names)


def load_national(path: Path, repeat_to: int | None = None,
                  log: list[str] | None = None) -> pd.DataFrame:
    """national demand CSV 로드. repeat_to 가 주어지면 순환 반복으로 길이를 맞춘다."""
    log = log if log is not None else []
    if not Path(path).exists():
        raise DownscaleError(f"national 파일을 찾을 수 없습니다: {path}")
    df = pd.read_csv(path)
    df.columns = [str(c).strip() for c in df.columns]
    n0 = len(df)
    log.append(f"national {n0}행, 컬럼 {list(df.columns)}")

    if repeat_to and repeat_to != n0:
        reps = int(np.ceil(repeat_to / n0))
        df = pd.concat([df] * reps, ignore_index=True).iloc[:repeat_to].reset_index(drop=True)
        log.append(f"{n0}행 패턴 순환 반복 -> {len(df)}행")
    if "Time_Index" in df.columns:
        df["Time_Index"] = np.arange(1, len(df) + 1)
    return df


def _read_sheet(profile_path: Path, sheet: str | None) -> pd.DataFrame:
    suffix = Path(profile_path).suffix.lower()
    if suffix in (".xlsx", ".xlsm", ".xls"):
        if sheet is None:
            raise DownscaleError("엑셀 프로파일에는 sheet 이름이 필요합니다.")
        return pd.read_excel(profile_path, sheet_name=sheet)
    if suffix in (".csv", ".txt"):
        return pd.read_csv(profile_path)
    raise DownscaleError(f"지원하지 않는 프로파일 형식: {suffix}")


def _extract_provinces(raw: pd.DataFrame, label: str):
    dt = None
    for c in raw.columns:
        if normalize_name(c) in ("datetime", "date", "time", "timestamp", "시간"):
            dt = pd.to_datetime(raw[c], errors="coerce")
            break

    cols: dict[str, str] = {}
    natcol = None
    for c in raw.columns:
        code = to_code(c)
        if code is not None:
            if code in cols:
                raise DownscaleError(f"시도 코드 중복: '{c}' 와 '{cols[code]}' 가 모두 {code}.")
            cols[code] = c
        elif natcol is None and _is_national_col(c):
            natcol = c

    missing = [p for p in PROVINCE_ORDER_OFFICIAL if p not in cols]
    if missing:
        raise DownscaleError(
            f"'{label}' 에서 다음 시도를 찾지 못했습니다: {missing}\n"
            f"  인식된 컬럼: {sorted(cols)}\n  전체 컬럼: {list(raw.columns)}")

    df = pd.DataFrame({code: pd.to_numeric(raw[cols[code]], errors="coerce")
                       for code in PROVINCE_ORDER_OFFICIAL})
    nat = pd.to_numeric(raw[natcol], errors="coerce") if natcol else None
    n = len(df)
    if dt is not None:
        dt = dt.iloc[:n].reset_index(drop=True)
    if nat is not None:
        nat = nat.iloc[:n].reset_index(drop=True)
    return df, dt, nat


def _clean(df, dt, nat, label, drop_leap, log):
    if df.isna().any().any():
        bad = int(df.isna().any(axis=1).sum())
        raise DownscaleError(
            f"'{label}' 에 결측/수식 미계산 셀이 {bad}행 있습니다. "
            f"엑셀에서 열어 값을 저장하거나 다른 탭을 지정하세요.")

    zero = df.sum(axis=1).le(0)
    if zero.any():
        n_all, n_zero = len(df), int(zero.sum())
        log.append(f"[warn] 전 시도 값이 0인 시간대 {n_zero}행 제거.")
        if n_all == 8784 and n_all - n_zero == 8760:
            log.append("[warn] 이 탭은 8784행 달력 위에 8760개 값만 채워져 있습니다. "
                       "2/29 이후 시각 라벨이 하루 밀렸을 수 있습니다.")
        k = (~zero).values
        df = df[k].reset_index(drop=True)
        dt = dt[k].reset_index(drop=True) if dt is not None else None
        nat = nat[k].reset_index(drop=True) if nat is not None else None

    if drop_leap:
        if dt is not None and dt.notna().all():
            mask = ~((dt.dt.month == 2) & (dt.dt.day == 29))
            if (~mask).any():
                log.append(f"윤일(2/29) {int((~mask).sum())}시간 제거.")
                k = mask.values
                df, dt = df[k].reset_index(drop=True), dt[k].reset_index(drop=True)
                nat = nat[k].reset_index(drop=True) if nat is not None else None
        elif len(df) == 8784:
            i0 = 59 * 24
            keep = np.r_[0:i0, i0 + 24:8784]
            log.append("datetime 없이 8784행 -> 인덱스 기준 윤일 24시간 제거.")
            df = df.iloc[keep].reset_index(drop=True)
            nat = nat.iloc[keep].reset_index(drop=True) if nat is not None else None
    return df, dt, nat


def load_profile(path: Path, sheet: str | None = None, drop_leap_day: bool = True,
                 need_absolute: bool = False, log: list[str] | None = None) -> Profile:
    """
    지역 프로파일 로드.
    need_absolute=True (method 3) 이고 시트가 비율뿐이면, 같은 워크북에서
    national 기준계열을 찾아 곱해 절대 MW 로 변환한다.
    """
    log = log if log is not None else []
    path = Path(path)
    if not path.exists():
        raise DownscaleError(f"프로파일 파일을 찾을 수 없습니다: {path}")

    label = sheet or path.name
    df, dt, nat = _extract_provinces(_read_sheet(path, sheet), label)
    df, dt, nat = _clean(df, dt, nat, label, drop_leap_day, log)
    prof = Profile(values=df, datetime=dt, national_ref=nat, label=label, log=log)
    log.append(f"프로파일 '{label}': {len(prof)}행 x 17개 시도 "
               f"({'비율' if prof.is_share else 'MW'})")

    if need_absolute and prof.is_share:
        prof.values = _to_absolute_mw(prof, path, sheet, drop_leap_day, log)
    return prof


def _to_absolute_mw(prof: Profile, path: Path, sheet, drop_leap, log) -> pd.DataFrame:
    log.append("비율 시트입니다. method 3 을 위해 national 기준계열을 찾습니다.")
    df = prof.values
    nat = prof.national_ref
    if nat is not None and nat.notna().all() and nat.gt(0).all():
        log.append("  -> 같은 시트의 national 열 사용.")
        return df.mul(nat.values, axis=0)

    if path.suffix.lower() in (".xlsx", ".xlsm", ".xls"):
        for cand in list_sheets(path):
            if cand == sheet:
                continue
            try:
                d2, dt2, nat2 = _extract_provinces(_read_sheet(path, cand), cand)
                d2, dt2, nat2 = _clean(d2, dt2, nat2, cand, drop_leap, [])
            except DownscaleError:
                continue
            if len(d2) != len(df):
                continue
            if not np.allclose(d2.sum(axis=1).values, 1.0, atol=1e-4):
                log.append(f"  -> 탭 '{cand}' 의 MW 값을 기준계열로 사용.")
                return df.mul(d2.sum(axis=1).values, axis=0)
            if nat2 is not None and nat2.notna().all() and nat2.gt(0).all():
                log.append(f"  -> 탭 '{cand}' 의 national 열을 기준계열로 사용.")
                return df.mul(nat2.values, axis=0)

    raise DownscaleError(
        "method 3 에는 절대 MW 프로파일이 필요합니다. 비율만으로는 시도별 형상을 복원할 수 없습니다.\n"
        "  -> 'regional_hourly_load_profile_20' 처럼 MW 값이 있는 탭을 지정하세요.")


def load_weights(path: Path) -> dict[str, float]:
    """시도 비중 CSV (열1=시도명/코드, 열2=비중). 합이 1이 되도록 정규화."""
    df = pd.read_csv(path)
    if df.shape[1] < 2:
        raise DownscaleError("weights CSV 는 최소 2열(시도, 비중)이 필요합니다.")
    kc, vc = df.columns[0], df.columns[1]
    w = {}
    for _, r in df.iterrows():
        code = to_code(r[kc])
        if code is None:
            raise DownscaleError(f"weights 의 '{r[kc]}' 를 시도 코드로 해석할 수 없습니다.")
        w[code] = float(r[vc])
    missing = [p for p in PROVINCE_ORDER_OFFICIAL if p not in w]
    if missing:
        raise DownscaleError(f"weights 에 누락된 시도: {missing}")
    s = sum(w.values())
    return {k: v / s for k, v in w.items()}


# ----------------------------------------------------------------------------
# 4. family / tag 자동탐지
# ----------------------------------------------------------------------------

def detect_families_tags(national: pd.DataFrame) -> tuple[list[str], list[str]]:
    """
    'Demand_MW', 'Demand_MW_25', 'Demand_heat' -> families=['Demand_MW','Demand_heat'],
    tags=['','25','30','35'].  Demand_Zero 는 제외(그대로 통과).
    """
    cols = [c for c in national.columns
            if c.lower().startswith("demand") and c.lower() != "demand_zero"]
    tags, seen_t, families, seen_f = [], set(), [], set()
    for c in cols:
        parts = c.rsplit("_", 1)
        has_tag = len(parts) == 2 and parts[1].isdigit()
        t = parts[1] if has_tag else ""
        base = parts[0] if has_tag else c
        if t not in seen_t:
            seen_t.add(t); tags.append(t)
        if base not in seen_f:
            seen_f.add(base); families.append(base)
    tags = sorted(tags, key=lambda x: (x != "", x))
    return families, tags


def detect_flat_families(national: pd.DataFrame, families: list[str]) -> set[str]:
    """national 에서 시간에 따라 변하지 않는 family (예: Demand_heat=8700 상수)."""
    return {f for f in families if f in national.columns and national[f].nunique() == 1}


def build_groups(national, families, tags, log) -> list[tuple[str, str, str]]:
    """(출력이름, 소스컬럼, family). 소스가 없으면 base 컬럼으로 fallback."""
    out = []
    for fam in families:
        if fam not in national.columns:
            raise DownscaleError(
                f"national 파일에 '{fam}' 컬럼 없음. 있는 컬럼: {list(national.columns)}")
        for tag in tags:
            name = fam if tag == "" else f"{fam}_{tag}"
            src = name if name in national.columns else fam
            if src != name:
                log.append(f"'{name}' 없음 -> '{fam}' 값 재사용.")
            out.append((name, src, fam))
    return out


# ----------------------------------------------------------------------------
# 5. 시간축 정렬 (method 4)
# ----------------------------------------------------------------------------

def align_share(share: pd.DataFrame, dt, n_target: int, mode: str) -> pd.DataFrame:
    if mode not in SHAPE_MODES:
        raise DownscaleError(f"shape_mode 는 {SHAPE_MODES} 중 하나여야 합니다.")
    n = len(share)
    if mode == "hourly":
        if n == n_target:
            return share.reset_index(drop=True)
        raise DownscaleError(
            f"shape_mode='hourly' 인데 길이 불일치 (profile={n}, national={n_target}).\n"
            f"  -> repeat_to={n} 로 national을 늘리거나 shape_mode='hour_of_day' 를 쓰세요.")
    period = 24 if mode == "hour_of_day" else 168
    if dt is not None and dt.notna().all():
        key = dt.dt.hour.values if period == 24 else dt.dt.dayofweek.values * 24 + dt.dt.hour.values
    else:
        key = np.arange(n) % period
    prof = share.groupby(key).mean().reindex(range(period)).ffill().bfill()
    prof = prof.div(prof.sum(axis=1), axis=0)
    return prof.iloc[np.arange(n_target) % period].reset_index(drop=True)


# ----------------------------------------------------------------------------
# 6. 핵심: downscale
# ----------------------------------------------------------------------------

def downscale(national: pd.DataFrame, profile: Profile, method: str = "4", *,
              weights: dict[str, float] | None = None,
              shape_mode: str = "hourly",
              families: list[str] | None = None,
              tags: list[str] | None = None,
              flat_families: set[str] | None = None,
              province_order: list[str] | None = None,
              decimals: int = 2,
              keep_national_cols: bool = True,
              log: list[str] | None = None) -> pd.DataFrame:
    """national demand DataFrame -> provincial demand DataFrame."""
    log = log if log is not None else []
    method = resolve_method(method)
    order = province_order or PROVINCE_ORDER_NZK
    n_target = len(national)

    auto_f, auto_t = detect_families_tags(national)
    families = families if families is not None else auto_f
    tags = tags if tags is not None else auto_t
    flat = flat_families if flat_families is not None else detect_flat_families(national, families)
    log.append(f"families={families}  tags={tags!r}")
    if flat:
        log.append(f"flat families (상수 비중 적용) = {sorted(flat)}")

    # 비중
    if method == "population":
        w = weights or DEFAULT_POPULATION_WEIGHTS
        s = sum(w.values())
        const_w = pd.Series({k: v / s for k, v in w.items()})
        log.append("시간불변 인구 비중 사용" + ("" if weights else " (내장 기본값)"))
    else:
        const_w = profile.annual_weights
        log.append("프로파일 연간 전력량 비중 사용")
    log.append("상위 5: " + ", ".join(
        f"{k} {v*100:.2f}%" for k, v in const_w.sort_values(ascending=False).head(5).items()))

    # 시간 형상
    aligned = prof_frac = None
    if method == "hourly-share":
        aligned = align_share(profile.hourly_share, profile.datetime, n_target, shape_mode)
    elif method == "regional-shape":
        if len(profile) != n_target:
            raise DownscaleError(
                f"method 3: 프로파일 길이({len(profile)}) != 출력 길이({n_target}). "
                f"repeat_to={len(profile)} 로 맞추세요.")
        prof_frac = profile.values / profile.values.values.sum()   # 전체 합 = 1

    groups = build_groups(national, families, tags, log)

    new_cols, names = {}, []
    for fam in families:
        items = [(nm, src) for nm, src, f in groups if f == fam]
        is_flat = fam in flat
        for code in order:                       # province-major
            for nm, src in items:                # year-minor
                v = national[src].values
                if is_flat or method in ("population", "national-shape"):
                    vals = v * const_w[code]
                elif method == "hourly-share":
                    vals = v * aligned[code].values
                else:                            # regional-shape
                    vals = v.sum() * prof_frac[code].values
                col = f"{nm}_{code}"
                new_cols[col] = vals
                names.append(col)

    out = national.copy() if keep_national_cols else pd.DataFrame()
    if not keep_national_cols and "Time_Index" in national.columns:
        out["Time_Index"] = national["Time_Index"].values
    out = pd.concat([out, pd.DataFrame(new_cols)[names]], axis=1)
    if decimals >= 0:
        out[names] = out[names].round(decimals)

    out.attrs["method"] = method
    out.attrs["groups"] = groups
    out.attrs["province_order"] = order
    out.attrs["families"] = families
    return out


# ----------------------------------------------------------------------------
# 7. 검증 리포트
# ----------------------------------------------------------------------------

def validate(out: pd.DataFrame, national: pd.DataFrame, tol: float = 1e-4) -> dict:
    """연간 총량 / 시각별 합계 / 시도별 부하율 점검. dict + 출력용 lines 반환."""
    method = out.attrs.get("method", "?")
    groups = out.attrs.get("groups", [])
    order = out.attrs.get("province_order", PROVINCE_ORDER_NZK)
    families = out.attrs.get("families", [])

    lines, ok = [], True
    lines.append("연간 총량 검증")
    for nm, src, _ in groups:
        cols = [f"{nm}_{c}" for c in order]
        tp, tn = out[cols].sum(axis=1).sum(), national[src].sum()
        err = abs(tp - tn) / max(abs(tn), 1e-9)
        ok &= err < tol
        lines.append(f"  {'OK ' if err < tol else '!! '}{nm:18s} "
                     f"national={tn:14,.1f}  provincial={tp:14,.1f}  오차={err:.2e}")

    gap = None
    if families:
        fam0 = families[0]
        cols0 = [f"{fam0}_{c}" for c in order]
        gap = float((out[cols0].sum(axis=1) - national[fam0]).abs().max())
        note = "   <- method 3 은 시각별 일치를 보장하지 않습니다" if method == "regional-shape" else ""
        lines.append(f"  시각별 합계 최대 편차 ({fam0}): {gap:,.1f} MW{note}")

        lf = {c: out[f"{fam0}_{c}"].mean() / out[f"{fam0}_{c}"].max() for c in order}
        lines.append(f"시도별 부하율 (mean/peak, {fam0})")
        lines.append("  " + ", ".join(f"{c} {v*100:.0f}%" for c, v in lf.items()))
    else:
        lf = {}

    return {"ok": ok, "hourly_gap_mw": gap, "load_factors": lf, "lines": lines}