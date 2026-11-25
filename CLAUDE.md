# claude-cloud-proceed-in-bitbucket

This repository is a launcher. The real project is a Bitbucket repository that a
SessionStart hook clones into `workspace/<repo-name>/`; the hook's message at the start of
the session says where it is and whether setup succeeded.

- By default, work, build, commit and push inside `workspace/<repo-name>/`, pushing to
  Bitbucket (`origin` there). Never commit `workspace/` to this launcher repo.
- The hook leaves the Bitbucket repo on the branch it reports (`BB_BRANCH` if set, else the
  default branch); all remote branches are fetched. Work on the branch the user asks for,
  switching to it or creating it as they say. If they have not said which branch, ask
  before committing.
- Change this launcher repo itself only when the user explicitly asks for it. When it is
  unclear which repository a change belongs in, ask.
- `BB_SETUP_FILE` names the Bitbucket repo's setup instructions, a Markdown file whose
  contents the hook passes on at session start. Carry out those instructions and verify them
  before any other work. (If it names a `.sh` script instead, the hook already ran it and
  reports whether it succeeded.)
- If the hook reports a failure (clone or setup), tell the user, and do not guess at the
  repository's contents. The details are in `workspace/.bootstrap.log`, which holds the
  output of the clone, fetch and setup script.
- Read the Bitbucket repository's own `CLAUDE.md` (if any) and follow it.
- Git authentication uses a credential helper that reads `BB_TOKEN` from the environment.
  Never print, echo, log or commit the token, and never put it in a remote URL.
