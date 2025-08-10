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

### Setup ArgoCD
https://argo-cd.readthedocs.io/en/stable/getting_started/

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
