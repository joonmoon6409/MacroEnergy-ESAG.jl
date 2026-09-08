#!/usr/bin/env bash
# Reproduce the bidirectional ITL transmission file from scratch.
# Requires: python3 with numpy, scipy, (pandas not needed).
set -euo pipefail
cd "$(dirname "$0")"

echo ">>> [0/2] sanity-check the ITL solver against the paper's 5-bus test"
python3 compute_itl.py --validate

echo ">>> [1/2] compute province interface transfer limits  (~15-20 min)"
python3 -u compute_itl.py inputs/gist_data_newest | tee outputs/itl_run.log

echo ">>> [2/2] build transmission asset CSVs from the ITLs"
python3 build_transmission_ITL.py

echo
echo "done.  Main output: outputs/transmission_v2_2021_ITL_bidir.csv"
