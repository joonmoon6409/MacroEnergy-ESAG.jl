#=
Downscale.jl  --  NZK MACRO national -> provincial demand downscaling (라이브러리)

실행 진입점은 main.jl 입니다. 이 모듈은 순수 함수/데이터만 제공합니다.

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
=#

module Downscale

using CSV
using DataFrames
using XLSX
using Dates
using Printf
using Statistics

export DownscaleError, Profile, DownscaleResult,
       PROVINCE_ORDER_OFFICIAL, PROVINCE_ORDER_NZK, DEFAULT_POPULATION_WEIGHTS,
       METHOD_ALIASES, METHOD_DESCRIPTIONS, SHAPE_MODES,
       list_sheets, load_national, load_profile, load_weights,
       detect_families_tags, detect_flat_families, resolve_method,
       downscale, validate, nrows, is_share, hourly_share, annual_weights

# ----------------------------------------------------------------------------
# 0. 예외
# ----------------------------------------------------------------------------

struct DownscaleError <: Exception
    msg::String
end

Base.showerror(io::IO, e::DownscaleError) = print(io, e.msg)

# ----------------------------------------------------------------------------
# 1. 시도 코드 / 상수
# ----------------------------------------------------------------------------

"행정구역 코드 순"
const PROVINCE_ORDER_OFFICIAL = String[
    "SEL", "PUS", "TAE", "INC", "KWJ", "DJJ", "USN", "SJG", "GGI",
    "GWN", "CNB", "CNA", "JNB", "JNA", "GNB", "GNA", "JEJ",
]

"기존 demand_provincial_8760.csv 의 컬럼 순서 (drop-in 교체용)"
const PROVINCE_ORDER_NZK = String[
    "SEL", "PUS", "TAE", "INC", "KWJ", "USN", "SJG", "GGI", "GWN",
    "CNA", "CNB", "DJJ", "JNB", "JNA", "GNB", "GNA", "JEJ",
]

const PROV_INDEX = Dict(code => i for (i, code) in enumerate(PROVINCE_ORDER_OFFICIAL))

#=
method 1 기본 비중: 기존 demand_provincial_8760.csv 에서 역산한 시간불변 상수.
부하 기반이 아니라 인구 분포에 가깝다 (SEL 20.4% vs 실제 부하 9.2%).
=#
const DEFAULT_POPULATION_WEIGHTS = Dict{String,Float64}(
    "SEL" => 0.20440847, "PUS" => 0.05715809, "TAE" => 0.02650369,
    "INC" => 0.05348305, "KWJ" => 0.02340851, "DJJ" => 0.01845247,
    "USN" => 0.02865037, "SJG" => 0.02040004, "GGI" => 0.27001972,
    "GWN" => 0.02604710, "CNB" => 0.03758604, "CNA" => 0.03962696,
    "JNB" => 0.03477451, "JNA" => 0.02941335, "GNB" => 0.05908996,
    "GNA" => 0.05921532, "JEJ" => 0.01176234,
)

