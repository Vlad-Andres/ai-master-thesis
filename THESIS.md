# Active Learning for High-Affinity Peptide Sequence Design Using Stochastic Binding Simulations

### Abstract:
This thesis explores how active learning can accelerate the design of peptide sequences with high binding affinity while minimizing the number of simulated experiments required. A stochastic binding simulation model, based on a Monte Carlo method, will be used as a mechanistic surrogate for laboratory binding experiments. The simulator generates synthetic binding data by evaluating the effect of sequence mutations of different lengths and motifs on an input peptide, returning an estimated binding energy (ΔG) for each candidate sequence. The active learning framework trains a predictive model to estimate the binding energy (ΔG) of a peptide from its amino acid sequence. The model then iteratively proposes new sequence candidates whose predicted binding strength makes them the most informative candidates to evaluate further. These candidates are then evaluated by the simulation model, and the resulting binding energies are used to update the predictive model before the next iteration. The main objective is to identify which machine learning strategy, model configuration, active learning approach, and simulation model inference parameters (including frequency and batch size) can yield peptide sequences with lower binding energies (higher binding affinity) in the fewest simulation steps. Different strategies will be compared in terms of convergence speed, sample efficiency, and the quality of the sequences they discover to determine the most effective approach for simulation-guided peptide design.

## Simulator place in the design
###  Oracle: Simulator is a function that has input: peptide seq. -> noisy binding-energy estimate. 

```sh
evaluate(sequence, target, fidelity) → ΔG, uncertainty, cost
```

> **peptide binding affinity** - we need [a target, designable peptide to mutate]
- target: the sequence we want to be able to bind
- designed sequence: iteratively mutated one to improve the binding to the target

The free energy of a state $x$ is

$$
F(x) = -k_B T \ln P(x)
$$
where $P(x)$ is the number of times a state has been visited / total nr of steps

```
Cext - contacts between different chains (external)

target:   T1 T2 T3 T4 T5
          |  |  |
peptide:  P1 P2 P3        ← Cext = 3
```
___
### Algorithm:
1. Get P(x) for each state during the simulation phase, x - # of contacts
$$
   P(x) = \frac{count(x)}{count_{\text{total}}}
$$

   > where $count(x)$ is the number of steps spent in state $x$ and
   >$count_{\text{total}}$ the total number of steps.

   | Quantity | Simulator output | Set in the code |
   |---|---|---|
   | $x$ | column 1 of `stats_N<rank>.tab` | `Stats::Cext`, contacts between chains (`Stats.cpp`) |
   | $N(x)$ | column 2 of `stats_N<rank>.tab` | added every step by `EnergyMap::mapStats`, written by `GranCan::getMCStats` |


2. Group into unbound ($x = 0$) and bound ($x \neq 0$), and sum
   the probabilities in each group:
$$
   P_{\text{unbound}} = P(0), \qquad
   P_{\text{bound}} = \sum_{x \neq 0} P(x)
$$
3. **Compute the binding free energy:**

   $$
   \Delta F = F_{\text{bound}} - F_{\text{unbound}}
            = -k_B T \ln \frac{P_{\text{bound}}}{P_{\text{unbound}}}
   $$

>   A more negative $\Delta F$ means a stronger binder.

   | Quantity | Simulator output | Set in the code |
   |---|---|---|
   | $T$ | `BETA` line of the block: $T = 1/\text{BETA}$ (also `temperature` in `result.json`) | `-minT`/`-maxT` flags, converted in `App.cpp` |
   | $k_B$ | — | $1$ (reduced units) |
___