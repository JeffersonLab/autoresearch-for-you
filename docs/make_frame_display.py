"""Render one time-slice frame: X = hit time in frame, Y = channel, with the
coincidence the finder triggers on marked.

The finder logic mirrors SroFrameUnfolder::FramePassesFinder exactly: bin clean
(non-hot) ECAL hits into bin_ticks-wide bins of the 16384-tick frame and accept
the frame when any bin holds min_hits hits.

This is a documentation tool for reading the data by eye — it is not part of the
optimization loop.

Usage (needs uproot, matplotlib, numpy):
  uv run --with uproot --with matplotlib --with numpy python docs/make_frame_display.py \
      input=<chain output>.root hot_csv=config/hot_channels.csv out=frame.png

  list=true          rank the frames by strongest coincidence instead of plotting
  frame=<number>     plot a specific frame (default: the strongest one)
  zoom_us=<float>    half-width of the zoom panel, default 1.5 us

Reproduces docs/images/frame_coincidence.png with:
  frame=11540, from a 500-block coincidence-filtered run of sro_000791.evio.00000
"""
import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import uproot
from matplotlib.gridspec import GridSpec

FADC_TICK_NS = 4
DCRB_TICK_NS = 32
FADC_SLOT_CHANNELS = 16
DCRB_SLOT_CHANNELS = 96
FIRST_SLOT = 3
FADC_BAND = 18 * FADC_SLOT_CHANNELS
DCRB_BAND = 18 * DCRB_SLOT_CHANNELS
FADC_ROCS = [7, 9, 25, 27, 29, 84]
DCRB_ROCS = [44, 45, 46, 53, 54, 55]

ECAL, PCAL, UNKNOWN = 0, 1, -1
GROUP_STYLE = {
    ECAL: ("tab:blue", "ECAL"),
    PCAL: ("tab:orange", "PCAL"),
    UNKNOWN: ("tab:green", "unidentified roc 29/84"),
}


def parse_options(argv):
    options = {"input": "", "hot_csv": "", "out": "frame_display.png",
               "bin_ticks": 8, "min_hits": 6, "frame": -1, "list": False, "zoom_us": 1.5}
    for item in argv:
        key, _, value = item.partition("=")
        if key not in options:
            raise SystemExit(f"unknown option {key}")
        default = options[key]
        options[key] = value.lower() in ("1", "true", "yes") if isinstance(default, bool) \
            else type(default)(value)
    return options


def load_hot_channels(path):
    hot = {"fadc": set(), "dcrb": set()}
    with open(path) as handle:
        for row in csv.DictReader(handle):
            hot[row["group"]].add((int(row["rocid"]), int(row["slot"]), int(row["channel"])))
    return hot


def band_position(rocid, slot, channel):
    """Y coordinate: each ROC gets its own band, slot/channel stack inside it.

    The RNTuple columns are uint8/uint16, so cast before arithmetic — plain numpy
    scalars overflow on (slot - FIRST_SLOT) * channels.
    """
    rocid, slot, channel = int(rocid), int(slot), int(channel)
    if rocid in FADC_ROCS:
        start = FADC_ROCS.index(rocid) * FADC_BAND
        return start + (slot - FIRST_SLOT) * FADC_SLOT_CHANNELS + channel
    start = DCRB_ROCS.index(rocid) * DCRB_BAND
    return start + (slot - FIRST_SLOT) * DCRB_SLOT_CHANNELS + channel


def hot_mask(table, hot_set):
    keys = zip(table["rocid"].astype(int), table["slot"].astype(int), table["channel"].astype(int))
    return np.fromiter((key in hot_set for key in keys), dtype=bool, count=len(table["rocid"]))


def find_trigger_bin(frame_fadc, is_hot, bin_ticks, min_hits):
    """Return (bin_index, hit_count) of the fullest clean-ECAL time bin."""
    clean_ecal = (frame_fadc["detector"] == ECAL) & ~is_hot
    if not clean_ecal.any():
        return None, 0
    bins = frame_fadc["time_ticks"][clean_ecal].astype(np.int64) // bin_ticks
    counts = np.bincount(bins)
    best = int(counts.argmax())
    return best, int(counts[best])


def draw_panel(ax, times_us, positions, colors, sizes):
    ax.scatter(times_us, positions, c=colors, s=sizes, linewidths=0)


def label_bands(ax, rocs, band_height):
    """Tick label at the middle of each ROC band, separators at the edges.

    Labelling band starts instead would put a hit's marker next to its
    neighbour's label, which reads as the wrong crate.
    """
    ax.set_yticks([i * band_height + band_height / 2 for i in range(len(rocs))])
    ax.set_yticklabels([f"roc {roc}" for roc in rocs], fontsize=8)
    for i in range(1, len(rocs)):
        ax.axhline(i * band_height, color="0.85", linewidth=0.8, zorder=0)
    ax.set_ylim(-band_height * 0.05, len(rocs) * band_height * 1.02)


