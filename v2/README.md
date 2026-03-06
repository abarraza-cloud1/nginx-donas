# nginx-plus-one — Guía de uso desde cero

Este repositorio contiene 4 proyectos de demostración de **NGINX Plus + NAP WAF** gestionados  
con GitHub Actions y Terraform Cloud. Cada proyecto es independiente.

| Proyecto | Infraestructura | NAP WAF | Carpeta |
|---|---|---|---|
| `nginx-plus-one-vm` | AWS EC2 (2 VMs) | v4 (paquete apt) | `nginx-plus-one-vm/` |
| `ex5-plus` | AWS EC2 (2 VMs) | v5 (Docker hybrid) | `ex5-plus/` |
| `nginx-eks` + `nginx-plus-one-eks` | AWS EKS | v5 (bundle en NIC) | `nginx-eks/` |
| `aks-nginx-plus` | Azure AKS | v5 (bundle en NIC) | `aks-nginx-plus/` |

---

## Requisitos previos

Antes de ejecutar cualquier workflow necesitas tener activas las siguientes cuentas y licencias:

| Requisito | Dónde obtenerlo |
|---|---|
| Cuenta de GitHub con Actions habilitado | github.com |
| Cuenta de Terraform Cloud | app.terraform.io |
| Licencia de NGINX Plus (`.crt` + `.key` + JWT) | my.f5.com → NGINX Plus trial o compra |
| Cuenta AWS con acceso programático | AWS IAM |
| Cuenta Azure con Service Principal | Azure portal (solo para AKS) |
| API key de OMDb | omdbapi.com (gratis) |
| API key de TMDB | themoviedb.org (gratis) |
| SSH key pair | generada localmente (ver paso 2) |

---

## Paso 1 — Fork del repositorio

1. En GitHub, navega a `https://github.com/ocpdata/nginx-plus-one`
2. Haz clic en **Fork** → **Create fork**
3. Clona tu fork:
   ```bash
   git clone https://github.com/<tu-usuario>/nginx-plus-one.git
   cd nginx-plus-one
   ```

---

## Paso 2 — Generar SSH key pair

Los workflows crean instancias EC2 y se conectan por SSH. Necesitas un par de claves.

```bash
ssh-keygen -t ed25519 -C "nginx-plus-deploy" -f ~/.ssh/nginx-plus-deploy -N ""
```

Esto genera dos archivos:
- `~/.ssh/nginx-plus-deploy` — clave privada (se guarda como secret `SSH_PRIVATE_KEY`)
- `~/.ssh/nginx-plus-deploy.pub` — clave pública (se guarda como secret `SSH_PUBLIC_KEY`)

---

## Paso 3 — Configurar Terraform Cloud

