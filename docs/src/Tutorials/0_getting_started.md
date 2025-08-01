# Tutorial 0: Getting Started with Macro

!!! note "Interactive Notebook"
    The interactive version of this tutorial can be found [here](https://github.com/macroenergy/MacroEnergyExamples.jl/blob/main/tutorials/tutorial_0_getting_started.ipynb).

This tutorial will guide you through the steps to install Macro, a solver, and all the necessary dependencies.

## Installing Macro
Before installing Macro, make sure you have the following requirements installed:

- **Julia**: you can download it [here](https://julialang.org/downloads/). 
- **Git**: you can download it [here](https://git-scm.com/downloads).
- (optional) **Jupyter Notebook**: you can install it using the following command:
```bash
pip install notebook
```

### Download Macro

Since Macro is a **public repository**, you can simply clone it using:
```bash
git clone https://github.com/macroenergy/MacroEnergy.jl.git
```

If you want to clone a specific branch, you can use:
```bash
git clone -b <branch-name> https://github.com/macroenergy/MacroEnergy.jl.git
```

### Installation steps
- **Navigate to the repository**:
```bash
cd MacroEnergy.jl
```
- **Install Macro and all the dependencies**:
```bash
julia --project=. -e "using Pkg; Pkg.instantiate(); Pkg.precompile()"
```

### Setting up Jupyter Notebook
Once Macro is installed, to enable Jupyter Notebook support, you can run the following command:
```bash
julia --project=. 
```
in the terminal. Then, you can install the IJulia package and install the Macro kernel with the following commands:
```julia
julia> ]
(MacroEnergy) pkg> add IJulia
julia> using IJulia; IJulia.installkernel("MacroEnergy", "--project=@.")
```
Once the kernel is installed, you can run Jupyter Notebook with one of the following commands:
```bash
jupyter lab
```
or 
```bash
jupyter notebook
```

## Testing the installation
To test the installation, you can run the following command:
```julia
using MacroEnergy
```
in a Jupyter Notebook cell or in a Julia terminal. If everything is set up correctly, you should see no errors and the package should load without any issues.
