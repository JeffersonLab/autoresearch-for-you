# Autoresearch task — optimize the SRO EVIO processing chain

This file is the complete task definition.

## End goal

End goal of this program (beyond this run): ready software for a streaming
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
  - `{space}` = **/work/space** — your workspace: QUESTIONS.md,
    notes/STATUS.md, and the notes, scripts, plots, analyses and anything
    else that does not belong in the source tree. Create it on first run. Every
    `{space}/...` path in this file means that directory; renaming the
    workspace changes this line and nothing else.
  - Bulky outputs and the writable data store go to /data/autoresearch/
    (build trees, .root outputs, caches).
  - Input data: /data/sro_boyarinov_data_2026/sro_000791.evio.00000
- Permissions:
  - You commit to this repository following the Git section below. Never push.
  - Do not access the host system.
  - You use **uv** for python and can install/add packages via uv — choose
    libraries yourself as needed (do NOT use typer; plain argparse is fine).
  - If you need system libraries, install them, but write down what needs to be
    installed for future runs.
- Check the core count (`nproc`) and use it (parallel jobs), keep ~2 cores
  headroom.

## The chain you optimize

The chain works and is validated; it is deliberately unoptimized
(single-thread reader, eager parsing, serial writer). It reads SRO evio6 files,
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

- On start: read {space}/notes/STATUS.md if it exists, then process
  {space}/QUESTIONS.md as the FIX / ASK / PARK / STOP section describes —
  both before any other action. Then resume from where the last run stopped
  instead of restarting. Keep STATUS.md under ~40 lines; it is the resume
  entrypoint. If QUESTIONS.md does not exist yet, there are no questions —
  continue.
- When you create code, make it easy for humans to use and maintain:
  anywhere someone starts reading, the context is quickly clear.
- When you have enough information to act, act. Do not re-litigate decisions
  already made. If weighing a choice, pick one and record the recommendation.
  This never overrides FIX / ASK / PARK / STOP: a doubt it routes to a
  question stays a question.
- Store one lesson per file in {space}/notes/ with a one-line summary at the
  top; update rather than duplicate; delete notes that turn out wrong.
- Put plots in {space}/plots/ and write results up in {space}/reports/.
  Previous results, plots and knowledge must persist as you progress.
- Record any new assumption as a config knob in {space}/notes/DECISIONS.md so it
  is cheap to change later. Tie decisions to evidence and measured numbers.
- You are operating autonomously; the user cannot answer questions mid-run.
  For reversible actions that follow from this document, proceed. When
  anything unexpected happens — or you catch yourself about to assume
  something the user could have specified — use the FIX / ASK / PARK /
  STOP protocol (next section). Never pursue a doubtful assumption
  silently.
- Write every question into {space}/QUESTIONS.md the moment it occurs to
  you. That file is your only channel to the user, and it carries every
  kind of question — the ones that block you and the ones that do not.
- Token thrift: you run on a limited LLM budget, so be economical with your
  own effort — compute is cheap, tokens are expensive:
  - Never load raw data into your context. Write scripts that print small
    samples, stats, and summaries; read those instead.
  - Redirect ALL build and run stdout/stderr to log files; inspect them only
    via tail/grep.
  - Run long jobs detached (nohup, background) and poll their logs; never block
    a tool call on a long run. Loop over parameters INSIDE scripts, never one
    tool call per point.
  - Prefer one well-prepared production over many small iterations. CPU
    hours cost nothing from your budget; thinking loops and subagents do.
  - Validate from printed numbers (counts, hashes, MB/s); look at a
    rendered plot at most once per milestone.
  - Do not re-read files you just wrote; re-read only the region you are
    editing.
  - Milestone-first: Step 0 below (build + baseline + harness + correctness
    gate) DONE and recorded before any experiment. A finished measured
    experiment is worth more than three half-finished ones.
  - Before any open-ended search, state in your notes what improvement you
    expect and why. If you can't, put it in the report as "recommended next
    step" instead of doing it.
  - Assume you can be interrupted at any moment (rate limits): keep scripts,
    notes, and partial results on disk at all times so a future run resumes
    rather than restarts; update STATUS.md as you go.

## When something unexpected happens — FIX, ASK, PARK, or STOP