def main():
    opts = parse_options(sys.argv[1:])
    hot = load_hot_channels(opts["hot_csv"])

    source = uproot.open(opts["input"])
    fadc = source["fadc_hits"].arrays(
        ["frame_number", "rocid", "slot", "channel", "time_ticks", "detector"], library="np")
    dcrb = source["dcrb_hits"].arrays(
        ["frame_number", "rocid", "slot", "channel", "time_ticks"], library="np")
    fadc_is_hot = hot_mask(fadc, hot["fadc"])

    frame_numbers = np.unique(fadc["frame_number"])
    scored = []
    for number in frame_numbers:
        pick = fadc["frame_number"] == number
        sub = {name: column[pick] for name, column in fadc.items()}
        bin_index, count = find_trigger_bin(sub, fadc_is_hot[pick], opts["bin_ticks"], opts["min_hits"])
        if bin_index is not None:
            scored.append((count, int(number), bin_index))
    scored.sort(reverse=True)

    if opts["list"]:
        print("strongest coincidences (clean ECAL hits in one 32 ns bin):")
        for count, number, bin_index in scored[:15]:
            print(f"  frame {number:7d}  {count} hits in bin at {bin_index * opts['bin_ticks'] * FADC_TICK_NS / 1000.0:.3f} us")
        return 0

    if opts["frame"] >= 0:
        match = [entry for entry in scored if entry[1] == opts["frame"]]
        if not match:
            raise SystemExit(f"frame {opts['frame']} not in {opts['input']}")
        count, number, bin_index = match[0]
    else:
        count, number, bin_index = scored[0]

    pick = fadc["frame_number"] == number
    frame_fadc = {name: column[pick] for name, column in fadc.items()}
    frame_hot = fadc_is_hot[pick]
    pick_dcrb = dcrb["frame_number"] == number
    frame_dcrb = {name: column[pick_dcrb] for name, column in dcrb.items()}

    trigger_us = bin_index * opts["bin_ticks"] * FADC_TICK_NS / 1000.0
    bin_width_us = opts["bin_ticks"] * FADC_TICK_NS / 1000.0

    cal_times = frame_fadc["time_ticks"] * FADC_TICK_NS / 1000.0
    cal_pos = np.array([band_position(r, s, c) for r, s, c in
                        zip(frame_fadc["rocid"], frame_fadc["slot"], frame_fadc["channel"])])
    cal_colors = [GROUP_STYLE.get(int(d), ("tab:gray", ""))[0] for d in frame_fadc["detector"]]
    # hot channels are drawn, but greyed: they fire every frame and the finder skips them
    cal_colors = [("0.75" if is_hot else color) for color, is_hot in zip(cal_colors, frame_hot)]
    cal_sizes = np.where(frame_hot, 4, 14)

    dcrb_times = frame_dcrb["time_ticks"] * DCRB_TICK_NS / 1000.0
    dcrb_pos = np.array([band_position(r, s, c) for r, s, c in
                         zip(frame_dcrb["rocid"], frame_dcrb["slot"], frame_dcrb["channel"])]) if len(dcrb_times) else np.array([])
    dcrb_is_hot = hot_mask(frame_dcrb, hot["dcrb"]) if len(dcrb_times) else np.array([], dtype=bool)
    dcrb_colors = np.where(dcrb_is_hot, "0.8", "tab:red")

    fig = plt.figure(figsize=(14, 8))
    grid = GridSpec(2, 2, width_ratios=[2.4, 1], height_ratios=[1.15, 1], hspace=0.28, wspace=0.16)
    ax_cal = fig.add_subplot(grid[0, 0])
    ax_dc = fig.add_subplot(grid[1, 0], sharex=ax_cal)
    ax_zoom = fig.add_subplot(grid[:, 1])

    draw_panel(ax_cal, cal_times, cal_pos, cal_colors, cal_sizes)
    for axis in (ax_cal, ax_dc):
        axis.axvline(trigger_us, color="crimson", linestyle="--", linewidth=1.2, zorder=0)
    ax_cal.set_xlim(-1, 66.5)
    ax_cal.set_ylabel("calorimeter channel\n(one band per readout crate)")
    label_bands(ax_cal, FADC_ROCS, FADC_BAND)
    ax_cal.set_title(f"Time-slice frame {number}: {len(cal_times)} calorimeter + {len(dcrb_times)} drift-chamber hits in 65.5 us")

    if len(dcrb_times):
        ax_dc.scatter(dcrb_times[dcrb_is_hot], dcrb_pos[dcrb_is_hot], c="0.8", s=2, linewidths=0)
        ax_dc.scatter(dcrb_times[~dcrb_is_hot], dcrb_pos[~dcrb_is_hot], c="tab:red", s=6, linewidths=0)
    label_bands(ax_dc, DCRB_ROCS, DCRB_BAND)
    ax_dc.set_ylabel("drift chamber channel")
    ax_dc.set_xlabel("hit time inside the frame [us]")

    # zoom: the accepted bin, wide enough to show it is isolated in time. Y is
    # narrowed to the channels that fired, otherwise 18 hits spread over one
    # crate's band merge into a handful of blobs on the full-detector scale.
    half = opts["zoom_us"]
    in_zoom = (cal_times > trigger_us - half) & (cal_times < trigger_us + half)
    in_bin = (frame_fadc["detector"] == ECAL) & ~frame_hot \
        & (frame_fadc["time_ticks"].astype(np.int64) // opts["bin_ticks"] == bin_index)
    bin_pos = cal_pos[in_bin]
    bin_crates = sorted({int(r) for r in frame_fadc["rocid"][in_bin]})
    ax_zoom.axvspan(trigger_us, trigger_us + bin_width_us, color="crimson", alpha=0.18,
                    label=f"accepted bin ({bin_width_us * 1000:.0f} ns)")
    # white marker edges: within the bin several channels land on nearly the same
    # (time, y) and would merge into one blob otherwise
    ax_zoom.scatter(cal_times[in_zoom], cal_pos[in_zoom],
                    c=[cal_colors[i] for i in np.flatnonzero(in_zoom)],
                    s=np.where(frame_hot[in_zoom], 8, 52),
                    edgecolors=np.where(frame_hot[in_zoom], "none", "white"), linewidths=0.6)
    ax_zoom.set_xlim(trigger_us - half, trigger_us + half)
    pad = max(24.0, (bin_pos.max() - bin_pos.min()) * 0.3)
    ax_zoom.set_ylim(bin_pos.min() - pad, bin_pos.max() + pad)
    # y ticks at slot boundaries of the crate that fired: the shower spreads over slots
    if len(bin_crates) == 1:
        crate = bin_crates[0]
        band_start = FADC_ROCS.index(crate) * FADC_BAND
        # label the middle of each slot's 16 channels; separators at slot edges
        slot_edges = [(band_start + (slot - FIRST_SLOT) * FADC_SLOT_CHANNELS, slot)
                      for slot in range(FIRST_SLOT, FIRST_SLOT + 19)]
        low, high = ax_zoom.get_ylim()
        visible = [(y, slot) for y, slot in slot_edges if low <= y + FADC_SLOT_CHANNELS / 2 <= high]
        ax_zoom.set_yticks([y + FADC_SLOT_CHANNELS / 2 for y, _ in visible])
        ax_zoom.set_yticklabels([f"slot {slot}" for _, slot in visible], fontsize=8)
        for y, _ in slot_edges:
            ax_zoom.axhline(y, color="0.9", linewidth=0.8, zorder=0)
        ax_zoom.set_ylabel(f"roc {crate} channels")
    ax_zoom.set_xlabel("hit time inside the frame [us]")
    crate_text = f"roc {bin_crates[0]}" if len(bin_crates) == 1 else f"rocs {bin_crates}"
    ax_zoom.set_title(f"zoom on {crate_text}: {count} calorimeter channels fire within one\n"
                      f"{bin_width_us * 1000:.0f} ns bin (threshold {opts['min_hits']}) -> frame accepted")

    # only advertise groups that actually have a coloured hit in this frame
    handles = [plt.Line2D([], [], marker="o", linestyle="", color=color, label=label)
               for detector, (color, label) in GROUP_STYLE.items()
               if ((frame_fadc["detector"] == detector) & ~frame_hot).any()]
    if len(dcrb_times) and (~dcrb_is_hot).any():
        handles.append(plt.Line2D([], [], marker="o", linestyle="", color="tab:red", label="drift chamber"))
    handles.append(plt.Line2D([], [], marker="o", linestyle="", color="0.8", label="always-on channel (finder ignores)"))
    handles.append(plt.Line2D([], [], linestyle="--", color="crimson", label="coincidence time"))
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(0.5, -0.03),
               ncol=6, fontsize=9, frameon=False)
    ax_zoom.legend(loc="upper right", fontsize=8)

    fig.savefig(opts["out"], dpi=110, bbox_inches="tight")
    print(f"frame {number}: {count} clean ECAL hits in the bin at {trigger_us:.3f} us -> {opts['out']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