1. Ve a [app.terraform.io](https://app.terraform.io) y crea una cuenta (gratis para uso personal)
2. Crea una **organización** (anota el nombre, lo necesitas como `TFC_ORG`)
3. Genera un **API token**:
   - User settings → Tokens → **Create an API token**
   - Guarda el token como `TFC_TOKEN`

> Los workspaces de Terraform se crean **automáticamente** por los workflows. No necesitas crearlos a mano.

---

## Paso 4 — Configurar GitHub Secrets y Variables

Ve a tu repositorio en GitHub → **Settings** → **Secrets and variables** → **Actions**.

### Secrets (para todos los proyectos)

| Secret | Valor | Usado por |
|---|---|---|
| `TFC_TOKEN` | Token de Terraform Cloud | Todos |
| `TFC_ORG` | Nombre de la organización en TFC | Todos |
| `NGINX_REPO_CRT` | Contenido del archivo `.crt` de NGINX Plus | EC2, EKS, AKS |
| `NGINX_REPO_KEY` | Contenido del archivo `.key` de NGINX Plus | EC2, EKS, AKS |
| `LICENSE_JWT` | Contenido del `license.jwt` de NGINX Plus | EC2 |
| `LICENSE_KEY` | Contenido del `license.key` de NGINX Plus | EC2 |
| `DATA_PLANE_KEY` | Token del agente NGINX One Console | EC2 |
| `SSH_PUBLIC_KEY` | Contenido de `~/.ssh/nginx-plus-deploy.pub` | EC2 |
| `SSH_PRIVATE_KEY` | Contenido de `~/.ssh/nginx-plus-deploy` | EC2 |
| `AWS_ACCESS_KEY_ID` | Access key de AWS IAM | EC2, EKS |
| `AWS_SECRET_ACCESS_KEY` | Secret key de AWS IAM | EC2, EKS |
| `AWS_REGION` | Región de AWS (ej. `us-east-1`) | EC2 only* |
| `OMDB_API_KEY` | Tu API key de OMDb | EC2, EKS |
| `TMDB_API_KEY` | Tu API key de TMDB | EC2, EKS |

> **\* Nota importante:** Para los proyectos EKS, `AWS_REGION` debe configurarse como  
> **Variable** (no Secret). Ve a Settings → Variables → New repository variable.

### Variables (para proyectos EKS únicamente)

| Variable | Valor | Usado por |
|---|---|---|
| `AWS_REGION` | Región de AWS (ej. `us-east-1`) | `eks-deploy.yml`, `eks-destroy.yml` |

### Secrets adicionales para Azure AKS

| Secret | Valor |
|---|---|
| `AZURE_CLIENT_ID` | Application (client) ID del Service Principal |
| `AZURE_CLIENT_SECRET` | Secret del Service Principal |
| `AZURE_TENANT_ID` | Directory (tenant) ID |
| `AZURE_SUBSCRIPTION_ID` | ID de la suscripción de Azure |

### Secrets opcionales — NGINX One Console (F5 XC)

Estos secrets son **opcionales**. Si no los configuras, el workflow continúa sin sincronizar  
la política WAF con NGINX One Console.

| Secret | Descripción |
|---|---|
| `XC_API_P12_FILE` | Archivo `.p12` del Service Credential de F5 XC, codificado en base64 |
| `XC_API_URL` | URL del tenant XC (ej. `https://tu-tenant.console.ves.volterra.io`) |
| `XC_P12_PASSWORD` | Password del archivo `.p12` |

Para codificar el `.p12` en base64:
```bash
base64 -w 0 mi-credential.p12
```

---

## Paso 5 — Elegir qué proyecto desplegar

### Proyecto A: NGINX Plus + NAP v4 en EC2 (`nginx-plus-one-vm`)

**Qué hace:** Crea dos instancias EC2 — una con NGINX Plus + NAP WAF v4 como proxy, y otra  
con las dos apps Node.js (Cine OMDb y Cine TMDB) como backend.

**Workflow:** `.github/workflows/nginx-plus-ec2.yml`

1. Ve a tu repositorio → **Actions**
2. Selecciona **"Deploy Nginx Plus - WAF - Nginx One Agent en una VM en AWS"**
3. Haz clic en **Run workflow** → **Run workflow**
4. Espera ~15 minutos
5. Al final del workflow, en el job `deploy-cine` → paso "Display Cine app URL",  
   verás las IPs de acceso:
   ```
   ✅ Cine app deployed successfully!
   🌐 Access the app at: http://<IP>:3000/
   🌐 Access the TMDB app at: http://<IP>:3001/
   ```

**Para destruir:** Workflow → "Destroy Nginx Plus EC2" → Run workflow

---

### Proyecto B: NGINX Plus + NAP v5 hybrid en EC2 (`ex5-plus`)

**Qué hace:** Igual que el proyecto A, pero NAP WAF corre como dos contenedores Docker  
(`waf-enforcer` + `waf-config-mgr`), que es la arquitectura v5.

**Workflow:** `.github/workflows/ec5-plus.yml`

Mismos pasos que el Proyecto A, seleccionando el workflow `ec5-plus`.

---

### Proyecto C: NGINX Plus + NAP v5 en EKS (`nginx-eks`)

**Qué hace:** Crea un cluster EKS en AWS, instala el NGINX Ingress Controller con NAP WAF v5  
compilado en la imagen, construye las apps Node.js como contenedores y las despliega en  
Kubernetes con VirtualServer y políticas WAF.

**Prerequisito adicional:** El NIC custom se construye y sube a GHCR (GitHub Container Registry).  
Asegúrate de que tu usuario de GitHub tiene habilitados los packages.

**Workflow:** `.github/workflows/eks-deploy.yml`

1. Ve a **Actions** → **"Deploy EKS + Cine"** (o el nombre que aparezca)
2. Run workflow
3. El workflow tiene estos jobs en orden:
   - `setup` — crea workspace TFC
   - `build-image`, `build-image-tmdb`, `build-nic` — parallel: construye 3 imágenes Docker
   - `terraform-plan` → `terraform-apply` — crea VPC + EKS cluster (~12 min)
   - `setup-ingress` — instala NIC via Helm
   - `deploy-app` — aplica manifests K8s
4. Al final verás las URLs de acceso (IPs del LoadBalancer de AWS)

**Para destruir:** Actions → "Destroy EKS + Cine" → Run workflow

---

### Proyecto D: NGINX Plus + NAP v5 en AKS (`aks-nginx-plus`)

**Qué hace:** Igual que el Proyecto C pero en Azure Kubernetes Service.

**Workflow:** `.github/workflows/aks-deploy.yml`

1. Ve a **Actions** → **"Deploy AKS + Cine"**
2. Run workflow
3. Jobs en orden:
   - `setup` — verifica token TFC
   - `build-nic`, `build-image`, `build-image-tmdb` — parallel: construye imágenes
   - `terraform-plan` → `terraform-apply` — crea AKS cluster (~15 min)
   - `setup-ingress` → `deploy-app`
4. Al final verás las URLs del LoadBalancer de Azure

**Para destruir:** Actions → "AKS Destroy" → Run workflow

---

## Paso 6 — Verificar que funciona

Una vez desplegado cualquier proyecto, puedes verificar:

### Para proyectos EC2

Accede directamente a las IPs que aparecen en el log del workflow:
- `http://<IP>:3000/` → app Cine (OMDb, búsqueda de películas por título)
- `http://<IP>:3001/` → app Cine TMDB (búsqueda de películas con detalles)

Para verificar que el WAF está activo, intenta un ataque XSS:
```bash
curl -H "Host: cine.example.com" "http://<NGINX_IP>/?search=<script>alert(1)</script>"
# Debe responder con HTTP 200 y la respuesta de la política (bloqueado o en modo transparente)
```

Para configurar hosts locales y acceder por hostname:
```bash
# Añade a /etc/hosts (Linux/Mac) o C:\Windows\System32\drivers\etc\hosts (Windows):
<NGINX_PUBLIC_IP>   cine.example.com
<NGINX_PUBLIC_IP>   cine-tmdb.example.com
```

Luego abre `http://cine.example.com` en el navegador.

### Para proyectos Kubernetes

El LoadBalancer URL aparece en los logs del workflow. Puedes también obtenerlo con:
```bash
kubectl get svc -n nginx-ingress
# EXTERNAL-IP es la IP/hostname del LoadBalancer
```

---

## Paso 7 — Destruir los recursos

**Importante:** Los recursos de AWS y Azure **generan costos mientras estén corriendo**.  
Destruye siempre después de terminar las pruebas.

| Proyecto | Workflow de destrucción |
|---|---|
| EC2 NAP v4 | "Destroy Nginx Plus EC2" |
| EC2 NAP v5 | No existe workflow dedicado — destruir vía Terraform CLI o TFC |
| EKS | "Destroy EKS + Cine" |
| AKS | "AKS Destroy" |

---

## Referencia rápida — Todos los secrets

```
# Terraform Cloud
TFC_TOKEN=<token>
TFC_ORG=<org-name>

# NGINX Plus
NGINX_REPO_CRT=<contenido del .crt>
NGINX_REPO_KEY=<contenido del .key>
LICENSE_JWT=<contenido del license.jwt>
LICENSE_KEY=<contenido del license.key>
DATA_PLANE_KEY=<token del NGINX One agent>

# SSH (EC2)
SSH_PUBLIC_KEY=<contenido de id_ed25519.pub>
SSH_PRIVATE_KEY=<contenido de id_ed25519>

# AWS
AWS_ACCESS_KEY_ID=<key>
AWS_SECRET_ACCESS_KEY=<secret>
AWS_REGION=<region>  ← Secret para EC2; Variable para EKS

# Apps
OMDB_API_KEY=<key>
TMDB_API_KEY=<key>

# Azure (solo AKS)
AZURE_CLIENT_ID=<id>
AZURE_CLIENT_SECRET=<secret>
AZURE_TENANT_ID=<tenant>
AZURE_SUBSCRIPTION_ID=<subscription>

# NGINX One Console / F5 XC (opcional)
XC_API_P12_FILE=<base64 del .p12>
XC_API_URL=<https://tu-tenant.console.ves.volterra.io>
XC_P12_PASSWORD=<password>
```

---

## Arquitectura general

```
GitHub Actions Workflow
        │
        ├── Job: create-waf-policy-cinex  (opcional: NGINX One Console)
        │
        ├── Job: setup-tfc / setup         (crea workspace en Terraform Cloud)
        │
        ├── Job: terraform / terraform-apply  ──►  AWS/Azure
        │         └── crea VMs o cluster K8s
        │
        ├── Job: install / build-nic       (instala NGINX Plus + NAP WAF)
        │
        ├── Job: build-cine-omdb/tmdb      (valida/empaqueta apps Node.js)
        │
        └── Job: deploy-cine / deploy-app  (despliega las apps)
```

### Flujo de tráfico (EC2)

```
Internet
   │
   ▼
[NGINX Plus + NAP WAF]  ←── WAF inspecciona cada request
   │
   ├── Host: cine.example.com  ──►  [Backend :3000]  ──►  OMDb API
   └── Host: cine-tmdb.example.com  ──►  [Backend :3001]  ──►  TMDB API
```

### Flujo de tráfico (Kubernetes)

```
Internet
   │
   ▼
[LoadBalancer AWS/Azure]
   │
   ▼
[NGINX Ingress Controller + NAP WAF bundle]
   │
   ├── VirtualServer cine.example.com     ──►  Pod cine-app :3000
   └── VirtualServer cine-tmdb.example.com  ──►  Pod cine-tmdb :3001
```

---

## Solución de problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| Workflow falla en el primer job | Secretos de TFC no configurados | Verificar `TFC_TOKEN` y `TFC_ORG` |
| `apt-get install nginx-plus` falla con GPG error | Solo en `nginx-plus-one-vm`: URL de GPG incorrecta | Usar los archivos de `v2/` |
| `helm uninstall ingress-nginx` no encuentra release | Solo en `eks-destroy` original: nombre incorrecto | Usar `v2/.github/workflows/eks-destroy.yml` |
| `kubectl delete -f nic-values.yaml` falla | `aks-destroy` original: archivo incorrecto | Usar `v2/.github/workflows/aks-destroy.yml` |
| Apps retornan HTTP 500 | `OMDB_API_KEY` o `TMDB_API_KEY` no configurados | Añadir secrets a GitHub |
| `netstat: command not found` en diagnose script | Ubuntu 22.04+ no incluye net-tools | Usar `v2/nginx-plus-one-vm/scripts/diagnose-cine.sh` |
| Terraform destroy falla con "resource not found" en AKS | `az aks delete` fue ejecutado antes, estado desincronizado | Importar recursos con `terraform import` o limpiar estado |

---

## Cómo aplicar los fixes de v2/ al repositorio principal

Los archivos en `v2/` son las versiones corregidas. Para usarlos, cópialos sobre los originales:

```bash
# Desde la raíz del repo:
cp v2/.github/workflows/nginx-plus-ec2.yml .github/workflows/nginx-plus-ec2.yml
cp v2/.github/workflows/ec5-plus.yml        .github/workflows/ec5-plus.yml
cp v2/.github/workflows/eks-destroy.yml     .github/workflows/eks-destroy.yml
cp v2/.github/workflows/aks-destroy.yml     .github/workflows/aks-destroy.yml
cp v2/nginx-plus-one-vm/scripts/install-nginx-plus.sh nginx-plus-one-vm/scripts/install-nginx-plus.sh
cp v2/nginx-plus-one-vm/scripts/diagnose-cine.sh      nginx-plus-one-vm/scripts/diagnose-cine.sh

git add .
git commit -m "fix: apply all bug fixes from v2/ audit"
git push
```

Consulta `v2/BUGS.md` para el informe completo de bugs encontrados y `v2/FIXES.md` para  
el detalle de cada cambio aplicado.
