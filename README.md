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

For recovery, use the existing local Argo CD administrator access while
diagnosing Authentik, ingress, certificate, or OIDC configuration. Do not
delete the Argo CD namespace, CRDs, or Helm-managed resources as a recovery
step.

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
