# Pre-Fix Audit Report — Static Analysis

> **Status:** Initial state of the repository before any fixes were applied.  
> **Method:** Static reading of all files. No deployment was executed.  
> **Date:** March 5, 2026

---

## Summary Table

| ID | Severity | Blocks deploy? | File | Description |
|---|---|---|---|---|
| BUG-01 | 🔴 CRITICAL | ✅ YES | `nginx-plus-ec2.yml`, `ec5-plus.yml` | `exit 1` when XC secrets missing — cancels all downstream jobs |
| BUG-02 | 🔴 CRITICAL | ✅ YES | `nginx-plus-one-vm/scripts/install-nginx-plus.sh` | Wrong GPG key URL — apt install fails |
| BUG-03 | 🔴 CRITICAL | ✅ YES (EKS) | `eks-deploy.yml` | `AWS_REGION` defined as Variable, README says Secret — mismatch causes confusion |
| BUG-04 | 🟠 MEDIUM | No | `nginx-plus-ec2.yml`, `ec5-plus.yml` | SSH CIDR hardcoded `0.0.0.0/0` — opens SSH to the world |
| BUG-05 | 🟠 MEDIUM | Partial | All workflows | `OMDB_API_KEY` never documented; K8s version returns HTTP 500 when missing |
| BUG-06A | 🔴 CRITICAL | ✅ YES (destroy) | `aks-destroy.yml` | `kubectl delete -f nic-values.yaml` — that's a Helm values file, not a manifest |
| BUG-06B | 🔴 CRITICAL | ✅ YES (destroy) | `aks-destroy.yml` | Uses `az aks delete` directly, bypasses Terraform — causes state drift |
| BUG-06C | 🟠 MEDIUM | ✅ YES (destroy) | `aks-destroy.yml` | `AKS_RESOURCE_GROUP` and `AKS_CLUSTER_NAME` secrets required but never documented anywhere |
| BUG-07 | 🟠 MEDIUM | ✅ YES (destroy) | `eks-destroy.yml` | `helm uninstall ingress-nginx` — wrong release name, should be `nginx-ingress` |
| BUG-08 | 🟡 MINOR | No | `diagnose-cine.sh`, `nginx-plus-ec2.yml` | `netstat` not available on Ubuntu 22.04+ — use `ss` |

---

## Detailed Findings

### BUG-01 — CRITICAL: `exit 1` blocks all EC2 deploy jobs

**Files:** `.github/workflows/nginx-plus-ec2.yml` (line 24), `.github/workflows/ec5-plus.yml` (line 26)

**Evidence:**
```bash
# nginx-plus-ec2.yml, lines 22-25
if [[ -z "${XC_API_P12_FILE:-}" || -z "${XC_API_URL:-}" || -z "${VES_P12_PASSWORD:-}" ]]; then
  echo "Missing one or more required secrets: XC_API_P12_FILE, XC_API_URL, XC_P12_PASSWORD" >&2
  exit 1   # ← THIS IS THE BUG
fi
```

**What happens:**  
The first job `create-waf-policy-cinex` exits with code 1 if XC secrets are not configured.  
GitHub Actions marks any job that exits non-zero as **failed**. Because `deploy-cine` has  
`needs: [..., create-waf-policy-cinex]`, GitHub cancels the entire workflow.

**The NGINX One Console integration is optional** — it syncs the WAF policy to F5 XC cloud.  
A deployment without it still works; NGINX Plus + NAP WAF install and run locally.

**Contrast:** The destroy workflow (`nginx-plus-ec2-destroy.yml` line 48) correctly uses `exit 0`  
for the same check. The deploy workflow should mirror this pattern.

---

### BUG-02 — CRITICAL: Wrong GPG key URL breaks apt install

**File:** `nginx-plus-one-vm/scripts/install-nginx-plus.sh` (line 38)

**Evidence:**
```bash
# Wrong:
curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

# Should be:
curl -fsSL https://cs.nginx.com/static/keys/nginx_signing.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
```

**What happens:**  
`nginx.org/keys/nginx_signing.key` is the public GPG key for the open-source NGINX packages.  
`pkgs.nginx.com` (the NGINX Plus repo) is signed by the key at `cs.nginx.com`.  
Using the wrong key causes all `apt-get install nginx-plus app-protect` commands to fail  
with a signature verification error.

**Note:** `ex5-plus/scripts/install-nginx-plus.sh` already uses the correct URL — only the  
`nginx-plus-one-vm` version is wrong.

---

### BUG-03 — CRITICAL: `AWS_REGION` as Variable vs Secret inconsistency

**File:** `.github/workflows/eks-deploy.yml` (line 8)

**Evidence:**
```yaml
# eks-deploy.yml line 8
AWS_REGION: ${{ vars.AWS_REGION }}   # ← uses vars.*, NOT secrets.*
```

All EC2 workflows use `${{ secrets.AWS_REGION }}`. EKS workflows use `${{ vars.AWS_REGION }}`.  
These are different GitHub-level storage locations (Actions Variables vs Actions Secrets).  
If a user sets AWS_REGION as a Secret following the EC2 pattern, EKS deploys will fail  
with an empty variable.

**Fix:** `AWS_REGION` is not sensitive — it should be a Variable everywhere. The EC2 workflows  
need to be updated to use `vars.AWS_REGION` to match EKS.

---

### BUG-04 — MEDIUM: SSH open to the world

