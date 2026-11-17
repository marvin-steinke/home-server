# Podroute VPN Gateway

The `vpn-gateway` Application deploys Podroute and Gluetun in `vpn-gateway`;
Podroute injects routing helpers into new Pods in `vpn` (Prowlarr and SABnzbd).
The controller/gateway must stay outside that namespace.

For initial deployment, follow [Kubernetes setup](kubernetes-setup.md). Populate
the [WireGuard secrets](kubernetes-setup.md#secrets-and-creation-order) before the
gateway starts; cert-manager creates the internal TLS Secrets automatically.

## Configuration

- [global.podroute](../apps/vpn-gateway/vpn-gateway/values.yaml) is the canonical
  profile and supplies the gateway's `network.json`. Keep controller/helper
  images on matching release digests; do not maintain a second network config.
- The profile assumes AMD64, CoreDNS `10.43.0.10`, `cluster.local`, and MTU 1320.
  Public DNS uses WireGuard; cluster and `.local` queries use CoreDNS.
- RFC1918 bypasses are intentional broad security exceptions, not private-network
  isolation. The `172.16.1.0/24` overlay takes precedence over the
  `172.16.0.0/12` bypass.
- Gluetun's firewall is disabled because Podroute owns the kill switch. Gateway
  NetworkPolicy permits VPN transport, cluster peers, and configured private
  ranges, not unrestricted public egress.
- Exactly **one gateway** may be active. Its Deployment uses `Recreate`; its
  headless Service must resolve to one Pod IPv4 address. The node must allow
  `net.ipv4.ip_forward`; native sidecars require a compatible Kubernetes version
  and admission policy. Helpers run as root with restricted capabilities, not
  privileged mode.
- Podroute 1.0.0 rejects reinvocation after service-account token mounts are added
  to its helpers. Retain `automountServiceAccountToken: false` on consumers and
  diagnostic Pods in `vpn`; do not add token-dependent workloads there until
  this compatibility issue is fixed.
- Gateway liveness and consumer startup probes require `loc=NL` from Cloudflare's
  HTTPS trace endpoint. The previous ipinfo check hit shared-exit rate limits.

## Validate Changes

From the repository root, using the target Kubernetes version:

```sh
helm dependency build apps/vpn-gateway/vpn-gateway
helm lint apps/vpn-gateway/vpn-gateway --kube-version 1.36.3
helm template vpn-gateway apps/vpn-gateway/vpn-gateway \
  --namespace vpn-gateway --kube-version 1.36.3
```

Confirm controller/gateway JSON match, the webhook selects only `vpn`, the gateway
init precedes Gluetun, and the Service is headless. Profile changes roll the
gateway/controller through checksums; recreate existing consumers to receive the
updated injected profile. Admission changes affect CREATE only.

## Verification

Require all of the following after deployment or a routing change:

- One gateway endpoint and a healthy gateway/controller; certificate Ready and
  the webhook CA bundle populated.
- Helpers injected into recreated Prowlarr/SABnzbd Pods, with MTU 1320.
- Working cluster/public DNS, Netherlands public egress, and intended private LAN
  access. A healthy `/healthz` or an existing `wg0` alone does not prove routing.
- Bound config PVCs, writable config/NFS mounts, and working application endpoints.

During a controlled maintenance window, use a disposable, unprivileged canary
with the same token-mount setting in `vpn` to verify public IPv4/DNS fail closed
on gateway removal and VPN-transport loss, private bypasses remain usable, IPv6
cannot bypass, and traffic recovers after restoration. Also test that selected
Pod admission fails closed without the controller while unselected admission
continues. Remove the canary and all temporary controls afterward; do not grant
an application network-administration privileges for testing.

## Maintenance and migration

For feature previews, follow the
[feature-branch procedure](../.github/skills/feature-branch-testing/SKILL.md):
record root/child baselines, set the branch's child revision explicitly, validate
and push, deploy without merging, then restore and verify the baseline.

For an Angelnu-to-Podroute cutover or equivalent webhook/gateway replacement:

1. Record revisions, replicas, and policies. Pause root auto-sync **before**
   pausing affected children so parent self-heal cannot undo maintenance controls.
2. Sync the new ConfigMap, controller ServiceAccount/Service/Deployment and
   cert-manager Issuers/Certificates first, without starting the replacement
   gateway or enabling its webhook. Wait for the controller and serving
   certificate, including the `podroute-controller.vpn-gateway.svc` SAN.
3. Stop consumers and wait for termination. A temporary `pods: "0"` ResourceQuota
   in `vpn` prevents new Pods during the admission gap. Remove the old webhook,
   stop the old gateway, and wait before starting the replacement; never run both.
4. Verify the replacement gateway, forwarding, DNS/DHCP, WireGuard, and one
   endpoint. Sync the new fail-closed webhook and wait for cainjector's CA bundle.
5. Confirm exactly one VPN mutator. Once the webhook/gateway are healthy, remove
   the quota, test a canary, then recreate consumers and perform routing checks.
6. Review removal of obsolete resources explicitly, preserving the namespace,
   Mullvad Secret, and PVCs. Restore child policies first, then root; remove all
   temporary controls and require affected Applications Healthy/Synced.

Use selective resource sync for staging, not disabling the gateway controller:
app-template validates volume references even during partial rendering. Do not
create a second Helm release.

During maintenance, `applicationOverrides.<app>.automated: false` renders
`spec.syncPolicy.automated: null`. This is intentional: the deployed controller
continued syncing with `automated.enabled: false`, while plain null Helm values
are removed during merging. Remove temporary overrides after verification.

Historical preview checks covered routing, fail-closed behavior, storage and
admission recovery; they did not force certificate renewal. The baseline restored
after that preview had expired VPN trust anchors and failing consumer startup
probes. Neither that history nor a Synced revision proves current VPN health;
run the checks above for the deployed configuration.

## Certificates and renewal

Namespaced cert-manager Issuers own the private CA and controller certificate;
the public ACME issuer is not used for internal Service names. Cainjector fills
the webhook CA bundle from `Certificate/podroute-controller`. Argo CD must not
overwrite that managed bundle.

The serving certificate lasts 90 days and renews 30 days before expiry. Podroute
loads TLS files only at startup; after each renewal, restart it before the loaded
certificate expires:

```sh
kubectl -n vpn-gateway get certificate podroute-controller
kubectl -n vpn-gateway rollout restart deployment/podroute-controller
kubectl -n vpn-gateway rollout status deployment/podroute-controller --timeout=120s
```

Check renewal/expiry dates regularly. Verify the CA bundle and a successful
selected-namespace Pod CREATE after restarting: Certificate Ready alone does
not prove the controller loaded it. The private CA lasts ten years; CA renewal
is a separate planned trust transition. Do not delete the CA Secret as a shortcut.

## Rollback

Pause reconciliation and stop consumers. Disable/remove the replacement webhook,
stop its gateway, then revert only the relevant commits using a new Git commit.
Reconcile the baseline through Argo CD; wait for its gateway, TLS, and webhook,
then recreate consumers to get baseline helpers. Preserve PVCs, namespaces and
provider secrets. Restore child policies before root, remove maintenance controls,
and verify routing and application health. Do not use a destructive Git reset or
undo unrelated changes.
