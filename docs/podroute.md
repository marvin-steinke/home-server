# Podroute VPN Gateway

The `vpn-gateway` Argo CD Application deploys Podroute and Gluetun in
`vpn-gateway`. Every new Pod in `vpn` receives Podroute routing helpers.
Prowlarr and SABnzbd keep their existing storage, Services and Mullvad secret.
The controller and gateway must remain outside `vpn`.

## Configuration

The chart's `global.podroute` value is the canonical controller profile. Its
`network` object also supplies the gateway's `network.json`; do not maintain a
second copy. Both Podroute images are pinned to the same release's digests.
The current cluster uses CoreDNS `10.43.0.10`, `cluster.local`, and an AMD64 node.
The overlay MTU is capped at the existing WireGuard MTU of 1320.

The existing RFC1918 bypasses are retained on both clients and gateway. They
are broad security exceptions, not isolation from private networks. The
connected `172.16.1.0/24` overlay takes precedence over the `172.16.0.0/12`
bypass. Public DNS goes through WireGuard; cluster and `.local` queries go
to CoreDNS. Gluetun's firewall remains disabled because Podroute owns the
kill switch. Gateway NetworkPolicy permits VPN transport, cluster peers and
the configured private ranges, not unrestricted public egress.

Exactly one gateway may be active for this overlay. Its Deployment uses
`Recreate`, and its headless Service must resolve to one Pod IPv4 address.
`net.ipv4.ip_forward` is explicitly enabled; the node must allow that sysctl.
The helpers run as root with restricted capabilities, not privileged mode.
Native sidecars require a compatible Kubernetes version and admission policy.

Podroute 1.0.0 rejects reinvocation when Kubernetes adds service-account token
mounts to its helpers. The existing app-template consumers already set
`automountServiceAccountToken: false`; retain that setting. Diagnostic Pods in
`vpn` must set it explicitly too. Do not add token-dependent workloads to this
namespace until that controller compatibility issue is fixed.

Gateway liveness and consumer startup probes require `loc=NL` from Cloudflare's
HTTPS trace endpoint. The previous ipinfo endpoint returned HTTP 429 for the
shared VPN exit and prevented otherwise healthy applications from starting.

## Validate Changes

From the repository root:

```sh
helm dependency build apps/vpn-gateway/vpn-gateway
helm lint apps/vpn-gateway/vpn-gateway --kube-version 1.36.3
helm template vpn-gateway apps/vpn-gateway/vpn-gateway \
  --namespace vpn-gateway --kube-version 1.36.3
```

Confirm gateway and controller JSON match, the webhook selects only `vpn`,
the gateway init runs before Gluetun, and the Service remains headless.
Network/profile changes roll the gateway/controller using checksums. Existing
consumer Pods retain their injected profile: recreate them after a change.

## Feature Branch Preview

Follow `.github/skills/feature-branch-testing/SKILL.md`. Record the original
root revision and `main`'s child revision, then set `source.targetRevision` in
the feature branch to its exact name. Validate and push before running
`.github/scripts/set-argocd-revision.sh <branch>`; do not merge to deploy a
preview or start a parallel root sync. Wait for each affected child's sync
and health separately. Restore the recorded baseline before any future merge.

During maintenance, `applicationOverrides.<app>.automated: false` renders
`spec.syncPolicy.automated: null`. This is intentional: the deployed controller
continued automatic synchronization with `automated.enabled: false`. Plain
null values in Helm overrides are removed during value merging. Keep the root
paused while changing live child policies so parent self-heal cannot undo them.
Remove the temporary overrides after the controlled cutover is verified.

When returning a preview to the baseline, pause root/child reconciliation and
stop consumers before replacing the webhook and gateway. A temporary ResourceQuota
in `vpn` with `pods: "0"` prevents automatic reconciliation from creating Pods
during the admission gap. Keep it until the baseline gateway and webhook are
healthy, then remove it so consumers are recreated with the baseline helpers.
Verify consumer health and remove all temporary maintenance controls before merge.

### Preview Verification: 2026-11-02

The `podroute-migration` branch was deployed without merging its pull request.
Helm lint/render checks passed for bootstrap, gateway, Prowlarr and SABnzbd.
Live checks verified:

- Exactly one gateway endpoint, MTU 1320, and Podroute helpers on both consumers.
- Cluster/public DNS, Netherlands egress, and private LAN access.
- Public IPv4 and DNS blocked during gateway removal and VPN-transport loss;
   private bypasses stayed reachable and traffic recovered after restoration.
- IPv6 drop rules and no usable public IPv6 egress on this IPv4-only cluster.
- Selected Pod admission failed closed without the controller; unselected
   admission remained available and selected admission recovered after restart.
- Existing LoadBalancer endpoints responded, config PVCs remained bound, and
   application config/NFS mounts were writable without changing application data.

The canary and temporary firewall rules were removed after testing. Certificate
renewal itself was not forced; controller restart and subsequent TLS-backed
admission were tested. The token-mount reinvocation limitation above remains.

