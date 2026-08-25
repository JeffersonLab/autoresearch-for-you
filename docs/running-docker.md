# Running the agent container

The images `eicdev/eic-claude` and `eicdev/eic-opencode` bundle the full EIC software
stack (`eicdev/eic-full`: ROOT, toolchain, JANA2, spdlog, fmt preinstalled under
/app) plus Node.js, the respective agent CLI (Claude Code or opencode), and uv.
In `eic-claude`, `IS_SANDBOX=1` is baked in so `--dangerously-skip-permissions`
works as root; `eic-opencode` needs no equivalent — `opencode run --auto` has no
such restriction.

## One-time host preparation

```bash
# For Claude Code:
mkdir -p ~/.claude-docker

# For opencode:
mkdir -p ~/.opencode-docker
```

This directory persists agent credentials and settings across container runs.

## Start the container

### Option A — Claude Code (`eic-claude`)

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

### Option B — opencode (`eic-opencode`)

```bash
docker run --rm -it --init \
  --user $(id -u):$(id -g) \
  -e HOME=/myhome \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e UV_CACHE_DIR=/data/autoresearch/uv-cache \
  -v ~/.opencode-docker:/myhome \
  -v <your-data-dir>:/data \
  -v <path-to-this-clone>:/work \
  -w /work \
  eicdev/eic-opencode:latest bash
```

Two differences from option A, both consequences of how opencode stores state:

- **The whole `$HOME` is mounted**, not just one config subdirectory. opencode
  creates `~/.config/opencode`, `~/.local/share/opencode` (this is where
  `auth.json` lives), `~/.local/state/opencode` and `~/.cache/opencode` at
  startup. With only a subdirectory mounted, `/myhome` itself stays root-owned
  and opencode aborts with `EACCES: permission denied, mkdir '/myhome/.config'`.
- **No config-dir env override is needed.** The image bakes its config at
  `/etc/opencode/opencode.json` and points `OPENCODE_CONFIG` there — a
  world-readable path, so the `--user` run still gets the baked defaults
  (`/root` is mode 700). Set `OPENCODE_CONFIG` yourself only to substitute a
  different config.

`ANTHROPIC_API_KEY` is just one option — opencode is provider-agnostic and
picks up `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, `XAI_API_KEY`
and others the same way. Pin a specific model with `-m provider/model`.

Why each flag:

- `--user $(id -u):$(id -g)` — the container process runs with your numeric
  IDs, so files created in the mounts belong to you, not to root.
- `-e HOME=/myhome` — the image's default HOME is /root, which your ID cannot
  write to. `/myhome` is an arbitrary writable-enough path.
- `-e CLAUDE_CONFIG_DIR=/myhome/.claude` — the image bakes
  `CLAUDE_CONFIG_DIR=/root/.claude` for root runs; override it to follow your
  HOME.
- `-e UV_CACHE_DIR=...` — under option A docker creates the `/myhome` mount
  point root-owned, so `$HOME` itself is not writable and uv's default cache
  (`~/.cache/uv`) fails. Point it at the writable data store. Under option B
  `$HOME` *is* writable, but keeping the cache on the data volume is still
  worth it: it is multi-GB and survives a wiped home.
- `-v ~/.claude-docker:/myhome/.claude` (option A) /
  `-v ~/.opencode-docker:/myhome` (option B) — credentials and settings survive
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

### Claude Code:
Inside the container:

```bash
claude
```

In the Claude UI type `/login`, follow the link, then `/exit`. The login is
stored in the mounted `~/.claude-docker` and is reused by every later run.
Check with `claude auth status`.

To use an API key instead of a subscription login, skip this and add
`-e ANTHROPIC_API_KEY=sk-ant-...` to `docker run`.

### opencode:
Pass a provider key into `docker run` (`-e ANTHROPIC_API_KEY=sk-ant-...`,
`-e OPENAI_API_KEY=...`, `-e GEMINI_API_KEY=...`, …), or run
`opencode providers login` inside the container to authenticate interactively.
That writes `~/.local/share/opencode/auth.json`, which lands in the mounted
`~/.opencode-docker` and is reused by every later run.

## Run the optimization loop

### With Claude Code:

Headless, fully autonomous:

```bash
claude -p --model claude-fable-5 --dangerously-skip-permissions --verbose < /work/optimize.md
```

With a replayable session log:

```bash
claude -p --model claude-fable-5 --dangerously-skip-permissions \
  --verbose --output-format stream-json < /work/optimize.md \
  | tee /data/autoresearch/run-claude-$(date +%Y%m%d-%H%M).jsonl
```

Interactive (watch it work, intervene if needed):

```bash
claude --model claude-fable-5 --dangerously-skip-permissions --add-dir /data
```

then tell it: `Read /work/optimize.md and execute it.`

### With opencode:

Headless, fully autonomous:

```bash
opencode run --auto "$(cat /work/optimize.md)"
```

With session logging:

```bash
opencode run --auto "$(cat /work/optimize.md)" \
  | tee /data/autoresearch/run-opencode-$(date +%Y%m%d-%H%M).log
```

With a replayable machine-readable log instead:

```bash
opencode run --auto --format json "$(cat /work/optimize.md)" \
  | tee /data/autoresearch/run-opencode-$(date +%Y%m%d-%H%M).jsonl
```

Interactive (watch it work, intervene if needed):

```bash
opencode
```

then tell it: `Read /work/optimize.md and execute it.`

Notes:

- `claude -p` with no prompt argument reads the prompt from stdin; the
  redirect resolves inside the container, so `/work/optimize.md` is the
  mounted file.
- `opencode run` takes the prompt as a positional argument, so the file is
  substituted on the command line (`"$(cat /work/optimize.md)"`) rather than
  redirected on stdin.
- `--dangerously-skip-permissions` (Claude Code) and `--auto` (opencode) remove
  all permission prompts. That is acceptable here because the container only
  sees the three mounts.
- A run can take hours and a real token budget. The prompt tells the agent to
  keep state on disk (`space/notes/STATUS.md`), so an interrupted or
  rate-limited run resumes: start the same command again.

## Known gotchas

- With the Claude Code layout, `$HOME` (`/myhome`) is root-owned and only
  `/myhome/.claude` is writable. Anything that insists on writing to `$HOME`
  needs an env override (uv is handled above). Alternative layout: mount a
  directory over the whole HOME (`-v ~/.claude-docker-home:/myhome`) — then
  HOME is writable and the config dir lives inside it. The opencode recipe
  above already uses that whole-HOME layout, because opencode requires it.
- The container has no git identity for your uid. `optimize.md` instructs the
  agent to set a repository-local `user.name`/`user.email` before its first
  commit; if you commit manually inside the container, do the same.
- Run `bash` as a login shell (the default here) — /etc/profile puts the
  preinstalled ROOT and JANA2 runtime paths into the environment. If a
  non-login shell can't find `libJANA.so`, that's why.
- The agent never pushes; all its commits stay in your clone. Review with
  `git log` after the run.

## Using a different LLM CLI

Two are provided: [../docker/Dockerfile](../docker/Dockerfile) (Claude Code) and
[../docker/Dockerfile.opencode](../docker/Dockerfile.opencode) (opencode). For a
third, copy either one and replace the CLI install block with your agent's
(Codex CLI, Aider, ...). Keep the base image and uv. Adjust the login and
headless-run commands to your tool's equivalents; everything else in this
document (mounts, users, paths) stays the same — check whether your CLI needs
only a config subdirectory (like Claude Code) or a fully writable `$HOME` (like
opencode).
