# Argo CD Operations

For installation and the root `home-server` Application, follow
[Kubernetes setup](kubernetes-setup.md#first-install-bootstrap). Argo CD manages
its own [wrapper chart](../apps/argocd/argocd/) after bootstrap.

## Login

Authentik provides SSO at `https://argocd.bobby-dev.de`. Public CLI access through
Traefik requires gRPC-Web:

```bash
argocd login argocd.bobby-dev.de --grpc-web --sso
```

The shared OIDC secret must exist in Infisical before both consumers reconcile;
see the [secret inventory](kubernetes-setup.md#secrets-and-creation-order).
For SSO problems, use existing local administrator access or core-mode access
with an authorized kubeconfig while diagnosing Authentik, DNS, ingress, TLS, and
OIDC. Do not delete the namespace, CRDs, or core Secrets as a recovery step.

## Self-management safeguards

The Argo CD child Application self-heals, but automatic prune and deletion are
disabled and it has no resource-deletion finalizer. Review all resource
removal/replacement separately, especially immutable selector changes during
adoption. Server-side apply does not bypass immutability. Other children and the
root normally have automated pruning enabled.

## Automation and personal tokens

The chart defines two API-only accounts:

| Account | Access | Token destination |
| --- | --- | --- |
| `github-actions` | Get, update, and sync only `default/home-server` | GitHub Actions repository secret `ARGOCD_AUTH_TOKEN` |
| `personal-cli-admin` | Full Argo CD access | Personal password manager or macOS Keychain |

Only generate tokens **after** the accounts/RBAC reconcile, using an
authenticated Argo CD administrator session. These tokens are optional for
bootstrap and are not Infisical credentials.

For the [manual revision workflow](../.github/workflows/set-argocd-revision.yaml),
the server's authenticated CLI can issue a 90-day CI token directly into the
GitHub secret (`gh` runs on your Mac):

```bash
(
  set -o pipefail
  ssh -i ~/.ssh/bobby bobby@192.168.2.117 \
    'argocd account generate-token --account github-actions --expires-in 2160h --grpc-web' |
    gh secret set ARGOCD_AUTH_TOKEN --repo marvin-steinke/home-server
)
```

Confirm token generation and GitHub upload both succeed; never print the token or
commit it. Generate a separate 30-day personal token in a private terminal and
save it immediately:

```bash
argocd account generate-token --account personal-cli-admin --expires-in 720h --grpc-web
```

On macOS, `security add-generic-password -U -a personal-cli-admin -s
argocd.bobby-dev.de -w` prompts for it without putting it in shell history.
Use the stored token locally:

```bash
export ARGOCD_SERVER=argocd.bobby-dev.de ARGOCD_OPTS=--grpc-web
export ARGOCD_AUTH_TOKEN="$(security find-generic-password -a personal-cli-admin -s argocd.bobby-dev.de -w)"
argocd app list
unset ARGOCD_AUTH_TOKEN
```

Rotate before expiry: generate and verify replacements, update GitHub/Keychain,
then revoke old token IDs with `argocd account delete-token --account <account>
<token-id> --grpc-web`. An administrator can list IDs with `argocd account get
--account <account> --grpc-web`.

## Revision changes

In **Actions > Set Argo CD revision > Run workflow**, select a trusted branch.
The workflow must exist on the default branch to appear in Actions. It changes
the root Application revision and waits for sync/health; automated sync applies
the change.

For the same operation locally, authenticate as `personal-cli-admin` or an
administrator and run from the repository root:

```bash
.github/scripts/set-argocd-revision.sh main
```

For the public endpoint, set `ARGOCD_OPTS=--grpc-web`. Child Applications use
`source.targetRevision` in the selected branch's
[bootstrap values](../bootstrap/values.yaml), not necessarily the root's branch.
Wait for affected children separately.

For a feature preview, follow the
[feature-branch testing procedure](../.github/skills/feature-branch-testing/SKILL.md).
Record the original root/child revisions, validate and push the branch, deploy
without merging, then restore and verify the recorded baseline. Never run a
second root sync in parallel.