Preview cleanup restored the root and all child Applications to `main`
(`35f1353`) and Synced status. The operator confirmed that the baseline VPN
trust anchors are out of date, so working routing on `main` is not an acceptance
criterion for this cleanup. Prowlarr and SABnzbd startup probes were failing
after restoration; baseline VPN health must not be reported as verified.
The temporary Pod quota was removed and normal reconciliation restored.

## Initial Cutover From Angelnu

Schedule a short interruption. Verify node architecture, CoreDNS, MTU,
cert-manager/cainjector and registry access before stopping applications.
Record the old Git revision, replica counts and sync policies. Keep secret
values out of Git and logs. SSH access uses `bobby@192.168.2.117` with the
local `~/.ssh/bobby` key; stop and request operator action if sudo is needed.

1. Suspend automated sync on the root `home-server` Application, then on
   `vpn-gateway`, `prowlarr` and `sabnzbd`, before publishing the migration.
   This prevents parent self-heal from undoing the maintenance controls.
2. Commit/push the validated chart to the verified GitOps branch. Refresh
   `vpn-gateway` and selectively sync its new ConfigMap, ServiceAccount,
   controller Service/Deployment and cert-manager Issuers/Certificates through
   Argo CD. Do not start the new gateway or activate the new webhook yet.
   Use selective resource sync rather than disabling the gateway controller:
   app-template validates its volume references even during partial rendering.
   Do not create a second Helm release.
3. Wait for `Certificate/podroute-controller` Ready and the new controller
   Deployment available. Confirm the serving certificate covers
   `podroute-controller.vpn-gateway.svc`.
4. Scale Prowlarr and SABnzbd to zero and wait for their Pods to terminate.
   A temporary `pods: "0"` ResourceQuota in `vpn` guards against unexpected Pod
   creation while admission is being replaced; remove it only after the new
   fail-closed webhook is ready, before creating the canary or consumers.
   Remove `MutatingWebhookConfiguration/vpn-gateway-pod-gateway`, stop the old
   `vpn-gateway-pod-gateway-main` gateway, and wait for it to terminate before
   starting the new gateway. Never run both gateways on this overlay.
5. Sync the gateway resources through Argo CD. Verify forwarding, WireGuard,
   gateway DNS/DHCP and one headless endpoint. The controller's `/healthz`
   and the presence of `wg0` alone do not prove VPN connectivity.
6. Sync `MutatingWebhookConfiguration/podroute`; wait for cainjector to populate
   its CA bundle. It must remain fail-closed and select `vpn` only. Confirm
   exactly one active VPN mutator, then create a disposable canary in `vpn`
   and verify helper injection, cluster/public DNS and NL egress.
7. Restore the original consumer replica counts. Verify readiness, application
   access, storage and NL egress. Complete the reviewed Argo sync/prune to
   remove obsolete Angelnu resources, retaining the namespace and Mullvad
   ExternalSecret. Restore the original child sync policies, then the root's.
8. During the maintenance window, use the canary to verify public IPv4/DNS
   fail closed when WireGuard is down, private bypasses still work, IPv6
   cannot bypass, and recovery succeeds. Remove the canary and verify all
   affected Applications are Healthy/Synced. Do not test by granting an
   application network-administration privileges.

Admission changes affect CREATE only. Stopping and recreating consumer Pods
is mandatory; do not reuse old injected helpers with the replacement gateway.
The webhook's namespace-name selector and `podroute.io/routed` label must stay
aligned with the profile. No per-Pod opt-out is supported.

## Certificates And Renewal

Namespaced cert-manager Issuers own a private CA and the controller serving
certificate. Cainjector fills the webhook CA bundle from
`Certificate/podroute-controller`; the public ACME issuer is not used for
internal Service names. No private keys are stored in Git. The serving
certificate lasts 90 days and renews 30 days before expiry. The private CA
lasts ten years; CA renewal is a separate planned trust transition, not an
unattended serving-certificate renewal.

Podroute loads TLS files at startup. There is deliberately no reload operator:
after each serving-certificate renewal, restart the controller before its
previously loaded certificate expires:

```sh
kubectl -n vpn-gateway get certificate podroute-controller
kubectl -n vpn-gateway rollout restart deployment/podroute-controller
kubectl -n vpn-gateway rollout status deployment/podroute-controller --timeout=120s
```

Check certificate expiry/renewal dates regularly and schedule that restart
within the renewal window. Confirm the updated CA bundle and a successful
selected-namespace Pod CREATE after restarting. Certificate Ready alone does
not establish that the controller loaded the renewed certificate. Do not
delete the CA Secret as a renewal shortcut. Argo CD must not overwrite
cainjector's managed CA bundle.

## Rollback

Keep consumers stopped. Disable/remove the Podroute webhook, stop the new
gateway and wait for termination. Revert only migration commits using a new
Git commit, push it, and reconcile the old chart through Argo CD. Wait for
the old gateway, TLS and webhook, then recreate consumers so they receive the
old helpers. Preserve PVCs, namespaces and provider secrets. Restore replica
counts and sync policies, verify NL egress and application access, and return
all affected Applications to Healthy/Synced. Do not use a destructive Git reset
or undo unrelated changes.