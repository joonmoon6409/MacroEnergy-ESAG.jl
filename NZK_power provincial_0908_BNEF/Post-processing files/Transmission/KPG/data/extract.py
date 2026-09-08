
import os
import re
import pandas as pd

# -------------------------------------------------
# Configuration
# -------------------------------------------------

# Name of the MATPOWER case file
M_FILE_NAME = "KPG193_ver2_0.m"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
M_FILE = os.path.join(BASE_DIR, M_FILE_NAME)

# -------------------------------------------------
# Column headers for each MATPOWER structure
# -------------------------------------------------

HEADERS = {
    "mpc.bus": [
        "bus_i",
        "type",
        "Pd",
        "Qd",
        "Gs",
        "Bs",
        "area",
        "Vm",
        "Va",
        "baseKV",
        "zone",
        "Vmax",
        "Vmin",
    ],
    "mpc.gen": [
        "bus",
        "Pg",
        "Qg",
        "Qmax",
        "Qmin",
        "Vg",
        "mBase",
        "status",
        "Pmax",
        "Pmin",
        "Pc1",
        "Pc2",
        "Qc1min",
        "Qc1max",
        "Qc2min",
        "Qc2max",
        "ramp_agc",
        "ramp_10",
        "ramp_30",
        "ramp_q",
        "apf",
    ],
    "mpc.branch": [
        "fbus",
        "tbus",
        "r",
        "x",
        "b",
        "rateA",
        "rateB",
        "rateC",
        "ratio",
        "angle",
        "status",
        "angmin",
        "angmax",
        "Pf",
        "Qf",
        "Pt",
        "Qt",
    ],
    "mpc.gencost": [
        "model",
        "startup",
        "shutdown",
        "n",
        "c2_or_x1",
        "c1_or_y1",
        "c0_or_x2",
        "y2",
    ],
    "mpc.genthermal": [
        "type_thermal",
        "UT",
        "DT",
        "inistate",
        "initialpower",
        "ramp_up",
        "ramp_down",
        "startup_limit",
        "shutdown_limit",
        "startup1",
        "startup2",
        "startup3",
        "startupdelay1",
        "startupdelay2",
        "startupdelay3",
    ],
    "mpc.areas": [
        "area",
        "refbus",
    ],
    "mpc.dcline": [
        "fbus",
        "tbus",
        "status",
        "Pf",
        "Pt",
        "Qf",
        "Qt",
        "Vf",
        "Vt",
        "Pmin",
        "Pmax",
        "QminF",
        "QmaxF",
        "QminT",
        "QmaxT",
        "loss0",
        "loss1",
    ],
    "mpc.dclinecost": [
        "model",
        "startup",
        "shutdown",
        "n",
        "c2_or_x1",
        "c1_or_y1",
        "c0_or_x2",
        "y2",
    ],
}

OUTPUT_FILES = {
    "mpc.bus": "bus.csv",
    "mpc.gen": "gen.csv",
    "mpc.branch": "branch.csv",
    "mpc.gencost": "gencost.csv",
    "mpc.genthermal": "genthermal.csv",
    "mpc.areas": "areas.csv",
    "mpc.dcline": "dcline.csv",
    "mpc.dclinecost": "dclinecost.csv",
}


# -------------------------------------------------
# Extraction helpers
# -------------------------------------------------
def extract_matrix(text, matrix_name):
    """
    Extract a matrix from a MATPOWER .m file.

    Example:
        mpc.bus = [
            ...
        ];
    """
    pattern = rf"{re.escape(matrix_name)}\s*=\s*\[(.*?)\];"
    match = re.search(pattern, text, re.DOTALL)

    if match is None:
        return None

    matrix_text = match.group(1)
    rows = []

    for line in matrix_text.splitlines():
        # Remove MATLAB comments
        line = line.split("%")[0].strip()

        if not line:
            continue

        # Remove trailing semicolon and comma
        line = line.rstrip(";").rstrip(",").strip()

        if not line:
            continue

        values = re.split(r"\s+", line)
        rows.append(values)

    return rows


def make_headers(base_headers, row_width):
    """
    Use the provided headers when possible.
    If a matrix has more columns than expected, add extra_col_N headers.
    If it has fewer columns, trim the header list.
    """
    if row_width <= len(base_headers):
        return base_headers[:row_width]

    extra_headers = [
        f"extra_col_{i}"
        for i in range(len(base_headers) + 1, row_width + 1)
    ]
    return base_headers + extra_headers


def rows_to_dataframe(rows, headers):
    """Convert extracted rows into a DataFrame with safe headers."""
    if not rows:
        return pd.DataFrame(columns=headers)

    max_width = max(len(row) for row in rows)
    final_headers = make_headers(headers, max_width)

    padded_rows = [
        row + [pd.NA] * (max_width - len(row))
        for row in rows
    ]

    df = pd.DataFrame(padded_rows, columns=final_headers)

    # Convert numeric-looking values to numeric types.
    # Newer pandas versions no longer accept errors="ignore", so we try the
    # conversion and keep the original column only if conversion fails.
    for col in df.columns:
        try:
            converted_col = pd.to_numeric(df[col], errors="raise")
            df[col] = converted_col
        except (ValueError, TypeError):
            pass

    return df


def save_matrix(text, matlab_name, output_name, headers):
    rows = extract_matrix(text, matlab_name)

    if rows is None:
        print(f"{matlab_name} not found.")
        return None

    df = rows_to_dataframe(rows, headers)

    output_path = os.path.join(BASE_DIR, output_name)
    df.to_csv(output_path, index=False, encoding="utf-8-sig")

    print(f"Saved {output_name} from {matlab_name} ({len(df)} rows, {len(df.columns)} columns)")
    return df


def main():
    with open(M_FILE, "r", encoding="utf-8") as f:
        text = f.read()

    print(f"Reading MATPOWER file: {M_FILE}")
    print("Extracting matrices...\n")

    extracted = {}

    for matlab_name, output_name in OUTPUT_FILES.items():
        extracted[matlab_name] = save_matrix(
            text=text,
            matlab_name=matlab_name,
            output_name=output_name,
            headers=HEADERS[matlab_name],
        )

    print("\nExtraction complete.")
    print("Saved CSV files:")

    for matlab_name, output_name in OUTPUT_FILES.items():
        if extracted[matlab_name] is not None:
            print(f"- {output_name}")


if __name__ == "__main__":
    main()