const NAME_TO_CODE = Dict{String,String}(
    "seoul" => "SEL", "서울" => "SEL", "서울특별시" => "SEL", "sel" => "SEL",
    "busan" => "PUS", "pusan" => "PUS", "부산" => "PUS", "부산광역시" => "PUS", "pus" => "PUS",
    "daegu" => "TAE", "taegu" => "TAE", "대구" => "TAE", "대구광역시" => "TAE", "tae" => "TAE",
    "incheon" => "INC", "인천" => "INC", "인천광역시" => "INC", "inc" => "INC",
    "gwangju" => "KWJ", "kwangju" => "KWJ", "광주" => "KWJ", "광주광역시" => "KWJ", "kwj" => "KWJ",
    "daejeon" => "DJJ", "taejon" => "DJJ", "대전" => "DJJ", "대전광역시" => "DJJ", "djj" => "DJJ",
    "ulsan" => "USN", "울산" => "USN", "울산광역시" => "USN", "usn" => "USN",
    "sejong" => "SJG", "세종" => "SJG", "세종특별자치시" => "SJG", "sjg" => "SJG",
    "gyeonggi" => "GGI", "gyeonggido" => "GGI", "kyonggi" => "GGI",
    "경기" => "GGI", "경기도" => "GGI", "ggi" => "GGI",
    "gangwon" => "GWN", "kangwon" => "GWN", "강원" => "GWN",
    "강원도" => "GWN", "강원특별자치도" => "GWN", "gwn" => "GWN",
    "chungbuk" => "CNB", "chungcheongbuk" => "CNB", "chungcheongbukdo" => "CNB",
    "충북" => "CNB", "충청북도" => "CNB", "cnb" => "CNB",
    "chungnam" => "CNA", "chungcheongnam" => "CNA", "chungcheongnamdo" => "CNA",
    "충남" => "CNA", "충청남도" => "CNA", "cna" => "CNA",
    "jeonbuk" => "JNB", "jeollabuk" => "JNB", "jeollabukdo" => "JNB", "chonbuk" => "JNB",
    "전북" => "JNB", "전라북도" => "JNB", "전북특별자치도" => "JNB", "jnb" => "JNB",
    "jeonnam" => "JNA", "jeollanam" => "JNA", "jeollanamdo" => "JNA", "chonnam" => "JNA",
    "전남" => "JNA", "전라남도" => "JNA", "jna" => "JNA",
    "gyeongbuk" => "GNB", "gyeongsangbuk" => "GNB", "gyeongsangbukdo" => "GNB",
    "kyongbuk" => "GNB", "경북" => "GNB", "경상북도" => "GNB", "gnb" => "GNB",
    "gyeongnam" => "GNA", "gyeongsangnam" => "GNA", "gyeongsangnamdo" => "GNA",
    "kyongnam" => "GNA", "경남" => "GNA", "경상남도" => "GNA", "gna" => "GNA",
    "jeju" => "JEJ", "cheju" => "JEJ", "제주" => "JEJ",
    "제주도" => "JEJ", "제주특별자치도" => "JEJ", "jej" => "JEJ",
)

const METHOD_ALIASES = Dict{String,String}(
    "1" => "population", "population" => "population", "pop" => "population",
    "2" => "national-shape", "national-shape" => "national-shape",
    "national_shape" => "national-shape",
    "3" => "regional-shape", "regional-shape" => "regional-shape",
    "regional_shape" => "regional-shape",
    "4" => "hourly-share", "hourly-share" => "hourly-share",
    "hourly_share" => "hourly-share",
)

const METHOD_DESCRIPTIONS = Dict{String,String}(
    "population"     => "1 | P_p(t) = N(t) * w_p          시간불변 인구 비중 (기존 방식)",
    "national-shape" => "2 | P_p(t) = N(t) * W_p          national 형상 유지 + 부하 기반 연간 비중",
    "regional-shape" => "3 | P_p(t) = E_tot * R_p(t)/SUM  연간 총량만 사용 + 시도별 형상 개별 적용",
    "hourly-share"   => "4 | P_p(t) = N(t) * s_p(t)       매시각 비율 적용 (시각별 합계 보존)",
)

const METHOD_ORDER = String["population", "national-shape", "regional-shape", "hourly-share"]

const SHAPE_MODES = String["hourly", "hour_of_day", "hour_of_week"]

const DATETIME_NAMES = Set(["datetime", "date", "time", "timestamp", "시간"])

# ----------------------------------------------------------------------------
# 2. 문자열 / 숫자 헬퍼
# ----------------------------------------------------------------------------

normalize_name(s) = replace(lowercase(strip(string(s))), " " => "", "-" => "", "_" => "")

to_code(colname) = get(NAME_TO_CODE, normalize_name(colname), nothing)

function is_national_col(colname)
    n = normalize_name(colname)
    return occursin("national", n) || startswith(n, "demandmw") ||
           n in ("total", "sum", "합계", "전국")
