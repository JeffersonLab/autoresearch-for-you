# jana4ml4fpga — SRO streaming chain (autoresearch snapshot)

A stripped-down snapshot of
[JANA4ML4FPGA](https://github.com/JeffersonLab/jana4ml4fpga), reduced to the
components that read and filter streaming-readout (SRO) EVIO6 data. Everything
unrelated to that chain — GEM/SRS reconstruction, the HallD EVIO reader, the
TCP DAQ sources, the flat-tree writer, DQM — is removed. The upstream
repository has the full project.

The code here is the optimization target of
[autoresearch-for-you](../README.md). It works and is validated, and it is
deliberately unoptimized: single-thread reader, eager parsing, serial writer.

## What is in the chain

```
evio file ──► EvioSroBlockSource ──► SroFrameUnfolder ──► SroRNTupleWriter ──► out.root
              1 evio block           1 frame = 1 event    frames / fadc_hits /
              = 1 timeslice          coincidence finder   dcrb_hits RNTuples
```

| Component | Path | Role |
|---|---|---|
| `evio_sro_parser` | [src/libraries/evio_sro_parser](src/libraries/evio_sro_parser) | Standalone decode library: block reader, frame-set parser, translation tables. No JANA, no ROOT — so `sro_dump` and unit checks build without the framework. |
| `evio6_file` | [src/plugins/evio6_file](src/plugins/evio6_file) | JANA2 plugin: timeslice source, frame unfolder with the coincidence finder, RNTuple writer, and a null writer for isolating the writer's cost. |
| `log` | [src/services/log](src/services/log) | spdlog-backed logging service; loaded by default (see `main.cc`). |
| `jana4ml4fpga` | [src/executables/jana4ml4fpga](src/executables/jana4ml4fpga) | CLI wrapper around JANA2. |
| `sro_dump` | [src/libraries/evio_sro_parser/sro_dump.cc](src/libraries/evio_sro_parser/sro_dump.cc) | Framework-free decoder check: dumps block and frame structure. |

## Build

Requirements: a C++20 compiler, CMake ≥ 3.19, ROOT ≥ 6.38 (for RNTuple), and
network access on the first configure. JANA2, spdlog and fmt are fetched and
built automatically when `find_package` does not find them; JANA2 is patched
during the fetch (see [cmake/fetch_dependencies.cmake](cmake/fetch_dependencies.cmake)).

```bash
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=build/install
cmake --build build -j $(nproc)
cmake --install build
```

`install_software.py` is an alternative for hosts without ROOT: it bootstraps a
self-contained Miniforge environment (ROOT + C++20 toolchain + CMake) and then
runs the build.

## Run

```bash
export LD_LIBRARY_PATH=<prefix>/lib:$LD_LIBRARY_PATH
export JANA_PLUGIN_PATH=<prefix>/plugins

<prefix>/bin/jana4ml4fpga -Pplugins=evio6_file \
  -Pnthreads=1 -Pjana:nevents=500 \
  -Pevio6_file:finder=coincidence \
  -Pevio6_file:finder_bin_ticks=8 \
  -Pevio6_file:finder_min_hits_in_bin=6 \
  -Pevio6_file:finder_hot_channels=<repo>/config/hot_channels.csv \
  -Pevio6_file:output_file=out.root \
  <input>.evio.00000
```

`-Pjana:nevents=N` counts evio blocks (timeslices), not frames.

### Parameters

| Parameter | Values | Meaning |
|---|---|---|
| `evio6_file:parse` | `0`, `1` | `0` reads blocks but skips parsing: a pure I/O measurement, no frames reach the output. |
| `evio6_file:finder` | `coincidence`, `ecal`, `bypass` | Frame selection. `bypass` writes every frame (diagnostic). |
| `evio6_file:finder_bin_ticks` | integer | Coincidence finder: time-bin width in ticks. |
| `evio6_file:finder_min_hits_in_bin` | integer | Coincidence finder: hits per bin required to accept a frame. |
| `evio6_file:finder_hot_channels` | path | CSV of always-on channels the finder ignores. Without it the finder warns and noisy channels fake coincidences. |
| `evio6_file:finder_min_ecal_charge` | integer | Threshold used by `finder=ecal`. |
| `evio6_file:output_file` | path | Output ROOT file. |
| `evio6_file:writer` | `rntuple`, `null` | `null` discards output; use it to measure the chain without write cost. |

### Output format

Three RNTuples keyed on `frame_number`: `frames` (one row per selected frame,
with `n_fadc_hits` / `n_dcrb_hits` counts), `fadc_hits` and `dcrb_hits` (one
row per hit, with rocid/slot/channel, charge, time and translated detector
coordinates).
