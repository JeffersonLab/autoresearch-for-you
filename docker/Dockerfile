# EIC + Claude Code agent layer (adds Node.js + Claude Code on top of eic-full)
#
# Turns the full EIC software stack into an environment where the Claude Code
# agent can build, run, and debug EIC software either interactively, in a
# semi-automatic mode (auto-accept edits, prompt for risky commands), or in a
# fully autonomous / headless mode (--dangerously-skip-permissions, no prompts).
#
# Build:
#   docker build -t eicdev/eic-claude:latest .
#   docker buildx build --tag eicdev/eic-claude:latest --push .
#
# Run — interactive agent (bring your own key):
#   docker run --rm -it --init \
#     -e ANTHROPIC_API_KEY=sk-ant-... \
#     -v "$PWD":/work -w /work \
#     eicdev/eic-claude:latest claude
#
# Run — semi-automatic (default settings: auto-accept edits, ask before running
#        shell commands):
#   docker run --rm -it --init -e ANTHROPIC_API_KEY=sk-ant-... \
#     -v "$PWD":/work -w /work eicdev/eic-claude:latest \
#     claude "fix the failing EICrecon test"
#
# Run — fully autonomous / headless (no prompts at all):
#   docker run --rm --init -e ANTHROPIC_API_KEY=sk-ant-... \
#     -v "$PWD":/work -w /work eicdev/eic-claude:latest \
#     claude -p "build epic and report any errors" --dangerously-skip-permissions
#
#   (IS_SANDBOX=1 is baked in so --dangerously-skip-permissions works as root
#    inside the container.)

# uv build stage — declared here so VERSION_UV is in global scope.  Docker
# forbids variable expansion in `COPY --from=...`, so we pull uv as a named
# stage (which *does* allow an ARG in the FROM) and copy from that stage below.
# Pin with --build-arg VERSION_UV=0.5.0 (an image tag) for reproducible builds.
ARG VERSION_UV=latest
FROM ghcr.io/astral-sh/uv:${VERSION_UV} AS uv

FROM eicdev/eic-full:latest

WORKDIR ${APP_ROOT}

# ---------------------------------------------------------------------------#
#  Node.js (Claude Code runtime dependency)                                  #
#                                                                            #
#  Claude Code needs Node.js 18+.  Ubuntu 24.04 ships an older node in its   #
#  repos, so we install the current LTS (22.x) from NodeSource.              #
# ---------------------------------------------------------------------------#
ARG NODE_MAJOR=22

RUN set -ex && \
    apt-get update && \
    apt-get install -y ca-certificates gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    apt-get clean && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------#
#  Claude Code CLI                                                            #
#                                                                            #
#  Installed globally via npm.  Pin a specific version with                  #
#  --build-arg VERSION_CLAUDE_CODE=1.2.3 for reproducible builds.            #
# ---------------------------------------------------------------------------#
ARG VERSION_CLAUDE_CODE=latest

RUN set -ex && \
    npm install -g "@anthropic-ai/claude-code@${VERSION_CLAUDE_CODE}" && \
    npm cache clean --force && \
    claude --version

# ---------------------------------------------------------------------------#
#  uv (Python package/venv manager used by agent workflows)                  #
#                                                                            #
#  Copied as static binaries from the `uv` stage defined at the top.         #
# ---------------------------------------------------------------------------#
COPY --from=uv /uv /uvx /usr/local/bin/

RUN uv --version

# ---------------------------------------------------------------------------#
#  Pre-install the project's Python dependencies into the uv cache            #
#                                                                            #
#  A dummy pyproject.toml (mirroring the target project) is synced at build   #
#  time.  This downloads every wheel — including CUDA-enabled torch — into    #
#  uv's cache (/root/.cache/uv), which persists in the image.  At run time    #
#  the agent's `uv sync` inside /work resolves entirely from cache with NO    #
#  network downloads, so it never waits.                                      #
#                                                                            #
#  --no-install-project: install only the dependencies, not the dummy root   #
#  package (there is no source to build).  The throwaway .venv is removed;    #
#  only the cache is what we keep.                                            #
#                                                                            #
#  NOTE: this adds several GB to the image (torch bundles the CUDA runtime).  #
#  Keep this file in sync with the real project's pyproject.toml so the       #
#  cached versions match what the agent resolves at run time.                 #
# ---------------------------------------------------------------------------#
COPY pyproject.toml /opt/uv-prime/pyproject.toml
RUN cd /opt/uv-prime && \
    uv sync --no-install-project && \
    rm -rf /opt/uv-prime/.venv

# ---------------------------------------------------------------------------#
#  Agent configuration                                                        #
#                                                                            #
#  settings.json ships a sensible "semi-automatic" default: edits are        #
#  auto-accepted, but shell commands still prompt.  Autonomous runs override #
#  this per-invocation with `claude --dangerously-skip-permissions`.         #
#                                                                            #
#  IS_SANDBOX=1 tells Claude Code it runs in an isolated container, which    #
#  allows --dangerously-skip-permissions while running as root.             #
#  DISABLE_AUTOUPDATER pins the baked-in CLI version for reproducibility.    #
# ---------------------------------------------------------------------------#
COPY settings.json /root/.claude/settings.json

ENV IS_SANDBOX=1 \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CONFIG_DIR=/root/.claude

# Non-interactive git identity so autonomous commits do not fail.
RUN git config --global user.name  "EIC Claude Agent" && \
    git config --global user.email "eic-claude@localhost" && \
    git config --global init.defaultBranch main && \
    git config --global --add safe.directory '*'

SHELL ["/bin/bash", "-c"]