- The user reads {space}/QUESTIONS.md between runs and answers inline. 
- User might explicitly say they are online and can answer interactrively
- If no explicit command from user is given, that file is your only channel 
to the user, so it carries every question you
have: what blocks you, what you would ask if the user sat beside you, and
what they should decide before the next phase. 
- Questions are a deliverable of this job! 
- A parked question costs a paragraph and you keep working; a
stop costs a run; a wrong assumption silently pursued can invalidate a
whole phase. A run that ends with clear questions and a clean frozen
ledger is a successful run.

Four responses cover everything:

- **FIX** — resolve it inside this run, no question. FIX applies only when
  the resolution is verified in this run: the build passes, the gate
  passes, the counts match. A fix that rests on an unverified
  interpretation is not a FIX — the interpretation is itself the question:
  PARK it.
- **ASK** — write a plain question, freeze nothing, keep working.
- **PARK** — write a `BLOCKING(!)` question, freeze its subject, keep
  working on something independent.
- **STOP** — write a `BLOCKING(!)` question, freeze everything, update
  STATUS.md, end the run.

A question is **BLOCKING(!)** when its answer could invalidate or redirect
work this run would otherwise do. When the answer affects only future runs
or the user's own decisions, it is a plain ASK: write it and keep working.
Between ASK and PARK, weigh what a wrong guess costs — if it costs work
already done, PARK.

The decision table routes what goes wrong. ASK also covers what the table
never sees: a preference the user could have stated, a question for an
upstream maintainer, a scope doubt about work you are not doing, a finding
that deserves a verdict. Routine engineering choices (naming, code
structure, library picks) are yours — never ask those.

**Absolute STOPs, regardless of the table below:** an action would destroy
something you cannot regenerate (the input file, the reference output, the
ledger, history.csv — overwriting your own build trees, outputs and caches
is routine and never triggers this); something would cost real money; the
task is impossible as specified; or proceeding would require breaking a
measurement rule of this file (the correctness gate, the locked finder, the
fixed workload). Proposing a change to a rule is not breaking it — that is a
PARK (see the table).

### Decision table — check top to bottom, first match wins

| you observe | response |
|---|---|
| two defensible readings of the task lead to different experiments or different numbers, and you are about to pick one | **PARK** the choice, with your intended reading as the recommendation. Routine engineering choices (naming, code structure, library picks) are yours — never park those. |
| the correctness gate fails on an experiment | **FIX**: re-run the gate with your change reverted. Reverted code passes → revert, record REJECTED with the measured delta. Reverted code also fails → the ruler is broken: two rows down. Never adjust the gate, the reference, or the workload to make an experiment pass — wanting to is the next row. |
| you want to change what the gate accepts, the reference output, the locked finder settings, or the definition of "correct" (the reference from Step 0 exists) | **PARK** the proposal with evidence; do NOT apply it. Continue only work that does not touch the disputed definition; if none exists, **STOP**. Mechanical repairs of verify_output.py that change no verdict (a crash fix) are the build-error row — after fixing, prove verdicts unchanged by verifying the stored reference against itself. Before the Step 0 reference exists, editing verify_output.py is normal Step 0 work. |
| the Step 0 counts (5500 scanned / 235 selected / 2064003 fadc_hits / 6530147 dcrb_hits) differ, or the stored reference no longer verifies against itself | during Step 0, before the baseline is recorded: **FIX** — debug the setup (build, parameters, input path). After the baseline is recorded: one clean rebuild and rerun with no code changes to rule out a stale environment; if the mismatch persists, **STOP** — the ruler is broken and nothing measured after this is valid. Throughput numbers and run-to-run variance are NOT this row. |
| a build error, tool error, or crash | **FIX**: debug it. Count attempts per blocked task, not per error message: if the task is still blocked after two distinct fix attempts, revert the working tree to the last state that built, then — evidence points at code you don't own → next row; the error sits in the build/verify/measure path itself → **STOP** (a broken ruler is not parkable); otherwise **PARK** this one experiment (question: drop it, or is there context I'm missing?). |
| a bug in code you don't own (JANA2, ROOT, the container) | write the question first; a minimal reproducer is good "continuing meanwhile" work (one script, at most; "not my code" is unverified until the reproducer fails with none of your changes in the loop). Chain builds, gate passes, metric unaffected → **ASK** and continue (question: file upstream? work around?). It blocks — or could skew — the baseline, the gate, or the measured metric → **STOP**. |
| a discovery that would change the SCOPE — the goal, the fixed workload, the locked finder, or the phase (e.g. "retuning the finder would beat any code change") | **PARK**: write the finding and the proposed re-scope. Do not add it to the backlog or EXPERIMENTS.md, and run no experiment on it. The written plan stays the plan until the user changes it — continue the next planned experiment that passes the freeze check. A new throughput hypothesis inside the current scope is not this row: that is the normal loop, just add it to the backlog. |
| a subsystem hits the move-on rule (loop step 6) | **FIX**: record the ceiling in the ledger and follow step 6. |
| the backlog is empty, every subsystem has a recorded ceiling, and the multithread series (loop step 6) is run and recorded | normal completion: write the final report (see Reporting), then sweep for questions — reread the ledger, notes and DECISIONS.md and **ASK** everything the user should decide or know before the next run. Set the first line of STATUS.md to `DONE — report at {space}/reports/experiment_report.md` and end the run. The end of a run is when questions matter most: the report says what happened, the questions say what the user must answer next. Finishing with an empty QUESTIONS.md is a defect, not a clean run. |

