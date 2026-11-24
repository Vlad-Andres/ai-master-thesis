sequenceDiagram
    autonumber
    actor R as Researcher
    participant AL as AL loop
    participant G as Candidate generator
    participant M as Surrogate model
    participant A as Acquisition function
    participant O as Oracle wrapper<br/>evaluate(seq, target)
    participant S as Simulator<br/>run.sh + grancan/hblattice
    participant D as Dataset

    R->>AL: config (target, peptide length, T, steps, batch size, budget)

    Note over AL,D: Initialisation
    AL->>G: getInitialRandomBatch
    G-->>AL: initial batch 
    loop each sequence in initial batch
        AL->>O: evaluate(seq, target)
        O->>O: build PDB (target + peptide on lattice)
        O->>S: run.sh SIM PDB (SEED, STEPS, ROUNDS, T)
        S->>S: MC simulation
        S-->>O: run folder (stats_N0.tab, statsTable0.txt, result.json)
        O->>O: P_apart = P(Cext=0), P_bound = P(Cext>0)
        O->>O: ΔF = -T ln(P_bound / P_apart)
        O-->>AL: ΔF, uncertainty, cost (steps)
        AL->>D: store (seq, ΔF, uncertainty)
    end

    Note over AL,D: Active learning iterations
    loop until budget spent or ΔF converged
        AL->>M: train on dataset
        D-->>M: (seq, ΔF) pairs
        AL->>G: propose candidates (mutations of best seqs)
        G->>G: apply diversity / composition constraint
        G-->>AL: candidate pool (e.g. 10,000 seqs)
        AL->>M: predict ΔF + uncertainty for pool
        M-->>AL: predictions
        AL->>A: score pool (e.g. EI, UCB, Thompson)
        A-->>AL: top-k batch to simulate
        loop each sequence in batch (parallel runs)
            AL->>O: evaluate(seq, target)
            O->>S: run.sh (one or more seeds)
            S-->>O: stats_N0.tab per run
            alt both bound and apart states visited
                O-->>AL: ΔF, uncertainty, cost
            else P_apart = 0 or P_bound = 0
                O-->>AL: invalid run (retry longer / other T)
            end
            AL->>D: store result
        end
        AL->>AL: track best ΔF vs simulations used
    end

    AL-->>R: best sequences, ΔF curve, sample-efficiency metrics