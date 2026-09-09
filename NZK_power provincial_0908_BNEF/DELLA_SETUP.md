# Running this case on Princeton Della

The code lives on GitHub (`joonmoon6409/MacroEnergy-ESAG.jl`, branch `NZK_Della`).
You do **not** push to the cluster — you clone from GitHub onto Della, then
keep both machines in sync through the branch (`git pull` / `git push`).

## 1. Get the repo onto Della

```bash
ssh hk6264@della.princeton.edu

cd /scratch/gpfs/$USER                      # scratch = big, fast, not backed up
git clone https://github.com/joonmoon6409/MacroEnergy-ESAG.jl.git
cd MacroEnergy-ESAG.jl
git checkout NZK_Della
```

If the clone asks for a password: use a **GitHub PAT** (classic, `repo` scope) as
the password, or set up an SSH deploy key. A public repo needs no auth.

## 2. Julia + package environment (one-time)

```bash
module avail julia                          # pick an available 1.10.x
salloc -c 8 --mem 32G -t 1:00:00            # short interactive job for precompile
module load julia/1.10.4
cd /scratch/gpfs/$USER/MacroEnergy-ESAG.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
exit
```

`Manifest.toml` is git-ignored, so `instantiate` re-resolves the environment on
Della. The repo root **is** the `MacroEnergy` package, so `--project=<repo root>`
is what provides `using MacroEnergy`.

## 3. Gurobi (one-time build against the cluster license)

```bash
module avail gurobi
module load gurobi/11.0.3                    # sets GUROBI_HOME + GRB_LICENSE_FILE
julia --project=. -e 'using Pkg; Pkg.build("Gurobi")'
```

## 4. Submit the run

`run_NZK_della.slurm` is in this case folder. Edit the `module load` versions to
match what `module avail` shows, then:

```bash
cd "/scratch/gpfs/$USER/MacroEnergy-ESAG.jl/NZK_power provincial_0908_BNEF"
sbatch run_NZK_della.slurm
squeue -u $USER                              # watch the job
tail -f slurm-<jobid>.out                    # watch progress
```

Notes:
- `run_v1_BNEF.jl` currently hard-codes Gurobi `"Threads" => 22`. Either set
  `#SBATCH --cpus-per-task` to 22, or change that line in `run_v1_BNEF.jl` to
  `"Threads" => parse(Int, get(ENV, "SLURM_CPUS_PER_TASK", "8"))`.
- Memory: local run peaked ~5 GB but the myopic 4-period build is heavier — 64 GB
  in the script is a safe start; drop it if it runs lean.
- Time: local run was still going at ~1.5 h. 12 h wall is a generous cap.
- Outputs (`results_*/`) land under the case folder on scratch. They are large
  (flows.csv ~0.5 GB/period) and git-ignored — pull them back with `rsync`/`scp`
  if needed, don't commit.

## 5. Keeping local and Della in sync

```bash
# made changes locally:
git add -A && git commit -m "..." && git push origin NZK_Della
# then on Della:
git pull origin NZK_Della

# made changes on Della: commit + push there, then `git pull` locally
```