If no row matches: **PARK**. If no row matches and the doubt is about whether
your measurements are valid — you cannot tell whether the ruler is right —
**STOP**.

### ASK — the exact protocol

Append to {space}/QUESTIONS.md (N = highest Q number in the file + 1):

```markdown
## Q<N> <date> — <one-line question>
- Found: <what prompted it; measured numbers where they exist, otherwise the exact error text verbatim>
- Why it matters: <what could change depending on the answer>
- Options: A) <...> B) <...>. Recommendation: <letter + one line why>
- ANSWER:
```

A plain entry freezes nothing. Keep working — including on its subject,
following your recommendation. It needs no STATUS.md line; the entry is the
record. Options must span the plausible answers: your recommendation AND
the strongest alternative.

### PARK — the exact protocol

1. Append to {space}/QUESTIONS.md, `BLOCKING(!)` opening the question line
   (N = highest Q number in the file + 1):

   ```markdown
   ## Q<N> <date> — BLOCKING(!) <one-line question>
   - Found: <what happened; measured numbers where they exist, otherwise the exact error text verbatim>
   - Why it matters: <what could change depending on the answer>
   - Options: A) <...> B) <...>. Recommendation: <letter + one line why>
   - Frozen until answered: <subsystem names from the fixed list (reader / parser+unfold / writer / topology) and/or file paths>
   - Continuing meanwhile: <the item you switch to + one line why it touches nothing frozen>
   - ANSWER:
   ```

   Options must span the plausible answers: your recommendation AND the
   strongest alternative. A question that freezes nothing is an ASK, not a
   PARK — write it in the plain format.
2. The freeze names concrete items and lasts the whole run: before starting
   ANY experiment, check it against the Frozen lists of ALL open BLOCKING(!)
   questions — allowed only if it touches none of the named subsystems or
   files. Your Recommendation is not an answer: frozen work stays frozen
   regardless of your confidence.
3. Revert the working tree to the last commit before switching (one commit
   per hypothesis stays clean). If the in-progress diff is evidence for the
   question, save it under {space}/notes/ and reference it from the entry.
4. Switch to the next backlog item that passes the freeze check in step 2.
   If none exists, STOP.
5. Add one line to STATUS.md: `Q<N> parked; continuing with <item>`.

### STOP — the exact protocol

For question-driven stops: write the BLOCKING(!) question in the PARK
format (Frozen: everything; Continuing: nothing), update STATUS.md so the
next run resumes from the answer, end the run. Normal completion (table
above) writes the final report and its ASK sweep instead. Stopping with a
written question is a good outcome.

### Processing QUESTIONS.md on run start

The set of active freezes is exactly the `Frozen until answered:` lines of
`BLOCKING(!)` entries without `[closed]` in their header — nothing else.
Plain entries never freeze anything. For each entry:

- ANSWER filled and decisive → apply it, append `[closed <date>]` to the
  header; for a BLOCKING(!) entry also rewrite its Frozen line to
  `Frozen: none [unfrozen <date>]`.
- ANSWER filled but conditional or unclear → do NOT unfreeze. Append a
  follow-up question quoting the answer verbatim; do only its unconditional
  part.
- ANSWER empty on a plain entry → it stays open and blocks nothing. Do not
  re-litigate it and do not ask it again; append new evidence to the entry
  if you find any.
- ANSWER empty on a BLOCKING(!) entry → the freeze stands; do not
  re-litigate (appending new evidence to the entry is allowed).
- A BLOCKING(!) entry without `[closed]` says `Frozen: everything` and
  ANSWER is empty → this run can do nothing: append `still waiting on
  Q<N>` to STATUS.md and end the run. Do not work around the freeze or
  reinterpret the question.

