# Authentik

## Setup Overview

This repository runs Authentik in Kubernetes and uses PostgreSQL on the home
server as its external database. Infisical supplies the persistent Authentik
key, database password, and Argo CD OIDC client secret through External Secrets.
Argo CD deploys the local Helm wrapper chart; Traefik exposes Authentik at
`https://authentik.bobby-dev.de`. The Authentik worker loads eight blueprint
files from one ConfigMap: one configures Argo CD OIDC, one manages each of the
six media proxy applications, and one manages their shared embedded-outpost
membership. Source files use `.yml`; ConfigMap keys use `.yaml`, the suffix the
upstream chart discovers.

## Installation

1. Prepare the database using [server setup](server-setup.md#3-prepare-postgresql-for-authentik).
2. Follow [Kubernetes setup](kubernetes-setup.md), including its ordered
   [secret prerequisites](kubernetes-setup.md#secrets-and-creation-order).
   Authentik needs `AUTHENTIK_KEY`, `POSTGRESQL_PW`, and
   `ARGOCD_OIDC_CLIENT_SECRET` before its workloads reconcile.
3. Let the existing `authentik` Argo CD Application deploy the chart; do not
   install a second Helm release. For a new instance, complete
   [initial setup](https://docs.goauthentik.io/install-config/install/kubernetes/#access-authentik)
   at `https://authentik.bobby-dev.de/if/flow/initial-setup/` and secure the
   `akadmin` account.

Preserve the current database password, `AUTHENTIK_KEY`, and OIDC secret on
upgrades. Confirm a restorable PostgreSQL backup before adopting or changing
existing objects.

### Chart and OIDC

The [wrapper chart](../apps/authentik/authentik/Chart.yaml) pins the upstream
Authentik version. Its values configure the external PostgreSQL host, Traefik ingress,
worker secret environment, and one ConfigMap containing all eight blueprint
files. The `authentik-external` ExternalSecret maps `AUTHENTIK_KEY` and
`POSTGRESQL_PW` to `authentik-external`; the `argocd-oidc` ExternalSecret
supplies `ARGOCD_OIDC_CLIENT_SECRET` to the Authentik worker. The Argo CD
wrapper also creates `argocd-oidc` in the `argocd` namespace for the Argo CD
server.
The `argocd-oidc` blueprint provisions a confidential client with callback
`https://argocd.bobby-dev.de/auth/callback` and restricts application access to
the `akadmin` user.

From the repository root, build and validate the wrapper chart before syncing:

```bash
helm dependency build apps/authentik/authentik
helm lint apps/authentik/authentik
helm template authentik apps/authentik/authentik --namespace authentik
```

Commit chart changes to the Application's configured revision and sync that
Application through Argo CD.

## Verify Installation

Check that External Secrets resolved, the workloads are ready, and the worker
applied all eight blueprints:

```bash
kubectl -n authentik get externalsecret,secret
kubectl -n argocd get externalsecret argocd-oidc
kubectl -n authentik wait --for=condition=Ready \
  externalsecret/authentik-external externalsecret/argocd-oidc --timeout=5m
kubectl -n argocd wait --for=condition=Ready externalsecret/argocd-oidc --timeout=5m
kubectl -n authentik rollout status deployment/authentik-server --timeout=5m
kubectl -n authentik rollout status deployment/authentik-worker --timeout=5m
kubectl -n authentik get pods
kubectl -n authentik logs deploy/authentik-worker --since=30m | grep -Ei 'blueprint|error'
curl --fail https://authentik.bobby-dev.de/application/o/argocd/.well-known/openid-configuration
```

In the Authentik admin interface, confirm the `argocd-oidc`, `radarr`, `sonarr`,
`bazarr`, `sabnzbd`, `prowlarr`, `seerr`, and `embedded-outpost` blueprint
instances are successful. Confirm the six proxy applications point to their
providers and are assigned to the embedded outpost. Complete an Argo CD OIDC
sign-in and test sign-in to each proxy application. For an existing
installation, compare application/provider identities with the pre-sync state;
blueprints match applications by slug and providers by name to adopt them rather
than create duplicates.

## Blueprint Operations

The chart stores source blueprints under
`apps/authentik/authentik/blueprints/` and renders them as `.yaml` keys in the
`authentik-blueprints` ConfigMap. The `argocd-oidc` blueprint manages Argo CD's
OIDC provider, application, and access policy. Each media application has its
own blueprint (`radarr`, `sonarr`, `bazarr`, `sabnzbd`, `prowlarr`, or `seerr`)
for its proxy provider, application, and `akadmin` binding. The
`embedded-outpost` blueprint applies all six media blueprints before assigning
their providers to the embedded outpost.

### Application Icons

The seven dashboard application icons are stored in
`apps/authentik/authentik/icons/` and packaged into the `authentik-icons`
ConfigMap. They come from the [Homarr Labs dashboard-icons
repository](https://github.com/homarr-labs/dashboard-icons/tree/adca944175c9a3eb0471f78a4da87f237476d585/svg)
at commit `adca944175c9a3eb0471f78a4da87f237476d585` under the upstream
[Apache-2.0 license](https://github.com/homarr-labs/dashboard-icons/blob/adca944175c9a3eb0471f78a4da87f237476d585/LICENSE).

The chart mounts the ConfigMap read-only at
`/data/media/public/icons` in both the server and worker. Application
blueprints refer to each file with a relative `meta_icon` path such as
`icons/radarr.svg`. To update an icon, replace its SVG in the chart's `icons/`
directory and sync the Authentik Argo CD application. These files are
read-only; managing uploads through Authentik's Files interface would require
separate writable persistent media storage.

Proxy provider client credentials are managed by Authentik. Matching existing
provider names adopts the providers without rotating their client IDs or
secrets; application slugs are also preserved. Removing the old combined
blueprint files does not undo objects they applied. No additional Infisical
keys are needed for these proxy applications.

Before deleting or changing Authentik data, confirm a restorable database
backup and review the objects the blueprint manages. To force a reapply after
deleting an object, queue the corresponding mounted blueprint directly;
ordinary discovery skips an unchanged file. For example, this reapplies only
Radarr's provider, application, and binding:

```bash
kubectl -n authentik exec deploy/authentik-worker -- ak shell -c '
from authentik.blueprints.models import BlueprintInstance
from authentik.blueprints.v1.tasks import apply_blueprint

instance = BlueprintInstance.objects.get(
  path="mounted/cm-authentik-blueprints/radarr.yaml"
)
message = apply_blueprint.send(instance.pk)
print("queued", message.message_id)
'
```

Use `argocd.yaml`, `sonarr.yaml`, `bazarr.yaml`, `sabnzbd.yaml`,
`prowlarr.yaml`, or `seerr.yaml` to reapply another application. Reapplying
`embedded-outpost.yaml` reapplies its six application dependencies before
updating outpost membership. Wait for the corresponding blueprint instance to
return to `successful` and check worker logs before considering recovery
complete. A deleted object is created anew and may receive a new database ID.
