# Architecture Diagrams

---

## 1. Flujo de tráfico — EC2 con NAP WAF v4 (`nginx-plus-one-vm`)

```mermaid
graph TD
    Internet((Internet)) -->|HTTP :80| NGINX["NGINX Plus R36\n+ NAP WAF v4\npaquete apt"]
    NGINX -->|"Host: cine.example.com\nproxy_pass :3000"| Backend["Backend EC2\nNode.js apps"]
    NGINX -->|"Host: cine-tmdb.example.com\nproxy_pass :3001"| Backend
    Backend -->|HTTPS| OMDb["OMDb API\nexterno"]
    Backend -->|HTTPS| TMDB["TMDB API\nexterno"]

    subgraph AWS ["AWS Region"]
        subgraph VPC ["VPC"]
            subgraph Public ["Subnet pública"]
                NGINX
            end
            subgraph Private ["Subnet privada — acceso solo desde SG de NGINX"]
                Backend
            end
        end
    end
```

---

## 2. Flujo de tráfico — EC2 con NAP WAF v5 hybrid (`ex5-plus`)

```mermaid
graph TD
    Internet((Internet)) -->|HTTP :80| NGINX["NGINX Plus R36\n+ ngx_http_app_protect_module"]
    NGINX -->|"Unix socket / gRPC\napp_protect_enforcer_address\n127.0.0.1:50000"| WAF["waf-enforcer\ncontainer\n:50000"]
    WAF <-->|Volumen compartido\n/opt/app_protect/bd_config| CFG["waf-config-mgr\ncontainer\n(compila políticas)"]
    NGINX -->|"Host: cine.example.com"| Backend["Backend EC2\nNode.js apps"]
    NGINX -->|"Host: cine-tmdb.example.com"| Backend

    subgraph Host ["EC2 nginx-plus"]
        NGINX
        subgraph Docker ["Docker Compose (NAP v5)"]
            WAF
            CFG
        end
    end
```

---

## 3. Flujo de tráfico — Kubernetes EKS/AKS con NAP WAF v5

```mermaid
graph TD
    Internet((Internet)) -->|HTTP/HTTPS| LB["AWS ALB / Azure LB"]
    LB --> NIC["NGINX Ingress Controller v5.3.4\n+ NAP WAF v5.11.2 bundle\ncine-waf.tgz compilado en imagen"]
    NIC -->|"VirtualServer + Policy\ncine.example.com"| PodA["Pod: cine-app\nNode.js :3000"]
    NIC -->|"VirtualServer + Policy\ncine-tmdb.example.com"| PodB["Pod: cine-tmdb\nNode.js :3001"]
    PodA -->|HTTPS| OMDb["OMDb API"]
    PodB -->|HTTPS| TMDB["TMDB API"]

    subgraph K8s ["Kubernetes Cluster (EKS v1.33 / AKS v1.32)"]
        subgraph NS_NIC ["Namespace: nginx-ingress"]
            NIC
        end
        subgraph NS_APP ["Namespace: cine"]
            PodA
            PodB
        end
    end
```

---

## 4. Pipeline GitHub Actions — Deploy EC2

```mermaid
flowchart LR
    TRG([workflow_dispatch]) --> J1 & J2 & J3 & J4

    J1["Job 1\ncreate-waf-policy-cinex\nOpcional: sube policy WAF\na NGINX One Console"]
    J2["Job 2\nsetup-tfc\nCrea workspace en\nTerraform Cloud"]
    J3["Job 3\nbuild-cine-omdb\nValida sintaxis JS"]
    J4["Job 4\nbuild-cine-tmdb\nValida sintaxis JS"]

    J2 --> J5["Job 5\nterraform\nCrea VPC + 2 EC2\ndevuelve IPs"]
    J5 --> J6["Job 6\ninstall\nSSH → instala\nNGINX Plus\n+ NAP WAF\n+ Agent"]

    J1 & J2 & J3 & J4 & J5 & J6 --> J7["Job 7\ndeploy-cine\nSSH → despliega\napps Node.js\ncomo servicios systemd"]
```

---

## 5. Pipeline GitHub Actions — Deploy Kubernetes (EKS/AKS)

```mermaid
flowchart LR
    TRG([workflow_dispatch]) --> S

    S["setup\nVerifica TFC token"] --> B1 & B2 & B3

    B1["build-image\nDocker build\ncine-app → GHCR"]
    B2["build-image-tmdb\nDocker build\ncine-tmdb → GHCR"]
    B3["build-nic\nDocker build\nNIC + NAP WAF bundle → GHCR"]

    B1 & B2 & B3 --> TP["terraform-plan\nPlan: VPC + cluster"]
    TP --> TA["terraform-apply\nCrea cluster\n~12 min"]
    TA --> SI["setup-ingress\nhelm install nginx-ingress\n(NIC desde GHCR)"]
    SI --> DA["deploy-app\nkubectl apply\nVirtualServer + Pods"]
```

---

## 6. Diagrama de secretos requeridos por proyecto

```mermaid
graph LR
    subgraph ALL ["Todos los proyectos"]
        TFC_TOKEN
        TFC_ORG
    end

    subgraph EC2 ["Proyectos EC2 (nginx-plus-one-vm, ex5-plus)"]
        NGINX_REPO_CRT
        NGINX_REPO_KEY
        LICENSE_JWT
        LICENSE_KEY
        DATA_PLANE_KEY
        SSH_PUBLIC_KEY
        SSH_PRIVATE_KEY
        AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY
        AWS_REGION_S["AWS_REGION (Secret)"]
        OMDB_API_KEY
        TMDB_API_KEY
    end

    subgraph EKS ["Proyecto EKS (nginx-eks)"]
        AWS_AK["AWS_ACCESS_KEY_ID"]
        AWS_SAK["AWS_SECRET_ACCESS_KEY"]
        AWS_REGION_V["AWS_REGION (Variable)"]
        OMDB_EKS["OMDB_API_KEY"]
        TMDB_EKS["TMDB_API_KEY"]
    end

    subgraph AKS ["Proyecto AKS (aks-nginx-plus)"]
        AZURE_CLIENT_ID
        AZURE_CLIENT_SECRET
        AZURE_TENANT_ID
        AZURE_SUBSCRIPTION_ID
    end

    subgraph XC ["Opcional: NGINX One Console"]
        XC_API_P12_FILE
        XC_API_URL
        XC_P12_PASSWORD
    end
```