end

function resolve_method(method)
    key = strip(string(method))
    haskey(METHOD_ALIASES, key) || throw(DownscaleError(
        "알 수 없는 method '$(method)'. 가능한 값: 1/2/3/4 또는 $(METHOD_ORDER)"))
    return METHOD_ALIASES[key]
end

"셀 값을 Float64 로. 변환 불가/결측이면 NaN."
function tonumber(x)
    x === missing && return NaN
    x === nothing && return NaN
    x isa Real && return Float64(x)
    if x isa AbstractString
        v = tryparse(Float64, strip(x))
        return v === nothing ? NaN : v
    end
    return NaN
end

"천 단위 구분자 + 소수 1자리."
function commafmt(x::Real)
    s = @sprintf("%.1f", x)
    parts = split(s, '.')
    ip = parts[1]
    frac = length(parts) > 1 ? parts[2] : "0"
    neg = startswith(ip, "-")
    neg && (ip = ip[2:end])
    buf = IOBuffer()
    n = length(ip)
    for (i, c) in enumerate(ip)
        print(buf, c)
        r = n - i
        if r > 0 && r % 3 == 0
            print(buf, ",")
        end
    end
    return (neg ? "-" : "") * String(take!(buf)) * "." * frac
end

# ----------------------------------------------------------------------------
# 3. Profile
# ----------------------------------------------------------------------------

"""
    Profile

시도별 지역 프로파일. `values` 는 (시간 x 17) 행렬이며 열 순서는
`PROVINCE_ORDER_OFFICIAL` 과 같다. 값은 비율(행 합 = 1) 또는 MW.
"""
mutable struct Profile
    values::Matrix{Float64}
    datetime::Union{Vector{DateTime},Nothing}
    national_ref::Union{Vector{Float64},Nothing}
    label::String
end

nrows(p::Profile) = size(p.values, 1)

rowsums(p::Profile) = vec(sum(p.values, dims = 2))

is_share(p::Profile) = all(abs.(rowsums(p) .- 1.0) .< 1e-4)

"매시각 비율 s_p(t), 행 합 = 1."
hourly_share(p::Profile) = p.values ./ rowsums(p)

"연간 전력량 비중 W_p (Dict), 합 = 1."
function annual_weights(p::Profile)
    tot = vec(sum(p.values, dims = 1))
    w = tot ./ sum(tot)
    return Dict{String,Float64}(PROVINCE_ORDER_OFFICIAL[i] => w[i]
                                for i in eachindex(PROVINCE_ORDER_OFFICIAL))
end

# ----------------------------------------------------------------------------
# 4. 파일 읽기
# ----------------------------------------------------------------------------

list_sheets(profile_path) = XLSX.sheetnames(XLSX.readxlsx(String(profile_path)))

function read_sheet(profile_path, sheet)
    path = String(profile_path)
    ext = lowercase(splitext(path)[2])
    if ext in (".xlsx", ".xlsm", ".xls")
        sheet === nothing && throw(DownscaleError("엑셀 프로파일에는 sheet 이름이 필요합니다."))
        tbl = try
            XLSX.readtable(path, String(sheet); stop_in_empty_row = false)
        catch err
            err isa MethodError || rethrow()
            XLSX.readtable(path, String(sheet))
        end
        return DataFrame(tbl)
    elseif ext in (".csv", ".txt")
        return DataFrame(CSV.File(path))
    end
    throw(DownscaleError("지원하지 않는 프로파일 형식: $(ext)"))
end

function parse_datetime_value(x)
    x isa DateTime && return x
    x isa Date && return DateTime(x)
    if x isa AbstractString
        s = strip(x)
        for fmt in (dateformat"yyyy-mm-dd HH:MM:SS", dateformat"yyyy-mm-ddTHH:MM:SS",
                    dateformat"yyyy-mm-dd HH:MM", dateformat"yyyy-mm-dd")
            v = tryparse(DateTime, s, fmt)
            v === nothing || return v
        end
    end
    return nothing
