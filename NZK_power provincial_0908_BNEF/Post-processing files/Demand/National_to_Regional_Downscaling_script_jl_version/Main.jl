#=
main.jl  --  NZK MACRO national -> provincial demand 변환 실행 스크립트

폴더 구조
    ./Input_data/     입력 파일 (national CSV, 지역 프로파일 xlsx, weights CSV)
    ./output_files/   출력 CSV
    Downscale.jl      변환 로직 (라이브러리)
    main.jl           이 파일 -- 설정 + 실행

사용법
    아래 CONFIG 를 수정한 뒤:
        julia main.jl

    또는 명령줄로 덮어쓰기:
        julia main.jl --method 3 --sheet "regional_hourly_load_profile_20"
        julia main.jl --list-sheets
        julia main.jl --methods 1,2,3,4    # 여러 방식 한 번에 비교 생성

    이 스크립트는 시작할 때 자기 폴더를 Julia 환경으로 활성화하고, 없는
    패키지는 자동으로 설치합니다. --project=. 를 붙이지 않아도, VS Code 의
    실행/디버그 버튼으로 돌려도 동작합니다.

    CONFIG 파일명은 Input_data/ 기준 상대경로로 해석됩니다 (절대경로도 가능).
=#

# ============================================================================
# 환경 부트스트랩  --  어떤 방식으로 실행하든 이 폴더의 Project.toml 을 쓴다
# ============================================================================

const ROOT = @__DIR__

using Pkg

if abspath(Base.active_project()) != abspath(joinpath(ROOT, "Project.toml"))
    @info "Julia 환경을 이 폴더로 전환합니다: $(ROOT)"
    Pkg.activate(ROOT)
end

let required = ["CSV", "DataFrames", "XLSX"]
    have = keys(Pkg.project().dependencies)
    lacking = [p for p in required if !(p in have)]
    if !isempty(lacking)
        @info "필요한 패키지를 설치합니다: $(lacking)  (최초 1회, 몇 분 걸릴 수 있습니다)"
        Pkg.add(lacking)
    end
end

include(joinpath(ROOT, "Downscale.jl"))

using .Downscale
using CSV
using DataFrames
using Printf

# ============================================================================
# CONFIG  --  여기만 고치면 됩니다
# ============================================================================

const INPUT_DIR = joinpath(ROOT, "Input_data")
const OUTPUT_DIR = joinpath(ROOT, "output_files")

const CONFIG = Dict{String,Any}(
    # --- 1) 입력 demand 파일 -------------------------------------------------
    "national_file" => "demand_national_8760.csv",

    # --- 2) 지역 프로파일 + 참조 탭 ------------------------------------------
    #     탭 목록은  julia main.jl --list-sheets  로 확인
    #     "provincial shape"                : 시각별 비율 (method 1/2/4 용)
    #     "regional_hourly_load_profile_20" : 실측 MW      (method 3 권장)
    #     "2025_ref" / "2030_NDC" 등        : 시나리오 탭 (MW, 자동 정규화)
    "profile_file" => "regional_hourly_load_profile_2024_analysis.xlsx",
    "profile_sheet" => "provincial shape",

    # --- 3) downscale 방식 ---------------------------------------------------
    #     1 population      P_p(t) = N(t) * w_p        (시간불변 인구 비중)
    #     2 national-shape  P_p(t) = N(t) * W_p        (national 형상 유지)
    #     3 regional-shape  P_p(t) = E_tot * R_p(t)/S  (연간 총량만 + 시도별 형상)
    #     4 hourly-share    P_p(t) = N(t) * s_p(t)     (매시각 비율)
    "method" => "4",

    # method 1 전용. nothing 이면 내장 인구 비중 사용.
    # CSV 예:  province,weight  /  Seoul,0.2044  /  ...
    "weights_file" => nothing,

    # method 4 전용. profile 과 national 길이가 다를 때의 매칭 방식.
    #   "hourly" | "hour_of_day" | "hour_of_week"
    "shape_mode" => "hourly",

    # --- 4) 시간축 ------------------------------------------------------------
    # national 을 이 길이까지 순환 반복 (336시간 대표패턴 -> 8760). nothing 이면 그대로.
    "repeat_to" => 8760,
    "drop_leap_day" => true,      # 프로파일이 8784행이면 2/29 제거

    # --- 5) 컬럼 --------------------------------------------------------------
    "families" => nothing,        # nothing = 자동탐지 (예: ["Demand_MW", "Demand_heat"])
    "tags" => nothing,            # nothing = 자동탐지 (예: ["", "25", "30", "35"])
    "flat_families" => nothing,   # nothing = national에서 상수인 family 자동 (Demand_heat 등)
    "province_order" => "nzk",    # "nzk" (기존 파일과 동일) | "official" (행정코드순)
    "keep_national_cols" => true,
    "decimals" => 2,

    # --- 6) 출력 --------------------------------------------------------------
    # nothing 이면  demand_provincial_m{method}_{행수}.csv  로 자동 생성
    "output_file" => nothing,
)

