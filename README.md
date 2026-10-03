## Installation

### Setup k3s

```bash
# https://docs.k3s.io/quick-start
curl -sfL https://get.k3s.io | sh -
```
optionally setup your kubectl config
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```
and set the `KUBECONFIG` env var in your shell profile
```bash
export KUBECONFIG=$HOME/.kube/config
```

### Setup NFS Server

```bash
sudo apt install nfs-kernel-server
# if you want to adjust the nfs dir, reflect the changes in the apps' yamls too
sudo mkdir -p /mnt/nfs
# populate your exports with something like this, you might want to adjust the IP range
sudo echo "/mnt/nfs 192.168.2.0/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
# and the ownership
sudo chown -R nobody:nogroup /mnt/nfs
# and the permissions as well.
sudo chmod -R 755 /mnt/nfs
# apply configuration and start service
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server
```

### Setup PostgreSQL

```bash
sudo apt install postgresql
sudo -u postgres psql
```

```sql
CREATE USER authentik WITH PASSWORD 'your_password';
CREATE DATABASE authentik OWNER authentik;
\c authentik
GRANT ALL ON SCHEMA public TO authentik;
ALTER SCHEMA public OWNER TO authentik;
\q
```

```bash
# edit postgresql.conf
sudo vim /etc/postgresql/{version}/main/postgresql.conf
# change:
listen_addresses = '*'

# edit pg_hba.conf
sudo vim /etc/postgresql/{version}/main/pg_hba.conf
# add the following line to allow connections from the k3s cluster (adjust the IP range if needed):
# host    all             all             10.42.0.0/16            scram-sha-256

sudo systemctl restart postgresql
```


### Setup Argo CD

Argo CD is managed by the local Helm wrapper at
`apps/argocd/argocd` and registered through the bootstrap chart. The wrapper
adopts the existing standard Argo CD v3.5.1 installation with upstream chart
`argo-cd` v10.4.0.

Before syncing the Authentik or Argo CD applications, create the shared OIDC
client secret in the Infisical project used by the `infisical` ClusterSecretStore.
Use the project's UUID, not its slug, and preserve an existing value so both
ExternalSecrets continue to reference the same client secret. `secrets set` is
an upsert: run the following only after confirming that
`ARGOCD_OIDC_CLIENT_SECRET` does not already exist in that project, environment,
and path.

```bash
secret="$(openssl rand -base64 48)"
infisical secrets set "ARGOCD_OIDC_CLIENT_SECRET=$secret" \
  --projectId=<infisical-project-uuid> \
  --env=default \
  --path=/ \
  --silent
unset secret
```

The secret is materialized as `argocd-oidc` in the `authentik` namespace for
the worker blueprint and in the `argocd` namespace for Argo CD. The Authentik
blueprint provisions the confidential `argocd` client with callback
`https://argocd.bobby-dev.de/auth/callback` and restricts application access to
the `akadmin` user.

Argo CD manages its own application with automated self-healing enabled, but
automatic prune and deletion are explicitly disabled. This is intentional:
review and apply all resource removal or replacement operations separately,
especially when adopting existing resources with immutable selectors. The
application uses server-side apply for this reason.

Validate the prerequisite rollout before exposing the Argo CD application:

```bash
kubectl -n authentik get externalsecret argocd-oidc
kubectl -n authentik get secret argocd-oidc
kubectl -n authentik logs deploy/authentik-worker
curl --fail https://authentik.bobby-dev.de/application/o/argocd/.well-known/openid-configuration
```

After Argo CD is reconciled, sign in at `https://argocd.bobby-dev.de` through
Authentik. Native CLI access through the public Traefik endpoint requires
gRPC-Web:

```bash
argocd login argocd.bobby-dev.de --grpc-web --sso
```

For CLI automation, the chart defines two API-only accounts. `github-actions`
can get, update, and sync only the `default/home-server` Application;
`personal-cli-admin` has full Argo CD access. After these accounts have
reconciled, use an authenticated Argo CD administrator session to issue separate
expiring tokens. The manual revision workflow reads the CI token from the GitHub
Actions repository secret `ARGOCD_AUTH_TOKEN`:

```bash
ssh -i ~/.ssh/bobby bobby@192.168.2.117 \
  'argocd account generate-token --account github-actions --expires-in 2160h --grpc-web' |
  gh secret set ARGOCD_AUTH_TOKEN --repo marvin-steinke/home-server
```

The server's authenticated Argo CD CLI issues the token, while `gh` runs on
your Mac. Do not print the token or store it in the repository. Generate the
personal token on the server separately and save its output immediately in a
password manager or macOS Keychain; it is valid for 30 days:

```bash
argocd account generate-token --account personal-cli-admin --expires-in 720h --grpc-web
```

On a Mac, `security add-generic-password -U -a personal-cli-admin -s
argocd.bobby-dev.de -w` prompts for the token without putting it in shell
history. Once stored in Keychain, use it with the local CLI:

```bash
export ARGOCD_SERVER=argocd.bobby-dev.de ARGOCD_OPTS=--grpc-web
export ARGOCD_AUTH_TOKEN="$(security find-generic-password -a personal-cli-admin -s argocd.bobby-dev.de -w)"
argocd app list
unset ARGOCD_AUTH_TOKEN
```