end

"열 전체가 파싱되면 Vector{DateTime}, 하나라도 실패하면 nothing."
function parse_datetime_col(col)
    out = Vector{DateTime}(undef, length(col))
    for (i, x) in enumerate(col)
        v = parse_datetime_value(x)
        v === nothing && return nothing
        out[i] = v
    end
    return out
end

function extract_provinces(raw::DataFrame, label::AbstractString)
    dt = nothing
    for c in names(raw)
        if normalize_name(c) in DATETIME_NAMES
            dt = parse_datetime_col(raw[!, c])
            break
        end
    end

    colmap = Dict{String,String}()
    natcol = nothing
    for c in names(raw)
        code = to_code(c)
        if code !== nothing
            if haskey(colmap, code)
                throw(DownscaleError("시도 코드 중복: '$(c)' 와 '$(colmap[code])' 가 모두 $(code)."))
            end
            colmap[code] = c
        elseif natcol === nothing && is_national_col(c)
            natcol = c
        end
    end

    miss = [p for p in PROVINCE_ORDER_OFFICIAL if !haskey(colmap, p)]
    if !isempty(miss)
        throw(DownscaleError(
            "'$(label)' 에서 다음 시도를 찾지 못했습니다: $(miss)\n" *
            "  인식된 컬럼: $(sort(collect(keys(colmap))))\n" *
            "  전체 컬럼: $(names(raw))"))
    end

    n = nrow(raw)
    M = Matrix{Float64}(undef, n, length(PROVINCE_ORDER_OFFICIAL))
    for (i, code) in enumerate(PROVINCE_ORDER_OFFICIAL)
        M[:, i] = tonumber.(raw[!, colmap[code]])
    end
    nat = natcol === nothing ? nothing : Float64[tonumber(x) for x in raw[!, natcol]]
    return M, dt, nat
end

"결측 검사 + 전 시도 0인 행 제거 + 윤일 제거."
function clean_profile(M::Matrix{Float64}, dt, nat, label::AbstractString,
                       drop_leap::Bool, log::Vector{String})
    if any(isnan, M)
        bad = count(i -> any(isnan, view(M, i, :)), 1:size(M, 1))
        throw(DownscaleError(
            "'$(label)' 에 결측/수식 미계산 셀이 $(bad)행 있습니다. " *
            "엑셀에서 열어 값을 저장하거나 다른 탭을 지정하세요."))
    end

    rs = vec(sum(M, dims = 2))
    keep = rs .> 0
    if !all(keep)
        n_all = size(M, 1)
        n_zero = n_all - count(keep)
        push!(log, "[warn] 전 시도 값이 0인 시간대 $(n_zero)행 제거.")
        if n_all == 8784 && n_all - n_zero == 8760
            push!(log, "[warn] 이 탭은 8784행 달력 위에 8760개 값만 채워져 있습니다. " *
                       "2/29 이후 시각 라벨이 하루 밀렸을 수 있습니다.")
        end
        M = M[keep, :]
        dt = dt === nothing ? nothing : dt[keep]
        nat = nat === nothing ? nothing : nat[keep]
    end

    if drop_leap
        if dt !== nothing
            mask = .!((month.(dt) .== 2) .& (day.(dt) .== 29))
            if !all(mask)
                push!(log, "윤일(2/29) $(count(.!mask))시간 제거.")
                M = M[mask, :]
                dt = dt[mask]
                nat = nat === nothing ? nothing : nat[mask]
            end
        elseif size(M, 1) == 8784
            i0 = 59 * 24                      # 1/1 ~ 2/28 = 1416시간
            idx = vcat(collect(1:i0), collect((i0+25):8784))
            push!(log, "datetime 없이 8784행 -> 인덱스 기준 윤일 24시간 제거.")
            M = M[idx, :]
            nat = nat === nothing ? nothing : nat[idx]
        end
    end
    return M, dt, nat
