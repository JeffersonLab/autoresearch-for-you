# Autoresearch task — optimize the SRO EVIO processing chain

This file is the complete task definition. It has three parts: the environment
you run in, the rules for how you work, and the optimization task itself.

## End goal

End goal of this program (NOT only this run): ready software for a streaming
readout test stand optimized for high throughput for readout / processing /
output. This run covers one concrete step: maximize the throughput of the
existing filtered chain.

## Environment

- You are running in a docker container in autonomous mode.
- Mounts and folders:
  - This repository is mounted at /work.
  - Source code: /work/jana4ml4fpga — a JANA2-based project, stripped to this
    chain: the plugin `evio6_file` (src/plugins/evio6_file), the decode library
    `evio_sro_parser` (src/libraries/evio_sro_parser), a log service and the
    CLI. Component and parameter reference: /work/jana4ml4fpga/README.md.
  - /work/space/ is your workspace: notes, scripts, plots, analyses and
    anything else that does not belong in the source tree. It does not exist
    yet — create it on first run.
  - Bulky outputs and the writable data store go to /data/autoresearch/
    (build trees, .root outputs, caches).
  - Input data: /data/sro_boyarinov_data_2026/sro_000791.evio.00000
- Permissions:
  - You commit to this repository following the Git section below. Never push.
  - You can't try to access the host system.
  - You use **uv** for python and can install/add packages via uv — choose
    libraries yourself as needed (do NOT use typer; plain argparse is fine).
  - If you need system libraries, install them, but write down what needs to be
    installed for future runs.
- Check the core count (`nproc`) and use it (parallel jobs), keep ~2 cores
  headroom.

## The chain you optimize

The chain works and is validated; it is deliberately unoptimized (naive
single-thread reader, eager parsing, serial writer). It reads SRO evio6 files,
unfolds ~65 µs time-slice frames (1 evio block = 1 timeslice, 1 frame = 1
event), selects event frames with the coincidence finder, and writes the
selected ~4.3% to RNTuples (`frames` / `fadc_hits` / `dcrb_hits` tables keyed
on frame_number).

Build — ROOT is preinstalled in the container; JANA2, spdlog and fmt are
fetched and built by CMake when not found:

```bash
cmake -S /work/jana4ml4fpga -B /data/autoresearch/build \
      -DCMAKE_INSTALL_PREFIX=/data/autoresearch/install
cmake --build /data/autoresearch/build -j $(nproc)
cmake --install /data/autoresearch/build
```

Run — the filtered chain on N blocks:

```bash
export LD_LIBRARY_PATH=/data/autoresearch/install/lib:$LD_LIBRARY_PATH
export JANA_PLUGIN_PATH=/data/autoresearch/install/plugins
/data/autoresearch/install/bin/jana4ml4fpga -Pplugins=evio6_file \
  -Pnthreads=1 -Pjana:nevents=<blocks> \
  -Pevio6_file:finder=coincidence \
  -Pevio6_file:finder_bin_ticks=8 \
  -Pevio6_file:finder_min_hits_in_bin=6 \
  -Pevio6_file:finder_hot_channels=/work/config/hot_channels.csv \
  -Pevio6_file:output_file=<out.root> \
  /data/sro_boyarinov_data_2026/sro_000791.evio.00000
```

If cmake found a preinstalled JANA2 (the eic images ship one), add its lib
directory to LD_LIBRARY_PATH as well.

## How you work

- On start: if /work/space/notes/STATUS.md exists, read it and resume from
  where the last run stopped instead of restarting. Keep STATUS.md under ~40
  lines; it is the single resume entrypoint.
- When you create code, make it easy for humans to use and maintain; anywhere
  someone starts reading, the context should be quickly clear.
- When you have enough information to act, act. Do not re-litigate decisions
  already made. If weighing a choice, pick and record a recommendation, not a
  survey.
- Store one lesson per file in space/notes/ with a one-line summary at the
  top; update rather than duplicate; delete notes that turn out wrong.
- Put plots in space/plots/ and write results up in space/reports/.
  Previous results, plots and knowledge must persist as you progress.
- Record any new assumption as a config knob in space/notes/DECISIONS.md so it
  is cheap to change later. Tie decisions to evidence and measured numbers.
- You are operating autonomously; the user cannot answer questions mid-task.
  For reversible actions that follow from this document, proceed. Stop and ask
  only if (a) the task is impossible as specified, (b) proceeding would break a
  permission, (c) an action is irreversible/costly. Write questions to
  space/QUESTIONS.md, update STATUS.md, then stop.