# ============================================================================

resolve_in(name) = name === nothing ? nothing :
                   (isabspath(String(name)) ? String(name) : joinpath(INPUT_DIR, String(name)))

resolve_out(name) = isabspath(String(name)) ? String(name) : joinpath(OUTPUT_DIR, String(name))

const FLAG_ARGS = Set(["--list-sheets", "--keep-leap-day", "--help", "-h"])

const VALUE_ARGS = Dict{String,String}(
    "--national" => "national_file",
    "--profile" => "profile_file",
    "--sheet" => "profile_sheet",
    "--method" => "method",
    "-m" => "method",
    "--weights" => "weights_file",
    "--shape-mode" => "shape_mode",
    "--repeat-to" => "repeat_to",
    "--province-order" => "province_order",
    "--decimals" => "decimals",
    "--output" => "output_file",
    "--methods" => "__methods",
)

function print_help()
    println("""
NZK MACRO: national demand -> 17개 시도 provincial demand

  julia main.jl [옵션]

옵션
  --national FILE       Input_data 내 national CSV 파일명
  --profile  FILE       Input_data 내 지역 프로파일 파일명
  --sheet    NAME       참조할 엑셀 탭 이름
  --method, -m  N       1|2|3|4 (또는 이름)
  --methods  1,2,3,4    여러 방식을 한 번에 실행
  --weights  FILE       method 1 용 비중 CSV 파일명
  --shape-mode MODE     hourly | hour_of_day | hour_of_week
  --repeat-to N         national 을 N행까지 순환 반복
  --keep-leap-day       프로파일의 2/29 를 유지
  --province-order X    nzk | official
  --decimals N          반올림 자리수 (음수면 반올림 안 함)
  --output FILE         출력 파일명 (output_files 기준)
  --list-sheets         프로파일 탭 목록 출력 후 종료

method""")
    for m in ["population", "national-shape", "regional-shape", "hourly-share"]
        println("  ", Downscale.METHOD_DESCRIPTIONS[m])
    end
end

function parse_cli(argv::Vector{String})
    opts = Dict{String,Any}()
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a in FLAG_ARGS
            opts[a] = true
            i += 1
        elseif haskey(VALUE_ARGS, a)
            i + 1 <= length(argv) || throw(DownscaleError("$(a) 에 값이 필요합니다."))
            opts[VALUE_ARGS[a]] = argv[i+1]
            i += 2
        else
            throw(DownscaleError("알 수 없는 옵션: $(a)  (--help 참고)"))
        end
    end
    return opts
end

function apply_overrides(cfg::Dict{String,Any}, opts::Dict{String,Any})
    c = copy(cfg)
    for (k, v) in opts
        startswith(k, "-") && continue          # 플래그
        k == "__methods" && continue
        if k == "repeat_to" || k == "decimals"
            c[k] = parse(Int, String(v))
        else
            c[k] = v
        end
    end
    get(opts, "--keep-leap-day", false) === true && (c["drop_leap_day"] = false)
    return c
end

