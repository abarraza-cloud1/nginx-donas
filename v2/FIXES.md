# Fixes Applied — Before / After

> All changes tracked here. Each fix references the bug ID from `BUGS.md`.  
> Fixed files are in the same relative paths as the originals.

---

## FIX-01 — `exit 1` → `exit 0` for missing XC secrets

**Bug:** BUG-01  
**Files changed:**
- `v2/.github/workflows/nginx-plus-ec2.yml`
- `v2/.github/workflows/ec5-plus.yml`

**Before:**
```bash
if [[ -z "${XC_API_P12_FILE:-}" || -z "${XC_API_URL:-}" || -z "${VES_P12_PASSWORD:-}" ]]; then
  echo "Missing one or more required secrets: XC_API_P12_FILE, XC_API_URL, XC_P12_PASSWORD" >&2
  exit 1
fi
```

**After:**
```bash
if [[ -z "${XC_API_P12_FILE:-}" || -z "${XC_API_URL:-}" || -z "${VES_P12_PASSWORD:-}" ]]; then
  echo "WARNING: XC_API_P12_FILE, XC_API_URL or XC_P12_PASSWORD not set." >&2
  echo "Skipping NGINX One Console policy sync. Deployment will continue without it." >&2
  exit 0
fi
```

**Why:** The NGINX One Console integration is optional — it uploads the WAF policy to F5 XC  
cloud for centralised management. If the user doesn't have an XC account, the workflow must  
still be able to deploy NGINX Plus + NAP WAF on the EC2 instance.  
The destroy workflow already used `exit 0` for this check; the deploy now matches it.

---

## FIX-02 — Correct GPG key URL for NGINX Plus repo

**Bug:** BUG-02  
**File changed:** `v2/nginx-plus-one-vm/scripts/install-nginx-plus.sh`

**Before:**
```bash
curl -fsSL https://nginx.org/keys/nginx_signing.key | \
  sudo gpg --yes --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
```

**After:**
```bash
curl -fsSL https://cs.nginx.com/static/keys/nginx_signing.key | \
  sudo gpg --yes --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
```

**Why:** `pkgs.nginx.com/plus` and `pkgs.nginx.com/app-protect` are signed by the key  
hosted at `cs.nginx.com`, not the one at `nginx.org`. Using the wrong key causes every  
`apt-get install nginx-plus app-protect` to fail with a GPG signature error.

---

## FIX-03 — Dynamic SSH CIDR (runner IP, not 0.0.0.0/0)

**Bug:** BUG-04  
**Files changed:**
- `v2/.github/workflows/nginx-plus-ec2.yml`
- `v2/.github/workflows/ec5-plus.yml`

**Before (two places per file):**
```bash
# "Set dynamic vars" step
echo "SSH_CIDR=0.0.0.0/0" >> "$GITHUB_ENV"

# "Set job outputs" step
ssh_cidr="0.0.0.0/0"
```

**After:**
```bash
# "Set dynamic vars" step
runner_ip="$(curl -fsSL https://api.ipify.org)"
echo "SSH_CIDR=${runner_ip}/32" >> "$GITHUB_ENV"

# "Set job outputs" step
ssh_cidr="$(curl -fsSL https://api.ipify.org)/32"
```

**Why:** The Terraform security group only needs to allow the GitHub Actions runner's IP.  
Deriving it at runtime restricts SSH access to a single `/32` CIDR instead of the entire internet.

---

## FIX-04 — Correct Helm release name in EKS destroy

**Bug:** BUG-07  
**File changed:** `v2/.github/workflows/eks-destroy.yml`

**Before:**
```bash
helm uninstall ingress-nginx -n ingress-nginx --ignore-not-found || true
kubectl delete namespace ingress-nginx --ignore-not-found
```

**After:**
```bash
helm uninstall nginx-ingress -n nginx-ingress --ignore-not-found || true
kubectl delete namespace nginx-ingress --ignore-not-found
```