- Token thrift: you run on a limited LLM budget, so be economical with your own
  effort — compute is cheap, your tokens are not:
  - Never load raw data into your context. Write scripts that print small
    samples, stats, and summaries; read those instead.
  - Redirect ALL build and run stdout/stderr to log files; inspect them only
    via tail/grep.
  - Run long jobs detached (nohup, background) and poll their logs; never block
    a tool call on a long run. Loop over parameters INSIDE scripts, never one
    tool call per point.
  - Prefer one well-prepared production over many chatty iterations. CPU hours
    cost nothing from your budget; thinking loops and subagents do.
  - Validate from printed numbers (counts, hashes, MB/s), not by viewing plot
    images; look at a rendered plot at most once per milestone.
  - Do not re-read files you just wrote; re-read only the region you are
    editing.
  - Milestone-first: Step 0 below (build + baseline + harness + correctness
    gate) DONE and recorded before any experiment. A finished measured
    experiment is worth more than three half-finished clever ones.
  - Before any open-ended search, state in your notes what improvement you
    expect and why. If you can't, put it in the report as "recommended next
    step" instead of doing it.
  - Assume you can be interrupted at any moment (rate limits): keep scripts,
    notes, and partial results on disk at all times so a future run resumes
    rather than restarts; update STATUS.md as you go.

## How you document

Applies to user-facing documents, texts and code+comments. For yourself you
write how it is better for your recall and understanding.

- Act as a technical writer following the Google Developer Documentation Style
  Guide.
- Eliminate excessive claims. Never use words that assume the user's skill
  level or the task's difficulty. Avoid words such as: simply, just, easily,
  easy, obvious, obviously, straightforward, trivial, painless, and basically.
- Eliminate ambiguous pronouns. Never use first person plural pronouns (we, us,
  our).
- Use direct address and imperative mood. Speak directly to the reader as
  "you" or give direct commands. Example: "Run the script" instead of "We will
  run the script".
- State the goal before the action. Example: "To start the server, run the
  command" instead of "Run the command to start the server".
- Omit unnecessary politeness. Do not use "please" or "kindly".
- Be objective and literal. Describe what the software does, not how the user
  should feel about it.
- Don't write code history, sentiments about code changes or prompt details in
  text. Any written text exists for a new human reader to understand the
  context in the minimal time.
- History or details may still exist if they help prevent a bug or warn of
  sketchy places. E.g. "Trying to optimize X will involve Y and will probably
  fail because of Z".
- Never leave pieces of prompt context and prompt jargon in comments.
  BAD: "As it said in optimize.md ...".
- A comment earns its place by saying something the code can't: the rationale,
  the constraint, the non-obvious consequence. E.g. "Push() is called while
  holding the JExecutionEngine mutex … keep it cheap" — not "// loop over
  outputs".
- Lead a non-trivial block with a short intent line, then the mechanism. Name
  the trap or the gotcha explicitly.

## How you code

- You write for humans, so a human maintainer feels comfortable reading
  (minimal cognitive load) and editing the code.
- You don't follow 80-character line cut-offs. If it is easier to read in one
  long line — do it. If a function definition reads better with each argument
  on its own line — use it. Decide from a human reader's point of view.
- Don't use short obscure variable names like `ac3` or `bumdbx`, but also don't
  make them unnecessarily long like `my_variable_to_hold_data`. Keep balance.
- Any place in the code must satisfy: if a new reader reads only this place,
  the variable names and comments let them understand the context and what is
  going on.
- A lot of import nesting is bad. Import B from A which is imported from C
  from D makes humans follow the whole chain and open all files. One very long
  file with everything is bad too. Decide on balance.
- For a single loop `i` is OK; for nested loops indexes must help understand
  the context: `col_i, row_i` for tables, `cats_i, rats_i` for more complex
  cases. Decide on balance.
- For analysis scripts configuration use **OmegaConf + YAML** to organize where
  data lives and what goes in/out of each stage.

---

# The task — component optimization loop

## Goal

Maximize throughput (input MB/s) of the **filtered chain** on the fixed
workload, one measured experiment at a time, without changing what the chain
produces.

## Step 0 — baseline before any experiment (first milestone)

1. Build the chain and smoke-run 500 blocks single-thread with the locked
   finder settings (see the run recipe above). Expected on this input: 5500
   frames scanned, 235 frames selected, 2064003 fadc_hits and 6530147
   dcrb_hits written. If you see different counts, stop and debug before
   anything else.
2. Create the measurement harness: `space/scripts/run_perf.sh <label>
   "<notes>" ...` that runs the chain and appends one row to
   `space/perf/history.csv` (date, label, blocks, frames scanned, frames
   selected, wall seconds, scanned frames/s, input MB/s, threads, notes).
   Measure hot-cache: do one warmup read after touching large files.
