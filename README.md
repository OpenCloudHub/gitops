<a id="readme-top"></a>

<!-- PROJECT LOGO & TITLE -->

<div align="center">
  <a href="https://github.com/opencloudhub">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/opencloudhub/.github/main/assets/brand/assets/logos/primary-logo-light.svg">
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/opencloudhub/.github/main/assets/brand/assets/logos/primary-logo-dark.svg">
    <!-- Fallback -->
    <img alt="OpenCloudHub Logo" src="https://raw.githubusercontent.com/opencloudhub/.github/main/assets/brand/assets/logos/primary-logo-dark.svg" style="max-width:700px; max-height:175px;">
  </picture>
  </a>

<h1 align="center">GitOps Repository</h1>

<!-- SHORT DESCRIPTION -->

<p align="center">
    Kubernetes GitOps configuration with ArgoCD, featuring MLOps pipelines, observability stack, storage solutions and model serving.<br />
    <a href="https://github.com/opencloudhub/.github"><strong>Explore the organization »</strong></a>
  </p>

<!-- BADGES -->

<p align="center">
    <a href="https://github.com/opencloudhub/gitops/graphs/contributors">
      <img src="https://img.shields.io/github/contributors/opencloudhub/gitops.svg?style=for-the-badge" alt="Contributors">
    </a>
    <a href="https://github.com/opencloudhub/gitops/network/members">
      <img src="https://img.shields.io/github/forks/opencloudhub/gitops.svg?style=for-the-badge" alt="Forks">
    </a>
    <a href="https://github.com/opencloudhub/gitops/stargazers">
      <img src="https://img.shields.io/github/stars/opencloudhub/gitops.svg?style=for-the-badge" alt="Stars">
    </a>
    <a href="https://github.com/opencloudhub/gitops/issues">
      <img src="https://img.shields.io/github/issues/opencloudhub/gitops.svg?style=for-the-badge" alt="Issues">
    </a>
    <a href="https://github.com/opencloudhub/gitops/blob/main/LICENSE">
      <img src="https://img.shields.io/github/license/opencloudhub/gitops.svg?style=for-the-badge" alt="License">
    </a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->

<!-- TODO: make tunnel wait for ingress to be up -->

<details>
  <summary>📑 Table of Contents</summary>
  <ol>
    <li><a href="#overview">Overview</a></li>
    <li><a href="#technology-stack">Technology Stack</a></li>
    <li><a href="#architecture">Architecture</a></li>
    <li><a href="#project-structure">Project Structure</a></li>
    <li><a href="#getting-started">Getting Started</a></li>
    <li><a href="#local-development">Local Development</a></li>
    <li><a href="#platform-components">Platform Components</a></li>
    <li><a href="#mlops-pipelines">MLOps Pipelines</a></li>
    <li><a href="#team-applications">Team Applications</a></li>
    <li><a href="#troubleshooting">Troubleshooting</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

______________________________________________________________________

## 🌐 Overview <a id="overview"></a>

