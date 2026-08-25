# The JANA2 dependency: pin, patches, and the unfolder bugs

This project's EVIO chain is a `JEventUnfolder` topology: `EvioSroBlockSource`
emits one Timeslice event per EVIO block holding the parsed `SroBlockData`, and
`SroFrameUnfolder` emits one PhysicsEvent per selected frame. Each child event
carries an `SroFrameRef`, which points into the parent's `SroBlockData` instead
of copying hit slices.

Two JANA2 defects used to break that topology. Both are fixed in JANA2
**v2026.03.01**, which is why `JANA2_VERSION` in
`cmake/fetch_dependencies.cmake` pins that release and must not be moved below it.
The project applies no JANA2 patches at present.

## Where the JANA2 in a build comes from

The build always uses the pinned revision, and never a JANA2 supplied by the
environment — including the one inside the EIC docker images. Correctness is one
reason: images still ship JANA2 builds older than v2026.03.01.
Reproducibility is the other: this project compares throughput across runs and
machines, so a JANA2 that arrives with an image would be an uncontrolled variable
that moves the baseline whenever the image is rebuilt.

Three mechanisms enforce this:

- `cmake/fetch_dependencies.cmake` fetches, patches, builds and installs JANA2
  into `<build>/deps/jana2` without consulting the environment, then resolves it
  with `NO_DEFAULT_PATH`.
- A stamp file, `<build>/deps/jana2/ml4-jana2-stamp.txt`, records the pinned
  revision and the MD5 of every patch. A configure whose stamp does not match
  wipes the source, build and install trees and starts over, so editing a patch or
  moving the pin cannot leave a stale copy in place. A matching stamp skips the
  work entirely, which also means a reconfigure needs no network.
- The installed binaries and plugins carry `DT_RPATH` (`$ORIGIN/../lib`), set in
  the top-level `CMakeLists.txt`. `DT_RPATH` is searched before
  `LD_LIBRARY_PATH`, so an image that puts its own `libJANA.so` on that variable
  cannot substitute it at run time. The modern `DT_RUNPATH` default loses that
  contest, hence the explicit `--disable-new-dtags`.

Two escape hatches exist, both for debugging and neither safe for measurements:
`ML4_USE_SYSTEM_JANA2=ON` links the environment's JANA2, and
`FETCH_DEPENDENCIES=OFF` skips this file altogether. Both warn at configure time.

To confirm which JANA2 an installed binary actually loads:

```bash
ldd <prefix>/bin/jana4ml4fpga | grep libJANA
```

## Why the pin cannot go below v2026.03.01

Both defects hit any `JEventUnfolder` topology whose children outlive the
unfolding of their parent, which is exactly this chain.

**Parent retention (use-after-free).** An unfolder hands its parent event back to
the pool as soon as it stops unfolding, which happens while children are still in
flight. `JArrow::Push` cleared the event on the way to the pool, and
`JEvent::Clear()` deletes every object the source inserted — including the
`SroBlockData` a live child's `SroFrameRef` points into. JANA2 tracked the child
refcount and already deferred *reuse* of such a parent, but the clear ran before
the pool consulted that refcount, so the deferral only protected the empty `JEvent`
shell. The symptom was a segfault on the first block, at "0 events processed",
before any output was written. Fixed upstream by commit `1e6b5c48e`, which moves
`Clear()` out of `JArrow::Push` into both of `JEventPool`'s reclaim paths:
`Ingest()` when the child count is zero, and `NotifyThatAllChildrenFinished()`
when the last child finishes.

**Pool depletion (hang).** `JUnfoldArrow::Fire` dropped the parent event when the
unfolder returned `KeepChildNextParent` and the parent already had children, so
the parent never returned to its pool, the Timeslice pool drained and the topology
hung. This chain reaches that case on every block whose trailing frames fail the
finder, which is most blocks. Fixed upstream by PR #514 (`b67216180`).

Confirm a candidate revision carries both before moving the pin:

```bash
git merge-base --is-ancestor 1e6b5c48e <revision> && echo "parent retention: ok"
git merge-base --is-ancestor b67216180 <revision> && echo "pool depletion: ok"
```

## The unapplied patch in cmake/patches/

`jana2-clear-outputs-off-mutex.patch` is kept in the tree but is **not** listed in
`ML4_JANA2_PATCHES`, so no build applies it. It adds `JArrow::ClearOutputs()`,
called after `Fire()` and before `Push()`, so that recycling an event — whose
`JFactorySet::Clear()` frees every inserted object — happens while the worker
still owns its outputs, instead of inside `JEventPool::Ingest()` with the
`JExecutionEngine` mutex held. Events that still have children are skipped, since
only the pool may clear those once the last child finishes.

It is unapplied because it measured as no change. On the fixed 500-block workload,
median wall time over seven interleaved runs per configuration:

| configuration | 8 threads | 16 threads |
|---|---|---|
| v2026.03.01, no patch | 10.31 s | 8.26 s |
| v2026.03.01 + this patch | 10.22 s | 8.35 s |

The differences are smaller than the run-to-run spread, and bypass (write-all)
mode, which pushes far more events through the pools, showed no gain either. Raw
per-run timings: `jana2-clearoutputs-filtered.csv` and
`jana2-clearoutputs-bypass.csv` in this directory.

The reason is structural rather than a defect in the patch: `EvioSroBlockSource`
parses each block on the source thread, so the chain barely scales with threads at
all (11.3 s at 1 thread against 8.4 s at 16), and worker-side mutex contention is
not what limits it. Re-test the patch after parsing moves off the source thread —
add its filename back to `ML4_JANA2_PATCHES` and rebuild. Beware of measuring this
with short runs: JANA's status ticker quantizes wall time in `jana:ticker_interval`
steps (500 ms by default), which is several percent of a 500-block run, and a
longer workload stops fitting in the page cache and adds its own noise. Set
`-Pjana:ticker_interval=100` and interleave the configurations.

## Verifying a JANA2 revision

To reproduce the parent-retention defect against an older JANA2, or to confirm a
new revision is free of it, build
`jana2_unfolder_uaf_reproducer.cc` in this directory against a JANA2 install. It
needs no input file and no ROOT:

```bash
g++ -std=c++20 -g -O1 docs/jana2_unfolder_uaf_reproducer.cc -I <jana2-install>/include -L <jana2-install>/lib -lJANA -Wl,-rpath,<jana2-install>/lib -o unfolder_uaf
```

The reproducer unfolds 10 timeslices into 3 children each and checks a canary in
the parent's inserted data from the child's processor. Against unpatched JANA2 it
aborts on the first child; against patched JANA2 it reports 30 events processed
and exits 0. Building both JANA2 and the reproducer with
`-fsanitize=address -fno-omit-frame-pointer` reports the use-after-free directly.

To confirm the whole chain, run 500 blocks with the coincidence finder and check
the counts: 5500 frames scanned, 235 selected, 2064003 fadc_hits, 6530147
dcrb_hits. Run it at `nthreads=1` and at `nthreads>1` — the two defects have
different thread-count sensitivities.