## How you document

Applies to user-facing documents, texts and code+comments. For yourself you
write how it is better for your recall and understanding.

- Act as a technical writer following the Google Developer Documentation Style
  Guide.
- Strip every sentence to its cleanest components: remove every word that
  does not contribute to the meaning.
- Eliminate clutter: avoid redundancies ("completely finished" → "finished").
- Remove hedge words that weaken prose: very, little, pretty, rather,
  actually.
- Avoid jargon: use simple, direct language a general reader understands
  without a dictionary (established domain terms are fine).
- Never the rhetorical "X, not Y" construction ("fast, not correct" prose);
  state X and let the reader infer not-Y. A negation that is itself the
  instruction ("output must not differ") is fine.
- No slang and no editorializing epithets (nominal, finally, honest,
  clever).
- Use the em dash (—) for any dash in text, ranges included.
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
- Be objective and literal: describe what the software does.
- Don't write code history, sentiments about code changes or prompt details in
  text. Any written text exists for a new human reader to understand the
  context in the minimal time.
- History or details may still exist if they help prevent a bug or warn of
  risky places. E.g. "Trying to optimize X will involve Y and will probably
  fail because of Z".
- Never leave pieces of prompt context and prompt jargon in comments.
  BAD: "As it said in optimize.md ...".
- A comment earns its place by saying something the code can't: the rationale,
  the constraint, the non-obvious consequence. E.g. "Push() is called while
  holding the JExecutionEngine mutex … keep it cheap". BAD: "// loop over
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
   dcrb_hits written. If you see different counts, debug your setup (build,
   parameters, input path) before anything else; if they still differ with
   the recipe followed exactly, STOP per the FIX / ASK / PARK / STOP table.
2. Create the measurement harness: `{space}/scripts/run_perf.sh <label>
   "<notes>" ...` that runs the chain and appends one row to
   `{space}/perf/history.csv` (date, label, blocks, frames scanned, frames
   selected, wall seconds, scanned frames/s, input MB/s, threads, notes).
   Measure hot-cache: do one warmup read after touching large files.
3. Create the correctness gate: `{space}/scripts/verify_output.py` — given two
   chain output files, compare (a) the set of selected frame_numbers, (b)
   per-frame n_fadc/n_dcrb counts, (c) an order-insensitive hash over all hit
   rows. Generate the reference once from the unmodified code (500 blocks,
   filtered). Store the reference hash in the experiment ledger as well as on
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
regardless of speed — no exceptions.

## The loop — one hypothesis, one subsystem, one change

Subsystems only: reader (file I/O), parser+unfold (incl. finder), RNTuple writer,
JANA topology/threading. For each experiment:

1. **Hypothesize in writing first** in {space}/notes/EXPERIMENTS.md — the
   experiment ledger; it also holds the ordered backlog of not-yet-run
   hypotheses, seeded from Seed hypotheses below. Each entry: subsystem,
   the single change, expected gain with the reasoning from measured numbers.
   If the expected gain cannot be stated, do not run the experiment.
2. **Change one thing.** Unrelated cleanups are separate ledger entries.
3. **Measure** via `bash {space}/scripts/run_perf.sh <label> "<hypothesis ref>"
   ...` — 500 blocks, hot cache. Repeat once if the delta is under ~5%; note
   run-to-run variance.
4. **Gate**: verify_output.py against the reference. Fail => revert, record.
5. **Verdict** in EXPERIMENTS.md: accepted/rejected, measured delta, one-line
   why. Accepted => confirm on the full file, update the throughput progression
   plot and STATUS.md; re-run the component isolation runs after each accepted
   parser/writer change.
6. Work single-thread until the move-on rule fires (two consecutive
   experiments on a subsystem each ending < 5% or REJECTED => record the
   ceiling, move on), then open the multithread
   track (nthreads > 1 is a new experiment series; scanned frames/s and MB/s
   are the metrics, thread count always recorded).

## Seed hypotheses (verify the reasoning against your own profile before running)

Priority follows the measured load (parser ~91% in the original profile):

- **Lazy parsing**: the finder needs only clean ECAL hits, but the parser
  unpacks everything for the ~95.7% of frames that get rejected. Parse ECAL first,
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
run: {space}/reports/experiment_report.md with the waterfall of accepted gains
(baseline -> final MB/s), the final component profile, and the throughput
progression plot. Include a rejected-hypotheses section: record why each idea failed.
