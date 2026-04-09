# codex-ralph

Codex-native adaptation of Ralph, originally created by Ryan Carson / Snark Tank in [`snarktank/ralph`](https://github.com/snarktank/ralph).

This repo keeps the two reusable skills:

- `skills/prd`: generate a markdown PRD
- `skills/ralph`: convert a PRD into `prd.json`

It also includes a Codex-focused loop:

- `ralph.sh`: repeatedly runs `codex exec` against the current repo
- `CODEX.md`: the base prompt used for each iteration

## What Changed

- The runner is Codex-first and defaults to `codex`
- Each iteration is executed from the actual git project root
- The script generates a per-iteration prompt with absolute paths for `prd.json` and `progress.txt`
- Completion detection is based on Codex's final message, not the full CLI transcript
- The loop stops early if an iteration produces no durable update to `prd.json` or `progress.txt`

## Prerequisites

- Codex CLI installed and authenticated
- `jq` installed
- A git repository for the project you want Ralph to work on

## Install the Skills

Copy the skill folders into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
cp -R skills/prd ~/.codex/skills/
cp -R skills/ralph ~/.codex/skills/
```

Restart Codex after installing new skills.

## Use the Skills

Create a PRD:

```text
Load the prd skill and create a PRD for [feature]
```

Convert the PRD into `prd.json`:

```text
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

## Run Ralph

From the target project root:

```bash
./ralph.sh 10
```

or explicitly:

```bash
./ralph.sh --tool codex 10
```

The loop will:

1. Read `prd.json`
2. Pick the next unfinished story by priority
3. Ask Codex to complete one story
4. Require progress to be appended to `progress.txt`
5. Mark the story complete in `prd.json`
6. Repeat until all stories pass or the iteration limit is reached

## Files

- `CODEX.md`: base Codex instructions for each iteration
- `ralph.sh`: Codex runner
- `prd.json.example`: sample task file
- `skills/prd/SKILL.md`: PRD generation skill
- `skills/ralph/SKILL.md`: PRD-to-JSON conversion skill

## Attribution

This project is an adaptation of Ralph by Ryan Carson / Snark Tank.

- Original repository: [`snarktank/ralph`](https://github.com/snarktank/ralph)
- Original pattern write-up referenced by that repo: Geoffrey Huntley's Ralph pattern

This repo keeps the core workflow idea and adapts the loop, prompt, and skills for Codex CLI.
