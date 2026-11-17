# Server Setup

Manual preparation for the Debian home server. Complete this before the
[Kubernetes setup](kubernetes-setup.md); no host-native Authentik installation is
needed.

## Host and network

The charts currently assume:

| Setting | Value |
| --- | --- |
| Server / NFS / PostgreSQL address | `192.168.2.117` |
| LAN | `192.168.2.0/24` |
| k3s pod / service CIDRs | `10.42.0.0/16` / `10.43.0.0/16` |
| Cluster DNS | `10.43.0.10`, `cluster.local` |
| NFS data / media | `/mnt/nfs/data` / `/mnt/nfs/data/media` |
| Local application config | `/opt/cluster-configs/` |

Use a stable server address. If these settings differ, update the corresponding
[application values](../apps/), [Jellyfin PV](../apps/media/jellyfin/templates/jellyfin-pv.yaml),
and [VPN profile](../apps/vpn-gateway/vpn-gateway/values.yaml) before deploying.
The VPN configuration currently targets AMD64; check image and node compatibility.

Restrict Kubernetes API access (TCP 6443) to administration machines. Allow NFS
from cluster nodes and PostgreSQL (TCP 5432) from the cluster's actual source
addresses. Only expose intended ingress services; do not expose NFS or PostgreSQL
to the Internet. See [k3s networking requirements](https://docs.k3s.io/installation/requirements#networking)
for additional ports when adding nodes.

## 1. Install k3s

Follow the [k3s quick start](https://docs.k3s.io/quick-start). For a new server:

```bash
curl -sfL https://get.k3s.io | sh -
```

For repeatable rebuilds, record and use the tested k3s version through
`INSTALL_K3S_VERSION` rather than relying on the installer's current default.
Keep the bundled Traefik, CoreDNS, and ServiceLB enabled: the repository uses
them. The VPN needs native sidecar support and the node to permit the gateway's
`net.ipv4.ip_forward` setting; see [Podroute constraints](podroute.md#configuration).

Create a private administration kubeconfig on the server:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG="$HOME/.kube/config"
kubectl get nodes
```

Add the export to your shell profile if needed. For remote administration,
securely copy this config to your administration machine and change its API
server from `127.0.0.1` to the reachable server address covered by the API
certificate. Treat the kubeconfig as an administrator credential; never commit it.

## 2. Prepare NFS and local storage

Install the NFS server on the storage host and the client package on every
Kubernetes node (including this host):

```bash
sudo apt update
sudo apt install nfs-kernel-server nfs-common
sudo mkdir -p /mnt/nfs/data/media /mnt/nfs/data/usenet /opt/cluster-configs
sudoedit /etc/exports
```

Add this export once, adjusting the allowed network if needed:

```text
/mnt/nfs 192.168.2.0/24(rw,sync,no_subtree_check,root_squash)
```

Set ownership and write permissions on **new** media/download directories for
the configured application UID/GID (`2000:2000` for the download/*arr workloads).
Preserve ownership of restored data; do not recursively reset an existing share
to `nobody` or apply blanket permissions. Root squashing is intentional: prepare
permissions on the server rather than relying on a pod to chown the export.

```bash
sudo exportfs -ra
sudo systemctl enable --now nfs-kernel-server
sudo exportfs -v
```

The `config` StorageClass is created later by the
[local-path provisioner chart](../apps/local-path-provisioner/local-path-provisioner/values.yaml).
It stores application configuration under `/opt/cluster-configs/` with `Retain`;
NFS stores shared media/downloads. Back up both locations. Restoring files alone
does not recreate PV/PVC binding metadata; plan volume recovery before a rebuild.

## 3. Prepare PostgreSQL for Authentik

Install PostgreSQL on `192.168.2.117`:

```bash
sudo apt install postgresql
sudo -u postgres psql
```

For a **new** installation, create the database and set the role password
interactively:

```sql
CREATE ROLE authentik WITH LOGIN;
CREATE DATABASE authentik OWNER authentik;
\password authentik
\connect authentik
GRANT ALL ON SCHEMA public TO authentik;
ALTER SCHEMA public OWNER TO authentik;
\q
```

Save that same password as Infisical `POSTGRESQL_PW`; see the
[secret inventory](kubernetes-setup.md#secrets-and-creation-order).
For an existing deployment, reuse its database, password, and `AUTHENTIK_KEY`.
Confirm a restorable PostgreSQL backup before making changes.

In `/etc/postgresql/<installed-major-version>/main/postgresql.conf`, set:

```conf
listen_addresses = 'localhost,192.168.2.117'
```

In the corresponding `pg_hba.conf`, allow only the Authentik database and role
from the pod CIDR:

```conf
host    authentik    authentik    10.42.0.0/16    scram-sha-256
```

Keep the firewall aligned with that rule. If traffic is source-NATed, inspect the
actual source address and authorize only the required nodes rather than opening
the database to every address.

```bash
sudo systemctl restart postgresql
sudo systemctl enable postgresql
sudo systemctl is-active postgresql
sudo -u postgres pg_isready -h 192.168.2.117 -p 5432
```

`pg_isready` checks the listener, not application authentication. After deployment,
check Authentik's database connection and migration logs as well.

## Handoff

Confirm nodes are Ready, the NFS export is reachable from each node, and
PostgreSQL is accepting connections. Then continue with
[Kubernetes setup](kubernetes-setup.md). Host data restoration, backups, firewall
rules, and external provider accounts remain outside Kubernetes IaC.
