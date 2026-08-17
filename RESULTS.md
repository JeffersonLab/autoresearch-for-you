# Reference results — the original run (spoilers)

Read this after your own run. Knowing the winning moves changes what your
agent's performance means.

## Setup

- Date: 2026-07-25, one working day including the baseline setup.
- Agent: Claude Code (model `claude-fable-5`), fully autonomous
  (`--dangerously-skip-permissions`), running from the same `optimize.md`
  protocol as this repository (the original had the workspace of the
  construction phase available; this repository starts one step earlier —
  your agent builds its own baseline and harness first).
- Machine: 20 cores, NVMe SSD measuring 4.4 GB/s O_DIRECT sequential read,
  3.0 GB/s cold buffered read.
- Workload: the same fixed workload as `optimize.md` — full 15.5 GB
  `sro_000791.evio.00000`, locked coincidence finder, ~4.3% frames selected.

## Waterfall of accepted experiments (full-file MB/s)

| # | change | MB/s | wall |
|---|--------|-----:|-----:|
| baseline | eager parse, serial writer, 1 thread | 95 | 163 s |
| v1 lazy-parse | decode only ECAL up front; defer non-ECAL ROC banks, decode per selected frame | 343 | 45 s |
| v2 writer-compression | expose `evio6_file:compression`; zstd-1 | 417 | 37 s |
| v4 pipeline-overlap | nthreads=4, no code change: writer tap overlaps source | 580 | 27 s |
| v5 parallel-writer | RNTupleParallelWriter, per-thread fill contexts | 1658 | 9.4 s |
| v6 parallel-parse | lazy parse moved to unfolder Preprocess (parallel map arrow) | 1752 | 8.9 s |
| v7 parallel-deferred-decode | decode in the consuming processor (parallel); Unfold = finder only | 2412 | 6.4 s |
| v8 mmap-reader | zero-copy mapped input; blocks pin the mapping via shared_ptr | 4206 hot / 2983 cold | 3.7 / 5.2 s |

Final: **31× (cold cache) / 44× (hot cache)** over the 95.4 MB/s baseline.
Cold runs end I/O-bound — identical to a cold `dd` of the same file (100% of
the kernel buffered-read path, 68% of the O_DIRECT ceiling). Hot runs end
compute-bound at 20 threads, at 96% of the O_DIRECT read ceiling.

## The rejected hypothesis worth knowing about

**v3 mmap-reader (first attempt): no gain.** Profiling attributed ~0.7 s to
"I/O", but most of that was process startup (JANA + ROOT dlopen); hot-cache
`fread` of 500 blocks costs ~0.03 s. The experiment was rejected and the
methodology fixed. The same code, resurrected as v8 after v5–v7 made the
reader the true bottleneck, became the biggest single win. A rejected change
can be right later — the premise, not the code, was wrong.

## Correctness

Every experiment was gated: selected frame set, per-frame hit counts, and an
order-insensitive hash over all hit rows — identical to the reference at every
accepted step (500-block gate: 235 frames, 2 064 003 fadc hits, 6 530 147
dcrb hits; full file: 3890 frames).

## Compare your run

Hardware differs; compare the speedup ratio over your own measured baseline,
not absolute MB/s, and check where your chain ended: I/O-bound (cold `dd`
speed) or compute-bound (cores saturated). Reaching the disk's buffered-read
ceiling with identical output is a complete result regardless of the absolute
number.

## Slides

Talk about this experiment: link TBD.
