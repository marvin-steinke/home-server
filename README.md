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

### Setup ArgoCD
https://argo-cd.readthedocs.io/en/stable/getting_started/
Upon installing the cert-manager, I'm usually having some trouble with the cainjector health at
some point. A restart of the node helps, not sure why.

## Pod Gateway
<img width="5320" height="1850" alt="pod_gateway" src="https://github.com/user-attachments/assets/c7fc760d-c2ce-4b16-bc07-ae00f39d2117" />

## App Setup
<img width="5320" height="1995" alt="app_setup" src="https://github.com/user-attachments/assets/3c7e0583-2047-44ec-b79b-14949cd31f31" />

```bash
kubectl create secret generic infisical-auth-credentials \
  --from-literal=clientId=<your-client-id-here> \
  --from-literal=clientSecret=<your-client-secret-here> \
  --namespace=default
```

## Media Setup
<img width="5320" height="3080" alt="media_setup" src="https://github.com/user-attachments/assets/45e40541-b1e6-4a54-8826-47ada30f384e" />