end

"""
    load_profile(path; sheet, drop_leap_day, need_absolute, log)

지역 프로파일 로드. `need_absolute=true` (method 3) 이고 시트가 비율뿐이면,
같은 워크북에서 national 기준계열을 찾아 곱해 절대 MW 로 변환한다.
"""
function load_profile(path; sheet = nothing, drop_leap_day::Bool = true,
                      need_absolute::Bool = false, log::Vector{String} = String[])
    p = String(path)
    isfile(p) || throw(DownscaleError("프로파일 파일을 찾을 수 없습니다: $(p)"))

    label = sheet === nothing ? basename(p) : String(sheet)
    M, dt, nat = extract_provinces(read_sheet(p, sheet), label)
    M, dt, nat = clean_profile(M, dt, nat, label, drop_leap_day, log)

    prof = Profile(M, dt, nat, label)
    push!(log, "프로파일 '$(label)': $(nrows(prof))행 x 17개 시도 " *
               "($(is_share(prof) ? "비율" : "MW"))")

    if need_absolute && is_share(prof)
        prof.values = to_absolute_mw(prof, p, sheet, drop_leap_day, log)
    end
    return prof
end

function to_absolute_mw(prof::Profile, path::AbstractString, sheet,
                        drop_leap::Bool, log::Vector{String})
    push!(log, "비율 시트입니다. method 3 을 위해 national 기준계열을 찾습니다.")
    M = prof.values
    nat = prof.national_ref
    if nat !== nothing && !any(isnan, nat) && all(nat .> 0)
        push!(log, "  -> 같은 시트의 national 열 사용.")
        return M .* nat
    end

    if lowercase(splitext(path)[2]) in (".xlsx", ".xlsm", ".xls")
        for cand in list_sheets(path)
            sheet !== nothing && cand == String(sheet) && continue
            local M2, dt2, nat2
            try
                M2, dt2, nat2 = extract_provinces(read_sheet(path, cand), cand)
                M2, dt2, nat2 = clean_profile(M2, dt2, nat2, cand, drop_leap, String[])
            catch err
                err isa DownscaleError || rethrow()
                continue
            end
            size(M2, 1) == size(M, 1) || continue
            rs2 = vec(sum(M2, dims = 2))
            if !all(abs.(rs2 .- 1.0) .< 1e-4)
                push!(log, "  -> 탭 '$(cand)' 의 MW 값을 기준계열로 사용.")
                return M .* rs2
            end
            if nat2 !== nothing && !any(isnan, nat2) && all(nat2 .> 0)
                push!(log, "  -> 탭 '$(cand)' 의 national 열을 기준계열로 사용.")
                return M .* nat2
            end
        end
    end

    throw(DownscaleError(
        "method 3 에는 절대 MW 프로파일이 필요합니다. 비율만으로는 시도별 형상을 복원할 수 없습니다.\n" *
        "  -> 'regional_hourly_load_profile_20' 처럼 MW 값이 있는 탭을 지정하세요."))
end

"""
    load_national(path; repeat_to, log)

national demand CSV 로드. `repeat_to` 가 주어지면 순환 반복으로 길이를 맞춘다.
"""
function load_national(path; repeat_to = nothing, log::Vector{String} = String[])
    p = String(path)
    isfile(p) || throw(DownscaleError("national 파일을 찾을 수 없습니다: $(p)"))

    df = DataFrame(CSV.File(p))
    for c in names(df)
        s = String(strip(c))
        s == c || rename!(df, c => s)
    end
    n0 = nrow(df)
    push!(log, "national $(n0)행, 컬럼 $(names(df))")

    if repeat_to !== nothing && repeat_to != n0
        reps = ceil(Int, repeat_to / n0)
        df = reduce(vcat, [df for _ in 1:reps])[1:repeat_to, :]
        push!(log, "$(n0)행 패턴 순환 반복 -> $(nrow(df))행")
    end
    if "Time_Index" in names(df)
        df[!, "Time_Index"] = collect(1:nrow(df))
    end
    return df
