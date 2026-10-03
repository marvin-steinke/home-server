# Authentik

## Setup Overview

This repository runs Authentik in Kubernetes and uses PostgreSQL on the home
server as its external database. Infisical supplies the persistent Authentik
key, database password, and Argo CD OIDC client secret through External Secrets.
Argo CD deploys the local Helm wrapper chart; Traefik exposes Authentik at
`https://authentik.bobby-dev.de`. The Authentik worker loads two mounted
blueprints: one configures Argo CD OIDC, and the other manages the six media
proxy applications and their embedded-outpost membership.

The server-level steps below prepare PostgreSQL; they do not install a second,
host-native Authentik instance. General k3s, NFS, External Secrets Operator,
and GitOps bootstrap instructions remain in the [root README](../README.md).

## Server-Level Installation

Run these steps on the home server that hosts PostgreSQL. The chart currently
connects to `192.168.2.117`; keep that address and the PostgreSQL listener,
firewall, and `pg_hba.conf` rules aligned. The examples assume the default k3s
pod CIDR `10.42.0.0/16`; adjust it if the cluster uses another range.

Install PostgreSQL and create the Authentik role and database:

```bash
sudo apt update
sudo apt install postgresql
sudo -u postgres psql
```

In the PostgreSQL prompt, create the role and database, set the role password
interactively, then grant schema access:

```sql
CREATE ROLE authentik WITH LOGIN;
CREATE DATABASE authentik OWNER authentik;
\password authentik
\connect authentik
GRANT ALL ON SCHEMA public TO authentik;
ALTER SCHEMA public OWNER TO authentik;
\q
```

Store the same password entered by `\password` in Infisical as `POSTGRESQL_PW`.
Do not put the password in Git or a shell command. For an existing Authentik
installation, preserve its current database password and `AUTHENTIK_KEY`.

Configure PostgreSQL to listen on the server interface used by the cluster. In
`/etc/postgresql/<installed-major-version>/main/postgresql.conf`, set:

```conf
listen_addresses = 'localhost,192.168.2.117'
```

In `/etc/postgresql/<installed-major-version>/main/pg_hba.conf`, allow the
cluster pod CIDR to connect to only this database and role:

```conf
host    authentik    authentik    10.42.0.0/16    scram-sha-256
```

Ensure the host firewall and network path permit TCP port `5432` from the
cluster, then restart and check PostgreSQL:

```bash
sudo systemctl restart postgresql
sudo systemctl enable postgresql
sudo systemctl is-active postgresql
sudo -u postgres pg_isready -h 192.168.2.117 -p 5432
```

Before changing an existing deployment or adopting existing Authentik objects,
confirm there is a recent, restorable PostgreSQL backup. This guide does not
replace the host's backup and restore procedure.

## Kubernetes-Level Installation

### Prerequisites