After the `github-actions` RBAC change has reconciled, open **Actions > Set Argo
CD revision > Run workflow** and select a trusted branch. The workflow uses
that branch as the root `home-server` Application's revision, syncs it, and
waits for it to become healthy. The workflow must be on the repository's
default branch before it appears in GitHub Actions.

For a local update, authenticate with `personal-cli-admin` or an administrator
and run from the repository root:

```bash
.github/scripts/set-argocd-revision.sh main
```

The script waits for the root Application to become synced and healthy. For the
public endpoint, set `ARGOCD_OPTS=--grpc-web` as shown above. Child Applications
continue to use the revision specified by the selected branch's
`bootstrap/values.yaml` (currently `testing`), not necessarily that branch.

Rotate the tokens before they expire: generate and verify replacements, update
the GitHub secret or personal Keychain entry, then revoke the old token IDs with
`argocd account delete-token --account <account> <token-id> --grpc-web`. An
administrator can list the token IDs with `argocd account get --account
<account> --grpc-web`.

For recovery, use the existing local Argo CD administrator access while
diagnosing Authentik, ingress, certificate, or OIDC configuration. Do not
delete the Argo CD namespace, CRDs, or Helm-managed resources as a recovery
step.

### Authentik Applications

The Authentik chart's `applications-blueprint` manages the existing Radarr,
Sonarr, Bazarr, SABnzbd, Prowlarr, and Seerr proxy applications, their
`akadmin` access bindings, and their assignments to the embedded outpost.
Argo CD remains in its separate OIDC blueprint. Proxy client credentials are
managed internally by Authentik: adopting these providers leaves their current
client IDs and secrets unchanged, while a new installation generates new ones.
No additional Infisical keys are needed for these proxy applications.

Before syncing this chart, confirm there is a restorable Authentik PostgreSQL
backup. From the repository root, validate the chart with
`helm dependency build apps/authentik/authentik`,
`helm lint apps/authentik/authentik`, and
`helm template authentik apps/authentik/authentik --namespace authentik`.
After Argo CD syncs it, check the `applications` blueprint instance and worker
logs for errors. Confirm the six applications still point to their existing
providers, the embedded outpost has all six providers, and sign-in works for
each application and Argo CD. Removing a blueprint does not undo changes it
already applied; correct or disable it before restoring affected data from the
backup.

Upon installing the cert-manager, I'm usually having some trouble with the
cainjector health at some point. A restart of the node helps, not sure why.

### Setup External Secrets Operator (ESO)
To set up ESO, the auth secret for the provider (Infisical) needs to be
created. If you choose a different provider, adjust the external-secret chart
accordingly.
```bash
kubectl create secret generic infisical-auth-credentials \
  --from-literal=clientId=<your-client-id-here> \
  --from-literal=clientSecret=<your-client-secret-here> \
  --namespace=default
```

### Bootstrap GitOps

The bootstrap chart only creates Argo CD `Application` resources, so it cannot
be the first resource applied to an empty cluster. Complete the host setup
above, then use Helm from an administration machine with cluster access.

Before issuing certificates, point the required DNS names at the Traefik entry
point and make TCP ports 80 and 443 reachable. Populate every Infisical secret
referenced by the enabled applications before their ExternalSecrets reconcile.

Install the controllers that provide the CRDs used by the Argo CD wrapper, then
verify the Infisical store before installing Argo CD:

```bash
helm dependency build apps/external-secrets/external-secrets
helm upgrade --install external-secrets apps/external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace

helm dependency build apps/cert-manager/cert-manager
helm upgrade --install cert-manager apps/cert-manager/cert-manager \
  --namespace cert-manager \
  --create-namespace

kubectl wait --for=condition=Ready clustersecretstore/infisical --timeout=5m
```

Create `ARGOCD_OIDC_CLIENT_SECRET` in Infisical as described in [Setup Argo
CD](#setup-argo-cd), then perform the one-time Argo CD installation and hand
application management to the bootstrap chart:

```bash
helm upgrade --install argocd apps/argocd/argocd \
  --namespace argocd \
  --create-namespace

helm upgrade --install home-server bootstrap \
  --namespace argocd \
  --create-namespace
```

Wait for the core applications before treating the cluster as ready:

```bash
kubectl -n argocd get applications
kubectl -n argocd get pods
kubectl -n external-secrets get pods
kubectl -n cert-manager get pods
```

From this point, make application changes through Git. Do not run a second
Helm release for an application that is already managed by its Argo CD
`Application`.

## App Setup
<img width="5320" height="1995" alt="app_setup" src="https://github.com/user-attachments/assets/3c7e0583-2047-44ec-b79b-14949cd31f31" />

## Media Setup
<img width="5320" height="3080" alt="media_setup" src="https://github.com/user-attachments/assets/45e40541-b1e6-4a54-8826-47ada30f384e" />

## Pod Gateway
<img width="5320" height="1850" alt="pod_gateway" src="https://github.com/user-attachments/assets/c7fc760d-c2ce-4b16-bc07-ae00f39d2117" />
