#!/usr/bin/env bash
# SessionStart hook: clone a Bitbucket repo into ./workspace/ and run or surface
# its repo-specific setup instructions. Anything printed to stdout is added to
# Claude's context, so keep stdout for things Claude should read; logs go to stderr/file.
#
# Environment variables (set them in the cloud environment's settings):
#   BB_REPO          required  "workspace/repo-slug" (Bitbucket Cloud), or set BB_URL instead
#   BB_URL           optional  full HTTPS clone URL (Bitbucket Data Center / Server, mirrors)
#   BB_TOKEN         optional  access token; omit if a network secret injects auth for the host
#   BB_USER          optional  git username for the token (default: x-token-auth, which suits
#                              repository/project/workspace access tokens; use
#                              x-bitbucket-api-token-auth for Atlassian API tokens)
#   BB_BRANCH        optional  branch to check out after cloning (default: the repo's default
#                              branch; all branches are fetched, so Claude can switch later)
#   BB_SETUP_FILE    optional  path inside the Bitbucket repo to the setup instructions:
#                                Markdown -> printed into Claude's context to carry out first
#                                *.sh     -> alternative: executed once per container before Claude starts
#   BB_START_DOCKER  optional  "1" to start dockerd in the background
#   BB_BOOTSTRAP_LOCAL optional "1" to also run outside cloud sessions
set -uo pipefail

if [[ "${CLAUDE_CODE_REMOTE:-}" != "true" && "${BB_BOOTSTRAP_LOCAL:-}" != "1" ]]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
WS="$ROOT/workspace"
LOG="$WS/.bootstrap.log"
mkdir -p "$WS"
log() { echo "[claude-cloud-proceed-in-bitbucket] $*" | tee -a "$LOG" >&2; }

if [[ -z "${BB_URL:-}" ]]; then
  if [[ -z "${BB_REPO:-}" ]]; then
    echo "claude-cloud-proceed-in-bitbucket: BB_REPO (or BB_URL) is not set, so no Bitbucket repository was cloned. Tell the user to set it in the cloud environment's settings."
    exit 0
  fi
  BB_URL="https://bitbucket.org/${BB_REPO}.git"
fi
NAME="$(basename "${BB_URL%.git}")"
DEST="$WS/$NAME"

# Credential helper that reads the token from the environment at call time,
# so the token is never written to .git/config or the remote URL.
CRED_HELPER='!f() { test -n "${BB_TOKEN:-}" && { echo "username=${BB_USER:-x-token-auth}"; echo "password=${BB_TOKEN}"; }; }; f'

if [[ -d "$DEST/.git" ]]; then
  log "Repository already present at $DEST, fetching."
  git -C "$DEST" fetch --all --prune >>"$LOG" 2>&1 || log "fetch failed (continuing with local copy)"
else
  log "Cloning $BB_URL into $DEST"
  args=(clone)
  [[ -n "${BB_BRANCH:-}" ]] && args+=(--branch "$BB_BRANCH")
  if ! git -c credential.helper= -c credential.helper="$CRED_HELPER" "${args[@]}" "$BB_URL" "$DEST" >>"$LOG" 2>&1; then
    echo "claude-cloud-proceed-in-bitbucket: cloning $BB_URL FAILED. See $LOG. Likely causes: host not in the environment's allowed domains, missing/expired token, or wrong BB_USER for the token type. Do not invent the repository's contents; tell the user."
    exit 0
  fi
fi
git -C "$DEST" config credential.helper ""
git -C "$DEST" config --add credential.helper "$CRED_HELPER"

if [[ "${BB_START_DOCKER:-}" == "1" ]] && command -v dockerd >/dev/null && ! docker info >/dev/null 2>&1; then
  log "Starting dockerd"
  nohup dockerd >"$WS/.dockerd.log" 2>&1 &
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi

echo "claude-cloud-proceed-in-bitbucket: Bitbucket repository $NAME is at $DEST, on branch $(git -C "$DEST" rev-parse --abbrev-ref HEAD) (all remote branches are fetched). This is the project to work on."

if [[ -n "${BB_SETUP_FILE:-}" ]]; then
  SETUP="$DEST/$BB_SETUP_FILE"
  if [[ ! -f "$SETUP" ]]; then
    echo "claude-cloud-proceed-in-bitbucket: BB_SETUP_FILE=$BB_SETUP_FILE was not found in the repository. Tell the user."
  elif [[ "$SETUP" == *.sh ]]; then
    MARK="$WS/.setup-done-$NAME"
    if [[ -f "$MARK" ]]; then
      echo "claude-cloud-proceed-in-bitbucket: setup script $BB_SETUP_FILE already ran in this container."
    else
      log "Running $SETUP"
      if (cd "$DEST" && bash "$SETUP") >>"$LOG" 2>&1; then
        touch "$MARK"
        echo "claude-cloud-proceed-in-bitbucket: setup script $BB_SETUP_FILE completed. Log: $LOG"
      else
        echo "claude-cloud-proceed-in-bitbucket: setup script $BB_SETUP_FILE FAILED. Read the end of $LOG, fix or report the problem before other work."
      fi
    fi
  else
    echo "claude-cloud-proceed-in-bitbucket: Before doing anything else, carry out the setup instructions below (from $BB_SETUP_FILE, run commands from $DEST), then verify them:"
    echo "----- BEGIN $BB_SETUP_FILE -----"
    cat "$SETUP"
    echo "----- END $BB_SETUP_FILE -----"
  fi
fi
exit 0
