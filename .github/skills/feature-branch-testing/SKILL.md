---
name: feature-branch-testing
description: "Create, validate, manually deploy, and clean up one feature branch preview in the shared home-server cluster"
argument-hint: "Describe the feature to test and the current branch state"
---

# Feature Branch Testing

Use this skill to test one feature branch at a time in the shared Kubernetes
cluster. Work from the repository root. The root `home-server` Application's
revision is changed by `.github/scripts/set-argocd-revision.sh`; child
Applications use `source.targetRevision` from the selected branch's
`bootstrap/values.yaml`. Both must point at the feature branch for a full
preview.

## Before Starting

Coordinate access to the single shared preview lane. Check the live root
revision and health with `argocd app get home-server`. Record its configured
target revision (the branch, not the synced commit SHA) and the original
`source.targetRevision` on `main` (not the current feature branch) for cleanup.
If another preview is active or the baseline is unclear, stop and coordinate
before changing the cluster.

Have `helm` and an authenticated Argo CD CLI with administrator or
`personal-cli-admin` permissions available. For the public endpoint, set
`ARGOCD_OPTS=--grpc-web`; see [the README](../../../README.md) for login and
Keychain-backed token setup. Never put tokens in commands, commits, or skill
files.

## Branch Preparation

Create a branch whose name is the feature name itself. Do not add a
`feature/`, `fix/`, or other category prefix; the exact branch name becomes
the Argo CD Git revision.

```bash
git switch main
git pull --ff-only
git switch -c <feature-name>
```

Set `source.targetRevision` in `bootstrap/values.yaml` to the exact branch
name. Keep the change on the feature branch and commit it with the feature;
the root Application will read this value from the remote branch:

```yaml
source:
  targetRevision: <feature-name>
```

## Validate And Preview

Run `helm lint bootstrap` and `helm template home-server bootstrap`; inspect
the rendered child Applications' `targetRevision` values. Lint and render any
changed application charts as well. Push the committed feature branch before
switching Argo CD to it.

From the repository root, use the script (not GitHub Actions or a manual
`argocd app set` command):

```bash
.github/scripts/set-argocd-revision.sh <feature-name>
```

The script sets, syncs, and waits for the root Application. It does not wait
for child Applications. Check affected children with
`argocd app get <application>` to confirm their target revision, then run
`argocd app wait <application> --sync --health --timeout 900` for each affected
child. Investigate an unhealthy or out-of-sync child before accepting the
preview.

## Cleanup Before Merge

Restore the recorded baseline before merging, even if the preview fails:

1. On the feature branch, restore `bootstrap/values.yaml`'s
  `source.targetRevision` to its original value from `main` (normally
  `main`), then commit and push that change. Do not silently overwrite a
  different baseline.
2. Run `.github/scripts/set-argocd-revision.sh <original-root-revision>` to
  return the root Application to the revision recorded before the preview
  (normally `main`).
3. Check `argocd app get home-server` and the affected child Applications;
  wait for their sync and health as above. Do not merge until the preview
  revision is no longer live and the baseline is healthy. If restoration
  fails, investigate before starting another preview.