end

"시도 비중 CSV (열1=시도명/코드, 열2=비중). 합이 1이 되도록 정규화."
function load_weights(path)
    p = String(path)
    isfile(p) || throw(DownscaleError("weights 파일을 찾을 수 없습니다: $(p)"))
    df = DataFrame(CSV.File(p))
    ncol(df) >= 2 || throw(DownscaleError("weights CSV 는 최소 2열(시도, 비중)이 필요합니다."))

    kc, vc = names(df)[1], names(df)[2]
    w = Dict{String,Float64}()
    for r in eachrow(df)
        code = to_code(r[kc])
        code === nothing && throw(DownscaleError(
            "weights 의 '$(r[kc])' 를 시도 코드로 해석할 수 없습니다."))
        w[code] = tonumber(r[vc])
    end
    miss = [p2 for p2 in PROVINCE_ORDER_OFFICIAL if !haskey(w, p2)]
    isempty(miss) || throw(DownscaleError("weights 에 누락된 시도: $(miss)"))

    s = sum(values(w))
    return Dict{String,Float64}(k => v / s for (k, v) in w)
end

# ----------------------------------------------------------------------------
# 5. family / tag 자동탐지
# ----------------------------------------------------------------------------

"""
    detect_families_tags(national)

'Demand_MW', 'Demand_MW_25', 'Demand_heat'
  -> families = ["Demand_MW", "Demand_heat"], tags = ["", "25", "30", "35"]
Demand_Zero 는 제외(그대로 통과).
"""
function detect_families_tags(national::DataFrame)
    cols = [c for c in names(national)
            if startswith(lowercase(c), "demand") && lowercase(c) != "demand_zero"]
    tags = String[]
    families = String[]
    for c in cols
        idx = findlast('_', c)
        has_tag = idx !== nothing && idx < lastindex(c) &&
                  all(isdigit, c[nextind(c, idx):end])
        t = has_tag ? String(c[nextind(c, idx):end]) : ""
        base = has_tag ? String(c[1:prevind(c, idx)]) : c
        t in tags || push!(tags, t)
        base in families || push!(families, base)
    end
    sort!(tags, by = x -> (x == "" ? 0 : 1, x))
    return families, tags
end

"national 에서 시간에 따라 변하지 않는 family (예: Demand_heat = 8700 상수)."
function detect_flat_families(national::DataFrame, families::Vector{String})
    return Set{String}(f for f in families
                       if f in names(national) && length(unique(national[!, f])) == 1)
end

"(출력이름, 소스컬럼, family). 소스가 없으면 base 컬럼으로 fallback."
function build_groups(national::DataFrame, families::Vector{String},
                      tags::Vector{String}, log::Vector{String})
    out = Tuple{String,String,String}[]
    for fam in families
        fam in names(national) || throw(DownscaleError(
            "national 파일에 '$(fam)' 컬럼 없음. 있는 컬럼: $(names(national))"))
        for tag in tags
            name = isempty(tag) ? fam : string(fam, "_", tag)
            src = name in names(national) ? name : fam
            src == name || push!(log, "'$(name)' 없음 -> '$(fam)' 값 재사용.")
            push!(out, (name, src, fam))
        end
    end
    return out
end

# ----------------------------------------------------------------------------
# 6. 시간축 정렬 (method 4)
# ----------------------------------------------------------------------------

