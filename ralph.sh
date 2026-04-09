#!/bin/bash
# Ralph Wiggum - Codex-native long-running agent loop
# Usage: ./ralph.sh [--tool codex] [max_iterations]

set -e

# Parse arguments
TOOL="codex"
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "codex" ]]; then
  echo "Error: Invalid tool '$TOOL'. This repository only supports 'codex'."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
BASE_PROMPT_FILE="$SCRIPT_DIR/CODEX.md"
CODEX_LAST_MESSAGE_FILE="$SCRIPT_DIR/.codex-last-message.txt"
CODEX_PROMPT_FILE="$SCRIPT_DIR/.codex-iteration-prompt.md"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: 'codex' CLI not found in PATH."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: 'jq' is required."
  exit 1
fi

if [ ! -f "$BASE_PROMPT_FILE" ]; then
  echo "Error: Missing $BASE_PROMPT_FILE"
  exit 1
fi

file_fingerprint() {
  local file="$1"
  if [ -f "$file" ]; then
    cksum "$file" | awk '{print $1 ":" $2}'
  else
    echo "missing"
  fi
}

current_story_state() {
  if [ -f "$PRD_FILE" ]; then
    jq -r '.userStories | map(select(.passes != true)) | sort_by(.priority) | .[0] | "\(.id // "none")|\(.title // "")|\(.passes // false)"' "$PRD_FILE" 2>/dev/null || echo "none||false"
  else
    echo "none||false"
  fi
}

write_codex_prompt() {
  local next_story
  next_story="$(current_story_state)"
  local story_id="${next_story%%|*}"
  local remainder="${next_story#*|}"
  local story_title="${remainder%%|*}"

  cat > "$CODEX_PROMPT_FILE" <<EOF
## Runtime Context

- Project root: \`$PROJECT_ROOT\`
- Ralph workspace: \`$SCRIPT_DIR\`
- PRD file: \`$PRD_FILE\`
- Progress log: \`$PROGRESS_FILE\`
- Current target story: \`$story_id\` - $story_title

Read and update the files at those exact paths. Do not assume the PRD or progress log live in the current working directory.
EOF
  printf "\n" >> "$CODEX_PROMPT_FILE"
  cat "$BASE_PROMPT_FILE" >> "$CODEX_PROMPT_FILE"
}

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"
echo "Project root: $PROJECT_ROOT"
echo "Ralph workspace: $SCRIPT_DIR"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  BEFORE_PROGRESS="$(file_fingerprint "$PROGRESS_FILE")"
  BEFORE_PRD="$(file_fingerprint "$PRD_FILE")"
  BEFORE_STORY="$(current_story_state)"
  COMPLETION_TEXT=""

  write_codex_prompt
  rm -f "$CODEX_LAST_MESSAGE_FILE"
  OUTPUT=$(codex exec \
    --dangerously-bypass-approvals-and-sandbox \
    --skip-git-repo-check \
    -C "$PROJECT_ROOT" \
    -o "$CODEX_LAST_MESSAGE_FILE" \
    - < "$CODEX_PROMPT_FILE" 2>&1 | tee /dev/stderr) || true

  # Prefer the agent's final message when checking completion, since stdout may include CLI noise.
  if [[ -f "$CODEX_LAST_MESSAGE_FILE" ]]; then
    OUTPUT="$(cat "$CODEX_LAST_MESSAGE_FILE")"$'\n'"$OUTPUT"
    COMPLETION_TEXT="$(cat "$CODEX_LAST_MESSAGE_FILE")"
  fi

  AFTER_PROGRESS="$(file_fingerprint "$PROGRESS_FILE")"
  AFTER_PRD="$(file_fingerprint "$PRD_FILE")"
  AFTER_STORY="$(current_story_state)"
  
  # Check for completion signal
  if [[ "$COMPLETION_TEXT" == *"<promise>COMPLETE</promise>"* ]]; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  if [[ "$BEFORE_PROGRESS" == "$AFTER_PROGRESS" && "$BEFORE_PRD" == "$AFTER_PRD" ]]; then
    echo ""
    echo "Codex iteration made no durable updates to prd.json or progress.txt."
    echo "Stopping early to avoid a blind loop."
    echo "Prompt used: $CODEX_PROMPT_FILE"
    exit 1
  fi

  if [[ "$BEFORE_STORY" == "$AFTER_STORY" && "$BEFORE_PROGRESS" == "$AFTER_PROGRESS" ]]; then
    echo ""
    echo "Codex did not advance the current story or append progress."
    echo "Stopping early to avoid repeating the same iteration."
    echo "Prompt used: $CODEX_PROMPT_FILE"
    exit 1
  fi
  
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
