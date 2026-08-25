// unfolder_uaf.cc — parent payload freed while a child still references it.
#include <JANA/JApplication.h>
#include <JANA/JEventSource.h>
#include <JANA/JEventUnfolder.h>
#include <JANA/JEventProcessor.h>
#include <cstdio>
#include <cstdlib>
#include <vector>

static constexpr uint64_t CANARY = 0xABCDEF0123456789ULL;

struct BlockData {                      // inserted into the parent (timeslice) by the source
    std::vector<uint64_t> samples;
    uint64_t canary = CANARY;
};

struct FrameRef {                       // child payload: pointer INTO the parent's BlockData,
    const BlockData* block;             // valid per the parent-lifetime guarantee
    int frame_index;
};

struct TimesliceSource : JEventSource {
    TimesliceSource() {
        SetLevel(JEventLevel::Timeslice);
        SetCallbackStyle(CallbackStyle::ExpertMode);
    }
    Result Emit(JEvent& event) override {
        auto* block = new BlockData;
        block->samples.assign(100000, event.GetEventNumber());
        event.Insert(block);
        return Result::Success;
    }
};

struct FrameUnfolder : JEventUnfolder {
    FrameUnfolder() {
        SetParentLevel(JEventLevel::Timeslice);
        SetChildLevel(JEventLevel::PhysicsEvent);
    }
    Result Unfold(const JEvent& parent, JEvent& child, int child_idx) override {
        child.Insert(new FrameRef{parent.GetSingle<BlockData>(), child_idx});
        // Three children per timeslice; the last one takes the NextChildNextParent
        // branch, which pushes the parent to its pool in the same firing.
        return child_idx == 2 ? Result::NextChildNextParent : Result::NextChildKeepParent;
    }
};

struct FrameProcessor : JEventProcessor {
    FrameProcessor() { SetCallbackStyle(CallbackStyle::ExpertMode); }
    void ProcessSequential(const JEvent& event) override {
        const auto* ref = event.GetSingle<FrameRef>();
        if (ref->block->canary != CANARY) {
            std::fprintf(stderr, "use-after-free: parent payload destroyed before child %llu finished\n",
                         (unsigned long long) event.GetEventNumber());
            std::abort();
        }
    }
};

int main() {
    JApplication app;
    app.SetParameterValue("jana:nevents", 10);
    app.SetParameterValue("nthreads", 1);
    app.Add(new TimesliceSource);
    app.Add(new FrameUnfolder);
    app.Add(new FrameProcessor);
    app.Run();
    return 0;
}