"설정 하나로 변환 1회 실행. 출력 경로를 반환."
function run_one(cfg::Dict{String,Any})
    m = resolve_method(cfg["method"])
    println("=" ^ 78)
    println("method $(cfg["method"])  ->  $(Downscale.METHOD_DESCRIPTIONS[m])")
    println("=" ^ 78)

    log = String[]

    # --- 프로파일 먼저 (method 3 의 출력 길이 결정에 필요) ---------------------
    profile = load_profile(resolve_in(cfg["profile_file"]);
                           sheet = cfg["profile_sheet"],
                           drop_leap_day = cfg["drop_leap_day"],
                           need_absolute = (m == "regional-shape"),
                           log = log)

    repeat_to = cfg["repeat_to"]
    if m == "regional-shape" && (repeat_to === nothing || repeat_to != nrows(profile))
        repeat_to = nrows(profile)
        push!(log, "method 3 -> 출력 길이를 프로파일 길이 $(repeat_to) 로 맞춥니다.")
    end

    national = load_national(resolve_in(cfg["national_file"]);
                             repeat_to = repeat_to, log = log)

    weights = cfg["weights_file"] === nothing ? nothing :
              load_weights(resolve_in(cfg["weights_file"]))

    order = cfg["province_order"] == "nzk" ? PROVINCE_ORDER_NZK : PROVINCE_ORDER_OFFICIAL

    res = downscale(national, profile, cfg["method"];
                    weights = weights,
                    shape_mode = cfg["shape_mode"],
                    families = cfg["families"],
                    tags = cfg["tags"],
                    flat_families = cfg["flat_families"],
                    province_order = order,
                    decimals = cfg["decimals"],
                    keep_national_cols = cfg["keep_national_cols"],
                    log = log)

    for line in log
        println("  ", line)
    end

    report = validate(res, national)
    println()
    for line in report.lines
        println(line)
    end

    name = cfg["output_file"] === nothing ?
           "demand_provincial_m$(cfg["method"])_$(nrow(res.df)).csv" :
           String(cfg["output_file"])
    path = resolve_out(name)
    mkpath(dirname(path))
    CSV.write(path, res.df)

    shown = startswith(path, ROOT) ? relpath(path, ROOT) : path
    println("\n저장: $(shown)  ($(nrow(res.df))행 x $(ncol(res.df))열)")
    report.ok || println(stderr, "경고: 총량 오차가 허용범위를 넘습니다.")
    println()
    return path
end

function main(argv::Vector{String} = String[])
    local opts
    try
        opts = parse_cli(argv)
    catch err
        err isa DownscaleError || rethrow()
        println(stderr, "오류: $(err.msg)")
        return 1
    end

    if get(opts, "--help", false) === true || get(opts, "-h", false) === true
        print_help()
        return 0
    end

    cfg = apply_overrides(CONFIG, opts)
    mkpath(OUTPUT_DIR)
    if !isdir(INPUT_DIR)
        println(stderr, "오류: 입력 폴더가 없습니다 -> $(INPUT_DIR)")
        return 1
    end

    try
        if get(opts, "--list-sheets", false) === true
            path = resolve_in(cfg["profile_file"])
            println("$(basename(path)) 탭 목록:")
            for s in list_sheets(path)
                println("  - ", s)
            end
            return 0
        end

        methods = haskey(opts, "__methods") ?
                  String[strip(x) for x in split(String(opts["__methods"]), ",")] :
                  String[String(cfg["method"])]

        for mth in methods
            c = copy(cfg)
            c["method"] = mth
            length(methods) > 1 && (c["output_file"] = nothing)   # 방식별 파일명 분리
            run_one(c)
        end
    catch err
        err isa DownscaleError || rethrow()
        println(stderr, "\n오류: $(err.msg)")
        return 1
    end
    return 0
end

#=
자동 실행

  julia main.jl                 ARGS 를 읽어 실행하고 종료 코드를 반환한다.
  VS Code 실행/디버그 버튼      디버거가 include 하므로 PROGRAM_FILE 이 이 파일이
                                아니다. 이 경우 ARGS 는 디버거의 것이므로 무시하고
                                CONFIG 설정대로 실행한다.
  REPL 에서 include("main.jl")  마찬가지로 CONFIG 설정대로 1회 실행한다.

자동 실행을 끄고 main() 을 직접 부르고 싶다면 include 전에:
    ENV["NZK_NO_AUTORUN"] = "1"
=#

const IS_SCRIPT = abspath(PROGRAM_FILE) == @__FILE__

if get(ENV, "NZK_NO_AUTORUN", "0") != "1"
    status = main(IS_SCRIPT ? copy(ARGS) : String[])
    IS_SCRIPT && exit(status)
end