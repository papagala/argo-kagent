# 🚀 Kagent GitOps Demo with ArgoCD

> **Production-Ready GitOps Demo** 🎪 Complete Kubernetes + ArgoCD workflow for AI agent platform deployment

<div align="center">

[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/argo-cd/)
[![Helm](https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)](https://helm.sh/)
[![OpenAI](https://img.shields.io/badge/OpenAI-412991?style=for-the-badge&logo=openai&logoColor=white)](https://openai.com/)

</div>

## 🎯 What This Demo Shows

This repository demonstrates a **complete GitOps workflow** for deploying an AI agent platform using:

- **Kind** - Local Kubernetes cluster for development
- **ArgoCD** - GitOps continuous delivery 
- **Helm** - Kubernetes package management
- **Kagent** - AI Agent platform with OpenAI integration
- **Model Context Protocol (MCP)** - AI tool integration framework

Perfect for learning GitOps principles, Kubernetes deployments, and AI agent architectures!

## 🌟 Quick Start

```bash
# 1. Install prerequisites  
make install-tools

# 2. Create Kind cluster
make create-cluster

# 3. Configure environment
make env-template
# Edit .env file with your OPENAI_API_KEY

# 4. Deploy everything
make setup

# 5. Access the services
# ArgoCD: https://localhost:8080 
# Kagent UI: http://localhost:8090
```

## 📋 Prerequisites

### Required Tools

```bash
# macOS (using Homebrew)
brew install kubectl argocd helm kind podman
```

### Required Configuration

1. **OpenAI API Key** (Required)
   - Get from: https://platform.openai.com/api-keys
   - Add to `.env` file as `OPENAI_API_KEY=sk-...`

2. **CA Bundle** (Optional, for corporate environments)
   - Set `CA_BUNDLE_PATH` in `.env` if you need custom certificates

## 📁 Repository Structure

```
argo-kagent/
├── 📄 Makefile                  # Build automation
├── 🚀 setup-kagent.sh          # Main setup script
├── 📝 .env.template             # Environment configuration
├── 📂 argocd/                   # ArgoCD application definitions
├── 📂 kagent-crds/             # Kagent Custom Resource Definitions
└── 📂 kagent/                  # Main Kagent Helm chart
```

## 🔧 Configuration

Environment Variables (`.env` file):

```bash
# Required: OpenAI API Key for AI functionality
OPENAI_API_KEY="sk-proj-your-openai-api-key-here"

# Optional: Kind cluster name (default: kagent-demo)
KIND_CLUSTER_NAME="kagent-demo"

# Optional: Custom CA certificate bundle path
# CA_BUNDLE_PATH="/path/to/your/ca-bundle.crt"
```

## 🌍 Access Points

After successful setup:

| Service | URL | Purpose | Credentials |
|---------|-----|---------|-------------|
| 🏗️ **ArgoCD** | https://localhost:8080 | GitOps Dashboard | `admin` / *auto-generated* |
| 🤖 **Kagent UI** | http://localhost:8090 | AI Agent Interface | No authentication |

Get ArgoCD password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## 📊 Available Commands

```bash
make help              # Show all available commands
make install-tools     # Install required tools (macOS)
make create-cluster    # Create Kind cluster
make setup             # Deploy Kagent with ArgoCD
make status            # Check service status
make teardown          # Remove Kagent (keep cluster)
make clean             # Clean up and delete cluster
```

## 🆘 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| 🔴 **ArgoCD not ready** | Wait longer, check `kubectl get pods -n argocd` |
| 🔴 **OpenAI API errors** | Verify `OPENAI_API_KEY` in `.env` file |
| 🔴 **Certificate errors** | Set `CA_BUNDLE_PATH` and use `./setup-kagent.sh --initial` |
| 🔴 **Port conflicts** | Run `make clean` to kill existing port-forwards |

### Debug Commands

```bash
# Check status
make status

# Check applications
kubectl get applications -n argocd
kubectl get pods -n kagent

# Force sync
argocd app sync kagent --force
```

## 🌟 Key Benefits

- ✅ **GitOps Best Practices** - Infrastructure as Code
- ✅ **Kubernetes Native** - Custom Resources and Operators  
- ✅ **AI Integration** - OpenAI-powered agents with MCP
- ✅ **Production Ready** - Helm charts, proper RBAC, health checks
- ✅ **Developer Friendly** - One-command setup

## 📚 Learning Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [GitOps Principles](https://opengitops.dev/)

---

<div align="center">

**Made with ❤️ for the Kubernetes and GitOps community**

*Perfect for learning, demos, and production deployments!* 🎪

</div>