3. Create the correctness gate: `space/scripts/verify_output.py` — given two
   chain output files, compare (a) the set of selected frame_numbers, (b)
   per-frame n_fadc/n_dcrb counts, (c) an order-insensitive hash over all hit
   rows. Generate the reference once from the unmodified code (500 blocks,
   filtered). Store the reference hash in the experiment ledger, not just on
   disk.
4. Measure your baseline: the 500-block quick run and one full-file
   confirmation run, single thread, recorded in history.csv. Then isolate
   components with diagnostic runs (reader only / parse+finder with null
   writer / full chain) to get your own load profile.

Reference numbers from the original run of this task on different hardware —
measure your own, expect different absolutes: full-file filtered chain
95.4 MB/s at 1 thread (163 s for the 15.5 GB file, 533 frames scanned/s);
load profile: parser+unfold 91%, file I/O 7%, RNTuple write 2%.

## The fixed workload (never varies inside the loop)

- Input: /data/sro_boyarinov_data_2026/sro_000791.evio.00000
  (quick runs: `-Pjana:nevents=500`; confirmation runs: full file).
- Finder locked: `finder=coincidence, finder_bin_ticks=8,
  finder_min_hits_in_bin=6,
  finder_hot_channels=/work/config/hot_channels.csv`.
  Do not retune physics in this phase.
- **Bypass (write-all) mode is excluded from the loop.** It must keep working
  as a diagnostic, but its performance is not a target and must not be
  reported.

## Correctness invariant (gate for every experiment)

Constrained input => output must be the same. An experiment whose output
differs from the reference (verify_output.py from Step 0) is REJECTED
regardless of speed — no exceptions, no "close enough".

## The loop — one hypothesis, one subsystem, one change

Subsystems: reader (file I/O), parser+unfold (incl. finder), RNTuple writer,
JANA topology/threading. For each experiment:

1. **Hypothesize in writing first** (space/notes/EXPERIMENTS.md): subsystem,
   the single change, expected gain with the reasoning from measured numbers.
   If the expected gain cannot be stated, do not run the experiment.
2. **Change one thing.** No drive-by refactors; unrelated cleanups are separate
   ledger entries.
3. **Measure** via `bash space/scripts/run_perf.sh <label> "<hypothesis ref>"
   ...` — 500 blocks, hot cache. Repeat once if the delta is under ~5%; note
   run-to-run variance.
4. **Gate**: verify_output.py against the reference. Fail => revert, record.
5. **Verdict** in EXPERIMENTS.md: accepted/rejected, measured delta, one-line
   why. Accepted => confirm on the full file, update the throughput progression
   plot and STATUS.md; re-run the component isolation runs after each accepted
   parser/writer change.
6. Work single-thread until single-thread gains dry up (two consecutive
   experiments on a subsystem < 5% => move on), then open the multithread
   track (nthreads > 1 is a new experiment series; scanned frames/s and MB/s
   are the metrics, thread count always recorded).

## Seed hypotheses (verify the reasoning against your own profile before running)

Priority follows the measured load (parser ~91% in the original profile):

- **Lazy parsing**: the finder needs only clean ECAL hits, but the parser
  unpacks everything — including DCRB bitmasks (~2.4 G hits/file, ~76% of
  parse output) for the ~95.7% of frames that get rejected. Parse ECAL first,
  run the finder, unpack the rest only for selected frames. Expected:
  several-fold parser gain.
- Per-hit cost: reserve() hit vectors from payload sizes; flatten translation
  lookups into one precomputed LUT[rocid][slot][channel]; avoid the per-block
  `new SroBlockData` (object pool or reuse).
- Parallel parse: move parsing from the source thread into the unfolder
  Preprocess (JANA parallelizes it across timeslices), nthreads sweep.
- Reader: mmap / larger read granularity — only after the parser is no longer
  >50% of the profile.
- Writer: buffered/parallel write — only if it reappears in the profile (it
  was 2%).

## Git

- Commit to this repository (never push): one commit per hypothesis, after its
  verdict is recorded.
- You decide on {experiment-name} (lowercase letters, digits, dashes). The
  commit message is `autoresearch/v{try_index}_{experiment-name}`.
- If git complains about a missing identity, set a repository-local
  user.name/user.email once and continue.

## Reporting

Keep the experiment ledger append-only and one entry per hypothesis. End of
run: space/reports/experiment_report.md with the waterfall of accepted gains
(baseline -> final MB/s), the final component profile, and the throughput
progression plot. A rejected-hypotheses section is as valuable as the wins —
record why each idea failed.
