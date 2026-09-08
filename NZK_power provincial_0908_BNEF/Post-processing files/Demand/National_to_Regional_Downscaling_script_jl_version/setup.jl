#=
setup.jl  --  최초 1회만 실행

이 폴더를 독립 Julia 환경으로 만들고 필요한 패키지를 설치합니다.

    julia setup.jl

이후에는 항상 --project=. 로 실행하세요.

    julia --project=. main.jl

VS Code 를 쓰신다면, 이 폴더를 열고 하단 상태바의 Julia env 를 이 폴더로
바꾸면 --project 없이도 동작합니다.
=#

using Pkg

Pkg.activate(@__DIR__)
Pkg.add(["CSV", "DataFrames", "XLSX"])   # Dates, Printf, Statistics 는 stdlib
Pkg.instantiate()

println("\n설치 완료. 이제 다음으로 실행하세요:")
println("    julia --project=. main.jl --list-sheets")
println("    julia --project=. main.jl")