**Why:** The deploy workflow installs the Helm chart with `--install nginx-ingress` (release  
name = `nginx-ingress`) in namespace `nginx-ingress`. The destroy must use the same name/namespace.  
Mismatch causes `helm uninstall` to silently succeed ("release not found") while leaving the  
NIC LoadBalancer running, which then blocks `terraform destroy` from deleting the VPC.

**Also fixed:** `run-name` contained `"Hola Cine"` — leftover vibe-coding artifact, corrected  
to `"Destroy EKS + Cine (${{ github.actor }})"`.

---

## FIX-05 — AKS destroy: complete rewrite

**Bug:** BUG-06A, BUG-06B, BUG-06C  
**File changed:** `v2/.github/workflows/aks-destroy.yml`

### BUG-06A fix: remove `kubectl delete -f nic-values.yaml`

**Before:**
```yaml
- name: Destroy Kubernetes resources
  run: |
    kubectl delete -f aks-nginx-plus/k8s/nginx-ic/nic-values.yaml --ignore-not-found
```

**After:** removed. Replaced with proper Helm uninstall.

### BUG-06B fix: use `terraform destroy` instead of `az aks delete`

**Before:**
```yaml
- name: Delete AKS cluster
  run: |
    az aks delete --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --yes --no-wait
```

**After:** Two-job structure:
1. `destroy-k8s` — removes Kubernetes workloads and Helm release
2. `terraform-destroy` — runs `terraform destroy -auto-approve` (removes cluster, resource group,
   Log Analytics workspace, and updates the Terraform state file)

### BUG-06C fix: eliminate `AKS_RESOURCE_GROUP` and `AKS_CLUSTER_NAME` secrets

**Before:**
```yaml
echo "RESOURCE_GROUP=${{ secrets.AKS_RESOURCE_GROUP }}" >> $GITHUB_ENV
echo "CLUSTER_NAME=${{ secrets.AKS_CLUSTER_NAME }}" >> $GITHUB_ENV
```

**After:** values are read from Terraform outputs:
```bash
echo "cluster_name=$(terraform output -raw cluster_name)"           >> $GITHUB_OUTPUT
echo "resource_group=$(terraform output -raw resource_group_name)"  >> $GITHUB_OUTPUT
```

No additional secrets required — the Azure credentials (`AZURE_CLIENT_ID`, etc.) and  
Terraform Cloud credentials (`TFC_TOKEN`, `TFC_ORG`) are already present from the deploy.

---

## FIX-06 — `netstat` → `ss` (Ubuntu 22.04+ compatibility)

**Bug:** BUG-08  
**Files changed:**
- `v2/nginx-plus-one-vm/scripts/diagnose-cine.sh`
- `v2/.github/workflows/nginx-plus-ec2.yml` (deploy-cine "Verify" step)

**Before:**
```bash
sudo netstat -tlnp | grep 3000
```

**After:**
```bash
sudo ss -tlnp | grep ':3000'
```

**Why:** `netstat` requires the `net-tools` package, which is not installed by default on  
Ubuntu 22.04 and 24.04. `ss` is part of `iproute2` which is installed on all Ubuntu images.

---

## Files NOT changed (identical to originals)

The following files have no bugs and are correct as-is:

| File | Notes |
|---|---|
| `ex5-plus/scripts/install-nginx-plus.sh` | Already uses correct GPG URL and `ss` |
| `nginx-plus-ec2-destroy.yml` | Already uses `exit 0` correctly |
| `eks-deploy.yml` | Functionally correct (BUG-03 is a config mismatch, not a code bug) |
| `aks-deploy.yml` | Correct |
| `nginx-eks/` app source | Correct (BUG-05 is a documentation gap, not a code error) |
| All Terraform files | Correct |
| All Dockerfiles | Correct |
| All Kubernetes manifests | Correct |
| `ex5-plus/scripts/cine-nginx.conf` | Correct (NAP v5 directives) |
| `nginx-plus-one-vm/scripts/cine-nginx.conf` | Correct (NAP v4 directives) |
