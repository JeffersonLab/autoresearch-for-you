# Running the agent container

The image `eicdev/eic-claude` is the EIC software stack (`eicdev/eic-full`:
ROOT, toolchain, JANA2, spdlog, fmt preinstalled under /app) plus Node.js,
the Claude Code CLI, and uv. `IS_SANDBOX=1` is baked in, so
`--dangerously-skip-permissions` (fully autonomous mode) works inside the
container.

## One-time host preparation

```bash
mkdir -p ~/.claude-docker
```

This directory persists the Claude Code login across container runs.

## Start the container

```bash
docker run --rm -it --init \
  --user $(id -u):$(id -g) \
  -e HOME=/myhome \
  -e CLAUDE_CONFIG_DIR=/myhome/.claude \
  -e UV_CACHE_DIR=/data/autoresearch/uv-cache \
  -v ~/.claude-docker:/myhome/.claude \
  -v <your-data-dir>:/data \
  -v <path-to-this-clone>:/work \
  -w /work \
  eicdev/eic-claude:latest bash
```

Why each flag:

- `--user $(id -u):$(id -g)` — the container process runs with your numeric
  IDs, so files created in the mounts belong to you, not to root.
- `-e HOME=/myhome` — the image's default HOME is /root, which your ID cannot
  write to. `/myhome` is an arbitrary writable-enough path.
- `-e CLAUDE_CONFIG_DIR=/myhome/.claude` — the image bakes
  `CLAUDE_CONFIG_DIR=/root/.claude` for root runs; override it to follow your
  HOME.
- `-e UV_CACHE_DIR=...` — docker creates the `/myhome` mount point root-owned,
  so `$HOME` itself is not writable and uv's default cache (`~/.cache/uv`)
  fails. Point it at the writable data store.
- `-v ~/.claude-docker:/myhome/.claude` — credentials and settings survive
  container restarts. Mount read-write: token refresh writes back.
- `-v <your-data-dir>:/data` — must contain
  `sro_boyarinov_data_2026/sro_000791.evio.00000`. The agent writes builds,
  caches and .root outputs to `/data/autoresearch/`.
- `-v <path-to-this-clone>:/work -w /work` — the repository, mounted where
  `optimize.md` expects it.
- `--init` — a proper PID 1: signal handling and zombie reaping for the
  long-running agent.
- `--rm -it` — throwaway container, interactive shell. State that matters
  lives in the mounts.

## GPU (optional — this task does not need one)

To make NVIDIA GPUs visible, add `--device nvidia.com/gpu=all`. That flag
resolves through CDI; if docker errors on it, generate the CDI spec once:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

(`nvidia-ctk` comes with the nvidia-container-toolkit package.) If you don't
have an NVIDIA GPU, omit the flag.

## First run — log in

Inside the container:

```bash
claude
```

In the Claude UI type `/login`, follow the link, then `/exit`. The login is
stored in the mounted `~/.claude-docker` and is reused by every later run.
Check with `claude auth status`.

To use an API key instead of a subscription login, skip this and add
`-e ANTHROPIC_API_KEY=sk-ant-...` to `docker run`.

## Run the optimization loop

Headless, fully autonomous:

```bash
claude -p --model claude-fable-5 --dangerously-skip-permissions --verbose < /work/optimize.md
```

Same, with a replayable session log:

```bash
claude -p --model claude-fable-5 --dangerously-skip-permissions \
  --verbose --output-format stream-json < /work/optimize.md \
  | tee /data/autoresearch/run-$(date +%Y%m%d-%H%M).jsonl
```

Interactive (watch it work, intervene if needed):

```bash
claude --model claude-fable-5 --dangerously-skip-permissions --add-dir /data
```

then tell it: `Read /work/optimize.md and execute it.`

Notes:

- `claude -p` with no prompt argument reads the prompt from stdin; the
  redirect resolves inside the container, so `/work/optimize.md` is the
  mounted file.
- `--dangerously-skip-permissions` removes all permission prompts. It is
  acceptable here because the container only sees the three mounts.
- A run can take hours and a real token budget. The prompt tells the agent to
  keep state on disk (`space/notes/STATUS.md`), so an interrupted or
  rate-limited run resumes: start the same command again.

## Known gotchas

- `$HOME` (`/myhome`) is root-owned; only `/myhome/.claude` is writable.
  Anything that insists on writing to `$HOME` needs an env override (uv is
  handled above). Alternative layout: mount a directory over the whole HOME
  (`-v ~/.claude-docker-home:/myhome`) — then HOME is writable and the config
  dir lives inside it.
- The container has no git identity for your uid. `optimize.md` instructs the
  agent to set a repository-local `user.name`/`user.email` before its first
  commit; if you commit manually inside the container, do the same.
- Run `bash` as a login shell (the default here) — /etc/profile puts the
  preinstalled ROOT and JANA2 runtime paths into the environment. If a
  non-login shell can't find `libJANA.so`, that's why.
- The agent never pushes; all its commits stay in your clone. Review with
  `git log` after the run.

## Using a different LLM CLI

Replace the Claude Code install block in [../docker/Dockerfile](../docker/Dockerfile)
with your agent's CLI (Codex CLI, Gemini CLI, opencode, ...) and rebuild. Keep
the base image and uv. Adjust the login and headless-run commands to your
tool's equivalents; everything else in this document (mounts, users, paths)
stays the same.