1. Complete the existing [k3s and network setup](../README.md#installation). DNS
   for `authentik.bobby-dev.de` must resolve to Traefik, and ports 80 and 443
   must be reachable for the configured ingress and certificate issuer.
2. Install the External Secrets Operator and cert-manager using the
  [controller steps in Bootstrap GitOps](../README.md#bootstrap-gitops)
   and confirm the `infisical` ClusterSecretStore is Ready. The `letsencrypt`
   ClusterIssuer must also be Ready.
3. In the Infisical project used by that ClusterSecretStore, make sure these
   keys exist in the configured environment and path:
   - `AUTHENTIK_KEY`: a stable, high-entropy Authentik secret key. Preserve it
     for an existing installation; changing it can invalidate encrypted data.
   - `POSTGRESQL_PW`: the password for the `authentik` PostgreSQL role above.
   - `ARGOCD_OIDC_CLIENT_SECRET`: the shared confidential client secret used
     by the Authentik Argo CD blueprint and the Argo CD application.

  If `ARGOCD_OIDC_CLIENT_SECRET` does not already exist, create it once using
  the Infisical project UUID (not its slug), the `default` environment, and
  root path. Do not rerun this upsert over an existing value:

   ```bash
   secret="$(openssl rand -base64 48)"
   infisical secrets set "ARGOCD_OIDC_CLIENT_SECRET=$secret" \
     --projectId=<infisical-project-uuid> \
     --env=default \
     --path=/ \
     --silent
   unset secret
   ```

   Store `AUTHENTIK_KEY` and `POSTGRESQL_PW` in the same Infisical project,
   environment, and path expected by the `infisical` ClusterSecretStore. Do not
   print or commit secret values.

### Install and Sync

The `apps/authentik/authentik` wrapper chart pins upstream Authentik
`2025.12.4`. Its values configure the external PostgreSQL host, Traefik ingress,
worker secret environment, and the two blueprint ConfigMaps. The
`authentik-external` ExternalSecret maps `AUTHENTIK_KEY` and `POSTGRESQL_PW` to
`authentik-external`; the `argocd-oidc` ExternalSecret supplies
`ARGOCD_OIDC_CLIENT_SECRET` to the Authentik worker. The Argo CD wrapper also
creates `argocd-oidc` in the `argocd` namespace for the Argo CD server.
The `argocd` blueprint provisions a confidential client with callback
`https://argocd.bobby-dev.de/auth/callback` and restricts application access to
the `akadmin` user.

From the repository root, build and validate the wrapper chart before syncing:

```bash
helm dependency build apps/authentik/authentik
helm lint apps/authentik/authentik
helm template authentik apps/authentik/authentik --namespace authentik
```

For initial cluster setup, first complete the root README's
[GitOps bootstrap](../README.md#bootstrap-gitops). That bootstrap registers the
`authentik` child Application in the `authentik` namespace. Sync and manage it
through the existing Argo CD Application; do not install a second Helm release
for Authentik. For an existing cluster, sync the same `authentik` Application
after the chart change is committed and available to its configured revision.

### Verify Installation

Check that External Secrets resolved, the workloads are ready, and the worker
applied both blueprints:

```bash
kubectl -n authentik get externalsecret,secret
kubectl -n argocd get externalsecret argocd-oidc
kubectl -n authentik get pods
kubectl -n authentik logs deploy/authentik-worker --since=30m | grep -Ei 'blueprint|error'
curl --fail https://authentik.bobby-dev.de/application/o/argocd/.well-known/openid-configuration
```

In the Authentik admin interface, confirm the `argocd` and `applications`
blueprint instances are successful. Confirm the six proxy applications point
to their providers and are assigned to the embedded outpost. Complete an Argo CD
OIDC sign-in and test sign-in to each proxy application. For an existing
installation, compare application/provider identities with the pre-sync state;
blueprints match applications by slug and providers by name to adopt them rather
than create duplicates.

## Blueprint Operations

The `applications` blueprint manages Radarr, Sonarr, Bazarr, SABnzbd, Prowlarr,
and Seerr, their `akadmin` bindings, and their embedded-outpost assignments.
The separate `argocd` blueprint manages Argo CD's OIDC provider and application.
Proxy provider client credentials are managed by Authentik. Matching existing
provider names adopts the providers without rotating their client IDs or
secrets; deleting and recreating a provider generates new credentials. No
additional Infisical keys are needed for these proxy applications.

Removing a blueprint does not undo changes it already applied. Before deleting
or changing Authentik data, confirm a restorable database backup and review the
objects the blueprint manages. To force a reapply after deleting an object,
queue the mounted blueprint directly; ordinary discovery skips an unchanged
file. This command reapplies the full six-application blueprint, not only the
deleted application's entries:

```bash
kubectl -n authentik exec deploy/authentik-worker -- ak shell -c '
from authentik.blueprints.models import BlueprintInstance
from authentik.blueprints.v1.tasks import apply_blueprint

instance = BlueprintInstance.objects.get(
    path="mounted/cm-applications-blueprint/applications.yaml"
)
message = apply_blueprint.send(instance.pk)
print("queued", message.message_id)
'
```

Wait for the `applications` blueprint instance to return to `successful` and
check worker logs before considering recovery complete. A deleted object is
created anew and may receive a new database ID.
