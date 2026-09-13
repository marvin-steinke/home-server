---
name: bjw-s-app-template
description: "Create, modify, debug, validate, or upgrade Helm wrapper charts that depend on bjw-s app-template. Use for app-template values, controllers, containers, services, ingress, persistence, secrets, probes, and version upgrades in this repository."
argument-hint: "Describe the chart and app-template configuration needed"
---

# bjw-s App-Template

Use this skill only for wrapper charts that declare an `app-template` dependency.

## Procedure

1. Read the target `Chart.yaml` and `values.yaml`. Determine the exact resolved
   app-template version and dependency alias. Values belong below that alias
   (normally `app-template:`).
2. Run `bash .github/skills/bjw-s-app-template/scripts/fetch-docs.sh <version>`
   from the workspace root. The [helper](./scripts/fetch-docs.sh) prints the
   absolute documentation directory. It fetches the exact release on a cache
   miss and reuses it offline thereafter. Read only one to three relevant pages
   using the routes below; expand only for a concrete gap.
3. Inspect one nearby chart with the requested capability: `apps/media/bazarr/`
   for a wrapper example, `apps/media/seerr/values.yaml` for explicit mounts,
   or `apps/vpn/prowlarr/values.yaml` for VPN-specific behavior. Check
   `bootstrap/values.yaml` only when application registration is needed.
4. Make the smallest chart change that meets the request. Preserve resource
   identifiers and references between controllers, services, ingress, and
   persistence. Do not invent image tags, credentials, probe endpoints, storage
   settings, ingress/authentication, VPN, or ExternalSecret behavior.
5. For upgrades, fetch the destination version and read its relevant upgrade
   guide before changing values. Never apply newer documentation to an older pin.
6. Validate the rendered chart with its dependencies resolved, `helm lint`, and
   `helm template`. Use the target cluster's supported Kubernetes version when
   it is known.

## Topic Routes

Paths are relative to the returned directory:

- Starting point: `getting-started.md`.
- Resource options: `reference/<resource>/index.mdx`, e.g. `controllers`,
   `service`, `ingress`, `persistence`, `configmaps`, `secrets`, or `route`.
- Container and pod details: children of `reference/controllers/`.
- Environment variables and patterns: `howto/`; migrations: `upgrades/`.

Resolve directory links to `index.mdx` or `index.md`. If a release uses a
different layout, list only the relevant directory. Do not dump all documents
or the schema into context.

## Cache Rules

- Requires Bash and Git >=2.25. Source: `https://github.com/bjw-s-labs/helm-charts.git`,
   tag `app-template-<version>`. Never fall back to `main` or latest.
- Cache: `${XDG_CACHE_HOME:-$HOME/.cache}/bjw-s-app-template/<version>/`, outside
   the repository. `.cache-source` records upstream URL, tag, and commit.
- Pass an exact stable `X.Y.Z`. For a range, establish a trustworthy resolved
   version from the lock/dependency state or ask for an explicit pin. For a new
   chart, choose its dependency pin first. Do not parse YAML with grep.
- On fetch errors, report the missing version or prerequisite; do not substitute
   another release. Removing only the affected version cache explicitly allows
   a refetch. No background refresh or in-repository references are needed.
- Treat local charts as examples, not defaults. In particular, ingress, NFS,
  VPN, and authentication choices are application-specific.