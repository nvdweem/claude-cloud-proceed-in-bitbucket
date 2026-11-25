# claude-cloud-proceed-in-bitbucket

Claude Code cloud sessions can only start from a GitHub repository. This small GitHub repo
is that starting point. At session start, a SessionStart hook does the following:

1. Clones a Bitbucket repository (Cloud or Data Center) into `workspace/<repo>/` using a token.
2. Optionally starts Docker.
3. Passes that repo's setup instructions, a Markdown file named by `BB_SETUP_FILE`, to Claude
   to carry out before any other work. (Optionally a `*.sh` script instead, which the hook
   runs itself before Claude starts, once per container.)

`CLAUDE.md` tells Claude to work and push in the Bitbucket checkout, not here.

## Setup

1. Push this repo to GitHub (private is fine) and connect it in Claude Code.
2. Create a Bitbucket token:
   - **Repository, project or workspace access token**: leave `BB_USER` unset (defaults to `x-token-auth`).
   - **Atlassian API token**: set `BB_USER=x-bitbucket-api-token-auth`.

   Give it read scope, plus write if Claude should push.
3. Open the cloud environment's settings (environment menu in the session title bar, then **Edit**):
   - **Environment variables**:

     | Variable | | Meaning |
     |---|---|---|
     | `BB_REPO` | required | `workspace/repo-slug` on Bitbucket Cloud, e.g. `myworkspace/my-repo` |
     | `BB_URL` | instead of `BB_REPO` | Full clone URL, for Bitbucket Data Center, e.g. `https://bitbucket.example.com/scm/proj/repo.git` |
     | `BB_TOKEN` | required for private repos | The Bitbucket token |
     | `BB_USER` | optional | Git username for the token; see step 2 |
     | `BB_SETUP_FILE` | optional | Path in the Bitbucket repo to the setup instructions, e.g. `claude/SETUP.md` |
     | `BB_BRANCH` | optional | Branch to start on. Leave it out to start on the repo's default branch and tell Claude in the session which branch to work on; all branches are fetched either way |
     | `BB_START_DOCKER` | optional | `1` to start the Docker daemon |
   - **Network access**: add `bitbucket.org` (or your Data Center host) to the allowed domains,
     plus every host your setup downloads from (JDK mirror, Maven repo, Docker registry, ...).
     Keep "Allow package managers" ticked.
4. Start a new session on this repo.

Environment variables are readable by anyone using the environment and by commands in its
sessions. Use a narrowly scoped token. The token never ends up in `.git/config` or in a
remote URL. Git reads it from the environment through a credential helper.

## Writing the setup file (in the Bitbucket repo)

The setup file is Markdown. At session start the hook passes its contents to Claude, which
carries out the steps from the repo root and verifies them before any other work. Write it
as instructions for Claude, with the commands to run and how to check they worked.

Example `claude/SETUP.md`:

````markdown
# Setup for cloud sessions

1. Install JDK 25 if `/opt/jdk25/bin/java` doesn't exist:
   ```bash
   curl -fsSL https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse -o /tmp/jdk.tgz
   mkdir -p /opt/jdk25 && tar xzf /tmp/jdk.tgz -C /opt/jdk25 --strip-components=1
   ```
   Use it via `export JAVA_HOME=/opt/jdk25 PATH=/opt/jdk25/bin:$PATH`.
2. Run `npm ci` in `frontend/`.
3. Verify: `java -version` reports 25, and `./mvnw -q -DskipTests verify` succeeds.
````

The repo's own `CLAUDE.md` is still honoured. Put general coding rules there, and setup
steps in the setup file.

Alternatively, `BB_SETUP_FILE` can point to a `.sh` script. The hook then runs it itself,
from the repo root as root, before Claude starts and once per container, with the output in
`workspace/.bootstrap.log` and a 20-minute limit. Only use that for fully scripted installs
that need no judgement.

## Troubleshooting

See `workspace/.bootstrap.log`. Usual causes:

- `could not read Username`: `BB_TOKEN` is not set in the session. Put it under
  Environment variables; a token saved only under Network secrets is not visible to the hook.
- The host is not in the allowed domains.
- `BB_USER` doesn't match the token type.
- The token has expired.

To test locally, run `BB_BOOTSTRAP_LOCAL=1 BB_REPO=... BB_TOKEN=... bash .claude/hooks/claude-cloud-proceed-in-bitbucket.sh`.