This repository contains the complete GitOps configuration for the OpenCloudHub Kubernetes platform. It implements a declarative, Git-driven approach to infrastructure and application management using (ArgoCD)[https://argo-cd.readthedocs.io/en/stable/].

**Key Principles:**

- 🔄 **GitOps-First**: All cluster state is defined in Git - the single source of truth
- 🏗️ **App of Apps Pattern**: Hierarchical application management with self-healing
- 🔐 **Secrets Management**: External Secrets Operator syncs secrets from HashCorp Vault
- 👥 **Multi-Tenant**: Clear separation between platform infrastructure and team workloads
- 🤖 **MLOps-Ready**: Full ML pipeline support with training, evaluation, and serving

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 🛠️ Technology Stack <a id="technology-stack"></a>

| Category          | Technologies                                       |
| ----------------- | -------------------------------------------------- |
| **GitOps**        | ArgoCD, ArgoCD Image Updater                       |
| **Service Mesh**  | Istio (Ambient Mode), Gateway API                  |
| **Secrets**       | External Secrets Operator, HashCorp Vault          |
| **Certificates**  | cert-manager                                       |
| **Storage**       | CloudNative-PG (PostgreSQL), MinIO (S3-compatible) |
| **Observability** | Prometheus, Grafana, Loki, Tempo, K8s Monitoring   |
| **MLOps**         | MLflow, Argo Workflows, KubeRay                    |
| **Serving**       | Ray Serve (LLM/ML models)                          |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 🏛️ Architecture <a id="architecture"></a>

### GitOps Flow

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                              Git Repository                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           ArgoCD (Self-Managed)                          │
│  ┌─────────────┐                                                        │
│  │  Root App   │ ◄─── Watches all ApplicationSets                       │
│  └──────┬──────┘                                                        │
│         │                                                               │
│         ├──────────────────┬──────────────────┬────────────────────┐    │
│         ▼                  ▼                  ▼                    ▼    │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌───────────┐│
│  │  Security   │    │  Platform   │    │   Teams     │    │ AppProjs  ││
│  │ AppSet      │    │  AppSet     │    │  AppSet     │    │           ││
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └───────────┘│
└─────────┼──────────────────┼──────────────────┼─────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
   │ Namespaces  │    │    Core     │    │     AI      │
   │ RBAC        │    │  Storage    │    │  Demo-App   │
   │ Limits      │    │ Observability│   │             │
   └─────────────┘    │   MLOps     │    └─────────────┘
                      └─────────────┘
```

### App of Apps Pattern

The repository uses ArgoCD's **App of Apps** pattern for hierarchical management:

1. **Root App** (`src/root-app.yaml`): The top-level application that ArgoCD watches
1. **ApplicationSets**: Generate applications dynamically based on directory structure
   - `security/` - Namespaces, RBAC, ResourceQuotas
   - `platform/` - Infrastructure components
   - `teams/` - Team-specific workloads
1. **Self-Management**: ArgoCD manages itself through the root app

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 📁 Project Structure <a id="project-structure"></a>

```text
.
├── local-development/                  # Local dev environment scripts
│   ├── start-dev.sh                    # Main setup script (Minikube + Vault + Bootstrap)
│   ├── setup-vault.sh                  # Local Vault container + secret seeding
│   ├── manifests/                      # PersistentVolumes for local storage
│   └── output/                         # Generated dev summaries (credentials, etc.)
│
├── scripts/
│   ├── bootstrap.sh                    # GitOps bootstrap (ArgoCD + Root App)
│   └── _utils.sh                       # Shared shell utilities
│
└── src/
    ├── root-app.yaml                   # 🎯 Root Application (self-managed ArgoCD)
    │
    ├── app-projects/                   # ArgoCD AppProjects (RBAC boundaries)
    │   ├── platform.yaml               # Platform team permissions
    │   └── teams.yaml                  # Team permissions
    │
    ├── application-sets/               # ApplicationSet generators
    │   ├── platform/                   # Watches src/platform/*/*
    │   ├── security/                   # Security policies (sync-wave: 0)
    │   └── teams/                      # Watches src/teams/*/*
    │
    ├── security/                       # 🔐 Cluster-wide security (deployed first)
    │   ├── namespaces/                 # All namespace definitions
    │   ├── rbac/                       # Role-based access control
    │   └── resource-limits/            # ResourceQuotas and LimitRanges
    │
    ├── platform/                       # 🏗️ Platform infrastructure
    │   ├── core/                       # Essential services
    │   │   ├── argocd/                 # ArgoCD
    │   │   ├── argo-image-updater/     # ArgoCD + Image Updater
    │   │   ├── cert-manager/           # TLS certificates
    │   │   ├── external-secrets/       # Vault integration
    │   │   ├── gateway/                # Istio Gateway
    │   │   └── istio/                  # Service mesh
    │   │
    │   ├── storage/                    # 💾 Data layer
    │   │   ├── cloudnative-pg/         # PostgreSQL clusters
    │   │   ├── minio-operator/         # MinIO operator
    │   │   ├── minio-tenant/           # S3-compatible storage
    │   │   └── pgadmin/                # Database UI (dev only)
    │   │
    │   ├── observability/              # 📊 Monitoring stack
    │   │   ├── prometheus/             # Metrics collection
    │   │   ├── grafana/                # Dashboards
    │   │   ├── loki/                   # Log aggregation
    │   │   ├── tempo/                  # Distributed tracing
    │   │   └── k8s-monitoring/         # Kubernetes metrics
    │   │
    │   └── mlops/                      # 🤖 ML infrastructure
    │       ├── mlflow/                 # Experiment tracking & model registry
    │       ├── argo-workflows/         # ML pipelines
    │       └── ray-operator/           # Model serving (KubeRay)
    │
    └── teams/                          # 👥 Team workloads
        ├── ai/
        │   ├── models-base/            # Pre-built LLM services (Qwen, etc.)
        │   └── models-custom/          # Custom trained models (Wine, Fashion-MNIST)
        │
        └── demo-app/
            └── demo-app-genai-backend/ # LangChain RAG demo
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 🚀 Getting Started <a id="getting-started"></a>

### Important Note for External Users

This repository is configured for the OpenCloudHub organization. To use it for your own projects, you'll need to:

1. **Fork this repository** to your own GitHub organization
1. **Update repository URLs** in:
   - `src/application-sets/*/applicationset.yaml` (change `opencloudhub/gitops`)
   - `src/platform/mlops/argo-workflows/workflow-templates/` (Git URLs)
1. **Create SSH deploy keys** for ArgoCD to access your repositories
1. **Configure secrets** in your own Vault instance or secret manager

### Prerequisites

| Requirement                               | Purpose                  |
| ----------------------------------------- | ------------------------ |
| Docker                                    | Container runtime        |
| Minikube                                  | Local Kubernetes cluster |
| kubectl                                   | Kubernetes CLI           |
| kustomize                                 | Manifest generation      |
| NVIDIA drivers + nvidia-container-toolkit | GPU support (optional)   |

### SSH Keys Setup

ArgoCD needs SSH access to your Git repositories:

```bash
# Create directory for keys
mkdir -p ~/.ssh/opencloudhub

# Generate deploy key for GitOps repo (no passphrase)
ssh-keygen -t ed25519 -C "argocd_gitops@yourdomain.com" \
  -f ~/.ssh/opencloudhub/argocd_gitops_ed25519 -N ""

# Generate deploy key for data registry (if using DVC)
ssh-keygen -t ed25519 -C "argo_data_registry@yourdomain.com" \
  -f ~/.ssh/opencloudhub/argo_data_registry_ed25519 -N ""

# Add public keys to your GitHub repo as deploy keys
cat ~/.ssh/opencloudhub/argocd_gitops_ed25519.pub
cat ~/.ssh/opencloudhub/argo_data_registry_ed25519.pub
```

Add the gitops secret to the gitops repo and the data registry key to the [Data Registry](https://github.com/OpenCloudHub/data-registry):

- Settings → Deploy Keys → Add Key
- Enable "Allow write access" (required for Image Updater)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 💻 Local Development <a id="local-development"></a>

The local development environment uses Minikube with a local HashCorp Vault for secrets management.

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/opencloudhub/gitops.git
cd gitops

# 2. Configure secrets
cp local-development/.env.secrets.example local-development/.env.secrets
# Edit .env.secrets with your credentials

# 3. Start everything
bash local-development/start-dev.sh
```

### What the Setup Script Does

The `start-dev.sh` script performs the following steps:

| Step                    | Description                                         |
| ----------------------- | --------------------------------------------------- |
| 1. **Start Minikube**   | Creates cluster with 16 CPUs, 36GB RAM, GPU support |
| 2. **Create Storage**   | Sets up PersistentVolumes for MinIO and PostgreSQL  |
| 3. **Setup Vault**      | Starts local Vault container and seeds all secrets  |
| 4. **Bootstrap GitOps** | Installs ArgoCD and deploys root application        |
| 5. **Start Tunnel**     | Enables LoadBalancer access via `minikube tunnel`   |
| 6. **Configure Hosts**  | Adds entries to `/etc/hosts` for local domains      |

### Vault Secrets

The `setup-vault.sh` script starts a local Vault in dev mode and seeds it with secrets from `local-development/.env.secrets`:

```bash
# Vault runs at http://127.0.0.1:8200
# Default token: 1234 (or as configured)

# View seeded secrets
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=1234
vault kv list kv/
```

**Seeded secret paths:**

- `kv/platform/gitops/repos/*` - Git repository SSH keys
- `kv/platform/docker/registry` - Docker Hub credentials
- `kv/platform/storage/cnpg/*` - PostgreSQL credentials
- `kv/platform/storage/minio-tenant/credentials` - MinIO access keys
- `kv/platform/observability/grafana/credentials` - Grafana admin
- `kv/ai/storage/cnpg/mlflow` - MLflow database

### Bootstrap Process

The `bootstrap.sh` script:

1. **Prepares the cluster** - Creates namespaces, pre-installs essential CRDs
1. **Creates secrets** - ArgoCD repository credentials, Vault token
1. **Installs ArgoCD** - Deploys base ArgoCD using Kustomize
1. **Deploys applications** - Applies root app and ApplicationSets

After bootstrap, ArgoCD takes over and reconciles all applications automatically.

### Local Access URLs

Once running, access services at:

| Service                            | URL                                                                      |
| ---------------------------------- | ------------------------------------------------------------------------ |
| ArgoCD                             | https://argocd.internal.opencloudhub.org                                 |
| Grafana                            | https://grafana.internal.opencloudhub.org                                |
| MLflow                             | https://mlflow.ai.internal.opencloudhub.org                              |
| Argo Workflows                     | https://workflows.ai.internal.opencloudhub.org                           |
| MinIO Console                      | https://minio.internal.opencloudhub.org                                  |
| pgAdmin                            | https://pgadmin.internal.opencloudhub.org                                |
| Wine Classifier API                | https://api.opencloudhub.org/models/custom/wine-classifier/docs          |
| Wine Classifier Dashboard          | https://wine-classifier.dashboard.opencloudhub.org/                      |
| Fashin MNIST Classifier API        | https://api.opencloudhub.org/models/custom/fashion-mnist-classifier/docs |
| Fashion MNIST Classifier Dashboard | https://fashion-mnist-classifier.dashboard.opencloudhub.org/             |
| Qwen Base Dashboard                | https://qwen-0.5b.dashboard.opencloudhub.org/                            |
| Rag Demo App Backend               | https://demo-app.opencloudhub.org/api/docs                               |

### Connecting to pgAdmin

pgAdmin is included for database inspection during development:

1. Access https://pgadmin.internal.opencloudhub.org
1. Login with credentials from your `local-development/.env.secrets`
1. Add a new server connection:

| Field    | Value                                            |
| -------- | ------------------------------------------------ |
| Host     | `mlflow-db-cluster-rw.storage.svc.cluster.local` |
| Port     | `5432`                                           |
| Database | `mlflow`                                         |
| Username | (from `local-development/.env.secrets`)          |
| Password | (from `local-development/.env.secrets`)          |
| SSL Mode | `disable`                                        |

4. Do the PGVector database of the demo RAG app

### Environment Variables

Control script behavior with environment variables:

```bash
# Skip Vault setup (use existing)
SKIP_VAULT=true bash local-development/start-dev.sh

# Skip GitOps bootstrap (just start Minikube)
SKIP_BOOTSTRAP=true bash local-development/start-dev.sh

# Preview without making changes
DRY_RUN=true bash local-development/start-dev.sh

# Customize Minikube resources
MINIKUBE_CPUS=8 MINIKUBE_MEMORY=16g bash local-development/start-dev.sh
```

### GitHub Actions for Local Testing

To test CI/CD workflows against your local Minikube cluster:

#### 1. Deploy Self-Hosted GitHub Runner

Deploy a self-hosted runner that connects to your local cluster. You have two options:

**Option A: Use our pre-built runner (recommended)**

We provide a ready-to-use dockerized runner at [gh-actions-local-runner](https://github.com/OpenCloudHub/gh-actions-local-runner) with detailed setup instructions.

**Option B: Set up your own runner**

Follow GitHub's official guide:

- Settings → Actions → Runners → New self-hosted runner
- Select your OS and follow the installation steps

#### 2. Store Kubeconfig as GitHub Secret

Create a portable kubeconfig with embedded certificates and store it as `KUBE_CONFIG`:

```bash
# Create kubeconfig with embedded certificates
kubectl config view --flatten --minify > /tmp/kubeconfig-embedded.yaml

# Base64 encode for GitHub secret
cat /tmp/kubeconfig-embedded.yaml | base64 -w 0

# Clean up
rm /tmp/kubeconfig-embedded.yaml
```

Add the base64 output as a repository secret:

- Settings → Secrets and variables → Actions → New repository secret
- Name: `KUBE_CONFIG`
- Value: (paste the base64 output)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 🏗️ Platform Components <a id="platform-components"></a>

### Core Services (src/platform/core/)

| Component                | Description                                                 |
| ------------------------ | ----------------------------------------------------------- |
| **ArgoCD**               | GitOps controller - self-managed, watches this repository   |
| **ArgoCD Image Updater** | Automatically updates image tags and commits to Git         |
| **cert-manager**         | Automated TLS certificate management with Let's Encrypt     |
| **External Secrets**     | Syncs secrets from HashCorp Vault to Kubernetes             |
| **Istio**                | Service mesh (ambient mode) for mTLS and traffic management |
| **Gateway**              | Istio Gateway API for ingress routing                       |

### Storage (src/platform/storage/)

| Component          | Description                                                    |
| ------------------ | -------------------------------------------------------------- |
| **CloudNative-PG** | Production-grade PostgreSQL operator with HA, backups, pooling |
| **MinIO Operator** | Manages MinIO tenant deployments                               |
| **MinIO Tenant**   | S3-compatible object storage for artifacts, datasets, models   |
| **pgAdmin**        | Web UI for PostgreSQL (development only)                       |

**Database Clusters:**

- `mlflow-db-cluster` - MLflow experiment tracking and model registry
- `demo-app-db-cluster` - Demo application database with PGVector vectordatabase

### Observability (src/platform/observability/)

| Component          | Description                                                   |
| ------------------ | ------------------------------------------------------------- |
| **Prometheus**     | Metrics collection and alerting                               |
| **Grafana**        | Dashboards and visualization                                  |
| **Loki**           | Log aggregation (promtail → loki → grafana)                   |
| **Tempo**          | Distributed tracing                                           |
| **k8s-monitoring** | Kubernetes-native metrics (kube-state-metrics, node-exporter) |

### MLOps (src/platform/mlops/)

| Component          | Description                                                                |
| ------------------ | -------------------------------------------------------------------------- |
| **MLflow**         | Experiment tracking, model registry, prompt registry                       |
| **Argo Workflows** | Kubernetes-native workflow engine for ML and Data pipelines                |
| **KubeRay**        | Ray cluster operator for distributed ML, data operations and model serving |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 🤖 MLOps Pipelines <a id="mlops-pipelines"></a>

### Workflow Templates

Located in `src/platform/mlops/argo-workflows/workflow-templates/`:

```text
workflow-templates/
├── mlops/
│   ├── mlops-pipeline.yaml      # Full CI/CD pipeline for ML models
│   └── modules/
│       ├── training.yaml        # Model training step
│       ├── mlflow.yaml          # MLflow integration (compare, promote)
│       ├── testing.yaml         # Model testing/validation
│       └── deployment.yaml      # GitOps deployment trigger
│
└── data/
    ├── base-data-pipeline.yaml          # Trigger base base pipelines
    ├── readmes-embeddings-pipeline.yaml # Example: README embeddings
    └── modules/
        └── ...                          # Data processing modules
```

### MLOps Pipeline Stages

The main `mlops-pipeline.yaml` orchestrates:

```text
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Training  │───►│   Compare   │───►│   Testing   │───►│  Deployment │
│             │    │  & Promote  │    │  (Staging)  │    │  (GitOps)   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │                  │
       ▼                  ▼                  ▼                  ▼
   MLflow Run      ci.model → staging   Validation      Update Git →
   + Metrics       if better than       Tests           ArgoCD Sync
                   champion
```

**Pipeline Features:**

- **Training** (`training.yaml`): Runs training job, logs to MLflow, registers model as `ci.<model_name>`
- **Compare & Promote** (`mlflow.yaml`): Compares against current champion, promotes to staging if improved
- **Testing** (`testing.yaml`): Runs validation tests on staging model (dummy currently)
- **Deployment** (`deployment.yaml`): Updates GitOps repo to trigger ArgoCD sync as well as tagging mlflow prod model

### Model Registry Convention

MLflow models follow a namespace convention:

| Registry          | Purpose                                       |
| ----------------- | --------------------------------------------- |
| `ci.<model>`      | Continuous Integration - newly trained models |
| `staging.<model>` | Staging - promoted for testing                |
| `prod.<model>`    | Production - deployed to serving              |

**Aliases:**

- `@champion` - Current production model
- `@previous` - Previous champion (for rollback)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## �� Team Applications <a id="team-applications"></a>

### AI Models (src/teams/ai/)

#### Base Models (models-base/)

Pre-configured foundational LLM deployments using Ray Serve:

| Model                   | Description                                     |
| ----------------------- | ----------------------------------------------- |
| `qwen-llm-service.yaml` | Qwen 2.5 0.5B Instruct - Small LLM for RAG/chat |

Features:

- Fractional GPU allocation (0.49 GPU per replica)
- OpenAI-compatible API endpoint
- Automatic scaling with Ray Serve

#### Custom Models (models-custom/)

Team-trained models deployed via Ray Serve:

| Model                                   | Description                                                                  |
| --------------------------------------- | ---------------------------------------------------------------------------- |
| `wine-classifier-service.yaml`          | Wine quality prediction (SkLearn + MLflow + Ray Serve + FastAPI)             |
| `fashion-mnist-classifier-service.yaml` | Image classification demo (Pytorch Lightning + MLflow + Ray Serve + FastAPI) |

### Demo Application (src/teams/demo-app/)

#### GenAI Backend (demo-app-genai-backend/)

A LangChain-based RAG application demonstrating:

- Integration with the Qwen LLM service
- PostgreSQL vector store (pgvector)
- FastAPI REST API

Deployed via ArgoCD Image Updater for automatic updates.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 🔧 Troubleshooting <a id="troubleshooting"></a>

### Bootstrap Failures

If the bootstrap fails, you can debug manually:

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Port-forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at https://localhost:8080
# Get admin password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Application Sync Issues

```bash
# Check application status
kubectl get applications -n argocd

# Get detailed sync status
kubectl describe application <app-name> -n argocd

# Force refresh
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### External Secrets Not Syncing

```bash
# Check External Secrets Operator
kubectl get pods -n external-secrets

# Check ClusterSecretStore
kubectl get clustersecretstore

# Check specific ExternalSecret
kubectl describe externalsecret <name> -n <namespace>

# Verify Vault connectivity
kubectl logs -n external-secrets deploy/external-secrets
```

### Pod Startup Issues

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check resource constraints
kubectl get limitrange,resourcequota -n <namespace>
```

### Minikube Tunnel Issues

```bash
# Check tunnel status
ps aux | grep "minikube tunnel"

# Restart tunnel
sudo pkill -f "minikube tunnel"
sudo minikube tunnel

# Verify LoadBalancer IPs
kubectl get svc -A | grep LoadBalancer
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 👥 Contributing <a id="contributing"></a>

Contributions are welcome! Please read the contributing guidelines before submitting PRs.

1. Fork the repository
1. Create a feature branch (`git checkout -b feature/amazing-feature`)
1. Commit changes (`git commit -m 'Add amazing feature'`)
1. Push to branch (`git push origin feature/amazing-feature`)
1. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

## 📄 License <a id="license"></a>

Distributed under the Apache 2.0 License. See [LICENSE](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

<div align="center">
  <h3>🌟 Follow the Journey</h3>
  <p><em>Building in public • Learning together • Sharing knowledge</em></p>

<div>
    <a href="https://opencloudhub.github.io/docs">
      <img src="https://img.shields.io/badge/Read%20the%20Docs-2596BE?style=for-the-badge&logo=read-the-docs&logoColor=white" alt="Documentation">
    </a>
    <a href="https://github.com/orgs/opencloudhub/discussions">
      <img src="https://img.shields.io/badge/Join%20Discussion-181717?style=for-the-badge&logo=github&logoColor=white" alt="Discussions">
    </a>
    <a href="https://github.com/orgs/opencloudhub/projects/4">
      <img src="https://img.shields.io/badge/View%20Roadmap-0052CC?style=for-the-badge&logo=jira&logoColor=white" alt="Roadmap">
    </a>
  </div>
</div>