function align_share(share::Matrix{Float64}, dt, n_target::Int, mode::AbstractString)
    mode in SHAPE_MODES || throw(DownscaleError("shape_mode 는 $(SHAPE_MODES) 중 하나여야 합니다."))
    n = size(share, 1)

    if mode == "hourly"
        n == n_target && return share
        throw(DownscaleError(
            "shape_mode='hourly' 인데 길이 불일치 (profile=$(n), national=$(n_target)).\n" *
            "  -> repeat_to=$(n) 로 national을 늘리거나 shape_mode=\"hour_of_day\" 를 쓰세요."))
    end

    period = mode == "hour_of_day" ? 24 : 168
    key = if dt !== nothing
        period == 24 ? hour.(dt) : (dayofweek.(dt) .- 1) .* 24 .+ hour.(dt)
    else
        collect(0:(n-1)) .% period
    end

    ncols = size(share, 2)
    acc = zeros(Float64, period, ncols)
    cnt = zeros(Int, period)
    for i in 1:n
        k = key[i] + 1
        for j in 1:ncols
            acc[k, j] += share[i, j]
        end
        cnt[k] += 1
    end
    for k in 1:period
        cnt[k] > 0 && (acc[k, :] ./= cnt[k])
    end
    # 빈 구간은 앞/뒤 값으로 채움
    for k in 2:period
        cnt[k] == 0 && (acc[k, :] .= acc[k-1, :])
    end
    for k in (period-1):-1:1
        (cnt[k] == 0 && sum(acc[k, :]) == 0) && (acc[k, :] .= acc[k+1, :])
    end
    acc ./= sum(acc, dims = 2)

    idx = (collect(0:(n_target-1)) .% period) .+ 1
    return acc[idx, :]
end

# ----------------------------------------------------------------------------
# 7. 핵심: downscale
# ----------------------------------------------------------------------------

struct DownscaleResult
    df::DataFrame
    method::String
    groups::Vector{Tuple{String,String,String}}
    order::Vector{String}
    families::Vector{String}
end

"""
    downscale(national, profile, method; kwargs...) -> DownscaleResult

national demand DataFrame 을 17개 시도로 분해한다.

키워드 인자
  weights            method 1 용 Dict{String,Float64}. nothing 이면 내장 인구 비중
  shape_mode         method 4 용. "hourly" | "hour_of_day" | "hour_of_week"
  families, tags     nothing 이면 자동탐지
  flat_families      nothing 이면 national 에서 상수인 family 자동
  province_order     출력 컬럼의 시도 순서
  decimals           반올림 자리수 (음수면 반올림 안 함)
  keep_national_cols 원본 national 컬럼 유지 여부
  log                로그를 쌓을 Vector{String}
"""
function downscale(national::DataFrame, profile::Profile, method = "4";
                   weights = nothing,
                   shape_mode::AbstractString = "hourly",
                   families = nothing,
                   tags = nothing,
                   flat_families = nothing,
                   province_order = nothing,
                   decimals::Int = 2,
                   keep_national_cols::Bool = true,
                   log::Vector{String} = String[])

    m = resolve_method(method)
    order = province_order === nothing ? PROVINCE_ORDER_NZK : Vector{String}(province_order)
    n_target = nrow(national)

    auto_f, auto_t = detect_families_tags(national)
    fams = families === nothing ? auto_f : Vector{String}(families)
    tgs = tags === nothing ? auto_t : Vector{String}(tags)
    flat = flat_families === nothing ? detect_flat_families(national, fams) :
           Set{String}(flat_families)

    push!(log, "families=$(fams)  tags=$(tgs)")
    isempty(flat) || push!(log, "flat families (상수 비중 적용) = $(sort(collect(flat)))")

    # --- 비중 ---------------------------------------------------------------
    local const_w::Dict{String,Float64}
    if m == "population"
        w = weights === nothing ? DEFAULT_POPULATION_WEIGHTS : Dict{String,Float64}(weights)
        s = sum(values(w))
        const_w = Dict{String,Float64}(k => v / s for (k, v) in w)
        push!(log, "시간불변 인구 비중 사용" * (weights === nothing ? " (내장 기본값)" : ""))
    else
        const_w = annual_weights(profile)
        push!(log, "프로파일 연간 전력량 비중 사용")
    end
    top5 = sort(collect(const_w), by = p -> -last(p))[1:min(5, length(const_w))]
    push!(log, "상위 5: " * join([@sprintf("%s %.2f%%", first(p), 100 * last(p)) for p in top5], ", "))

    # --- 시간 형상 -----------------------------------------------------------
    aligned = nothing
    prof_frac = nothing
    if m == "hourly-share"
        aligned = align_share(hourly_share(profile), profile.datetime, n_target, shape_mode)
    elseif m == "regional-shape"
        nrows(profile) == n_target || throw(DownscaleError(
            "method 3: 프로파일 길이($(nrows(profile))) != 출력 길이($(n_target)). " *
            "repeat_to=$(nrows(profile)) 로 맞추세요."))
        prof_frac = profile.values ./ sum(profile.values)   # 전체 합 = 1
    end

    groups = build_groups(national, fams, tgs, log)

    # --- 곱셈 ---------------------------------------------------------------
    out = keep_national_cols ? copy(national) : DataFrame()
    if !keep_national_cols && "Time_Index" in names(national)
        out[!, "Time_Index"] = national[!, "Time_Index"]
    end

    for fam in fams
        items = [(nm, src) for (nm, src, f) in groups if f == fam]
        isflat = fam in flat
        for code in order                        # province-major
            pidx = PROV_INDEX[code]
            for (nm, src) in items               # year-minor
                v = Float64.(national[!, src])
                vals = if isflat || m == "population" || m == "national-shape"
                    v .* const_w[code]
                elseif m == "hourly-share"
                    v .* view(aligned, :, pidx)
                else                             # regional-shape
                    sum(v) .* view(prof_frac, :, pidx)
                end
                decimals >= 0 && (vals = round.(vals, digits = decimals))
                out[!, string(nm, "_", code)] = collect(vals)
            end
        end
    end

    return DownscaleResult(out, m, groups, order, fams)
