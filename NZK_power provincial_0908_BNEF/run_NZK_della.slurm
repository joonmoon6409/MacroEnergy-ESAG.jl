#!/bin/bash
#SBATCH --job-name=NZK_0908
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=slurm-%j.out
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=hk6264@princeton.edu

# --- modules (check exact versions with `module avail julia` / `module avail gurobi`) ---
module purge
module load julia/1.10.4
module load gurobi/11.0.3

# --- paths ---
REPO="/scratch/gpfs/${USER}/MacroEnergy-ESAG.jl"
CASE="${REPO}/NZK_power provincial_0908_BNEF"

# keep Gurobi thread count == the cores Slurm gave us
export GRB_THREADS="${SLURM_CPUS_PER_TASK}"

cd "${CASE}"
julia --project="${REPO}" run_v1_BNEF.jl