**Files:** `nginx-plus-ec2.yml` (line 174), `ec5-plus.yml` (line 167)

**Evidence:**
```bash
# setup-tfc job, "Set dynamic vars" step
echo "SSH_CIDR=0.0.0.0/0" >> "$GITHUB_ENV"
```

This passes `ssh_cidr=0.0.0.0/0` to Terraform, which creates an EC2 security group rule  
allowing SSH from any IP on the internet. GitHub Actions runners have known IP ranges;  
the CIDR should be restricted to the runner's current IP.

---

### BUG-05 — MEDIUM: `OMDB_API_KEY` undocumented; K8s version crashes without it

**Files:** All EC2 and EKS deploy workflows; `nginx-eks/app/index.js` line 8

**Evidence:**
```javascript
// nginx-eks/app/index.js
const OMDB_API_KEY = process.env.OMDB_API_KEY;  // no fallback
// ...
if (!OMDB_API_KEY) {
  return res.status(500).json({ error: "OMDB_API_KEY no configurada" });
}
```

The VM version has a `|| "demo"` fallback. The K8s version returns HTTP 500.  
Neither `OMDB_API_KEY` nor `TMDB_API_KEY` appears in any README or secrets table.

---

### BUG-06A — CRITICAL: `kubectl delete -f` on a Helm values file

**File:** `.github/workflows/aks-destroy.yml` (line 44)

**Evidence:**
```yaml
- name: Destroy Kubernetes resources
  run: |
    kubectl delete -f aks-nginx-plus/k8s/nginx-ic/nic-values.yaml --ignore-not-found
```

`nic-values.yaml` is a Helm `--values` file (it has `controller:`, `service:` keys).  
It is **not** a Kubernetes manifest. `kubectl delete -f` will fail with:  
`error: no objects passed to delete`.

The correct way to remove the Helm release is `helm uninstall nginx-ingress`.

---

### BUG-06B — CRITICAL: `az aks delete` bypasses Terraform state

**File:** `.github/workflows/aks-destroy.yml` (line 59)

**Evidence:**
```yaml
- name: Delete AKS cluster
  run: |
    az aks delete --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --yes --no-wait
```

Terraform does not know this deletion happened. On the next `terraform plan` or  
`terraform apply`, Terraform will try to manage a resource that no longer exists  
and fail with `ResourceNotFound`. The Resource Group and Log Analytics workspace  
are also left behind.

**Fix:** Use `terraform destroy` which removes all resources and updates the state file.

---

### BUG-06C — MEDIUM: Two undocumented secrets in aks-destroy.yml

**File:** `.github/workflows/aks-destroy.yml` (lines 26-27)

**Evidence:**
```yaml
- name: Set AKS variables
  run: |
    echo "RESOURCE_GROUP=${{ secrets.AKS_RESOURCE_GROUP }}" >> $GITHUB_ENV
    echo "CLUSTER_NAME=${{ secrets.AKS_CLUSTER_NAME }}" >> $GITHUB_ENV
```

`AKS_RESOURCE_GROUP` and `AKS_CLUSTER_NAME` are not mentioned in any README.  
These values are already available from Terraform outputs — no secrets needed.

---

### BUG-07 — MEDIUM: Wrong Helm release name in EKS destroy

**File:** `.github/workflows/eks-destroy.yml` (line 63)

**Evidence:**
```bash
# eks-destroy.yml line 63
helm uninstall ingress-nginx -n ingress-nginx --ignore-not-found || true

# eks-deploy.yml (deploy) installs with:
helm upgrade --install nginx-ingress ...   # release name = "nginx-ingress"
```

The uninstall uses `ingress-nginx` (wrong). The release was installed as `nginx-ingress`.  
Helm will report "release not found" and the controller will not be removed before  
Terraform destroy — the LoadBalancer may block VPC deletion.

Also: `run-name` contains "Hola Cine" — leftover vibe-coding artifact.

---

### BUG-08 — MINOR: `netstat` not available on Ubuntu 22.04+

**Files:** `nginx-plus-one-vm/scripts/diagnose-cine.sh` (line 8), `nginx-plus-ec2.yml` deploy-cine job

**Evidence:**
```bash
sudo netstat -tlnp | grep 3000
```

`netstat` is part of the `net-tools` package which is **not installed by default**  
on Ubuntu 22.04 and 24.04. The equivalent command using the built-in `ss`:
```bash
sudo ss -tlnp | grep ':3000'
```

---

## Additional Findings (not bugs, but risks)

| # | Risk | Files |
|---|---|---|
| R-01 | `aks-nginx-plus/k8s/waf/waf-policy.yaml` uses NAP v4 CRD (`appprotect.f5.com/v1beta1`) but cluster runs NAP v5 | `waf-policy.yaml`, `waf-logconf.yaml` |
| R-02 | `nginx-eks/k8s/ingress.yaml` has NAP v4 annotations; the deploy workflow explicitly deletes it and uses VirtualServer instead — dead file | `ingress.yaml` |
| R-03 | `/api/debug` endpoint in `nginx-eks/cine-tmdb/index.js` exposes Node version, key length, auth method — no auth | `index.js` line 78 |
| R-04 | `aks-nginx-plus/docker/nginx-nic/` and `nginx-plus-one-eks/docker/nginx-nic/` are byte-for-byte identical — silent divergence risk | Both Dockerfiles |