end

# ----------------------------------------------------------------------------
# 8. 검증 리포트
# ----------------------------------------------------------------------------

"""
    validate(res, national; tol=1e-4)

연간 총량 / 시각별 합계 / 시도별 부하율 점검.
`(ok, hourly_gap_mw, load_factors, lines)` NamedTuple 반환.
"""
function validate(res::DownscaleResult, national::DataFrame; tol::Float64 = 1e-4)
    out = res.df
    lines = String[]
    ok = true

    push!(lines, "연간 총량 검증")
    for (nm, src, _) in res.groups
        tp = 0.0
        for c in res.order
            tp += sum(out[!, string(nm, "_", c)])
        end
        tn = sum(Float64.(national[!, src]))
        err = abs(tp - tn) / max(abs(tn), 1e-9)
        err < tol || (ok = false)
        push!(lines, "  " * (err < tol ? "OK " : "!! ") * rpad(nm, 18) *
                     " national=" * lpad(commafmt(tn), 16) *
                     "  provincial=" * lpad(commafmt(tp), 16) *
                     "  오차=" * @sprintf("%.2e", err))
    end

    gap = nothing
    lf = Dict{String,Float64}()
    if !isempty(res.families)
        fam0 = res.families[1]
        s = zeros(Float64, nrow(out))
        for c in res.order
            s .+= out[!, string(fam0, "_", c)]
        end
        gap = maximum(abs.(s .- Float64.(national[!, fam0])))
        note = res.method == "regional-shape" ? "   <- method 3 은 시각별 일치를 보장하지 않습니다" : ""
        push!(lines, "  시각별 합계 최대 편차 ($(fam0)): $(commafmt(gap)) MW" * note)

        push!(lines, "시도별 부하율 (mean/peak, $(fam0))")
        parts = String[]
        for c in res.order
            col = out[!, string(fam0, "_", c)]
            v = mean(col) / maximum(col)
            lf[c] = v
            push!(parts, @sprintf("%s %.0f%%", c, 100 * v))
        end
        push!(lines, "  " * join(parts, ", "))
    end

    return (ok = ok, hourly_gap_mw = gap, load_factors = lf, lines = lines)
end

end # module
