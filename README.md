# Inception of Things

> Kubernetes, GitOps, and Infrastructure-as-Code — from a bare VM to a fully automated self-healing delivery pipeline.

---

<!-- SCREENSHOT: terminal showing vagrant up + all pods Running -->
![banner placeholder](.github/assets/banner.png)

---

## What is this?

A four-part project that progressively builds a complete **DevOps infrastructure** from scratch — no cloud provider, no managed services, just a MacBook, a few shell scripts, and a deep understanding of how modern deployments actually work.

Each part isolates one layer of the stack. By the end, `./install.sh` in the bonus part spins up a production-grade GitOps pipeline in under 10 minutes, fully automated.

---

## The Stack

| Layer | Technology |
|---|---|
| Virtualisation | QEMU + Apple HVF (ARM64, near-native speed) |
| VM orchestration | Vagrant |
| Kubernetes (in-VM) | k3s (single binary, Traefik built-in) |
| Kubernetes (containerised) | k3d (k3s inside Docker) |
| Git server | GitLab CE (self-hosted) |
| GitOps controller | ArgoCD |
| Ingress / reverse proxy | Traefik |
| Container runtime | containerd |

---

## Parts

### Part 1 — k3s Cluster with Vagrant

<!-- SCHEMA: two VMs, server ←token→ worker, kubectl from host via SSH tunnel -->
![p1 schema placeholder](.github/assets/p1-schema.png)

Two VMs provisioned from code. One runs the k3s **server**, the other joins as an **agent**. The server's join token is extracted over SSH and passed to the worker automatically — no manual steps.

An SSH port-forward tunnels the Kubernetes API (`localhost:6443`) from inside QEMU to the host, so `kubectl` works from the Mac without any networking magic.

**Concepts in play:** k3s server/agent architecture, node join tokens, kubeconfig, SSH local port forwarding, Vagrant multi-machine provisioning, QEMU ARM64 virtualisation.

---

### Part 2 — Kubernetes Ingress Routing

<!-- SCHEMA: curl → loopback alias → SSH tunnel → VM → Traefik → 3 services -->
![p2 schema placeholder](.github/assets/p2-schema.png)

One VM, one k3s cluster, three apps, one IP — the classic **virtual hosting** problem solved with Kubernetes Ingress.

Each app is served by nginx, with its HTML stored in a **ConfigMap** and mounted as a volume. No custom Docker images, no registry. Traefik reads the `Host:` header on every request and routes to the matching Service.

```bash
curl -H "Host: app1.com" http://192.168.56.110   # → App 1
curl -H "Host: app2.com" http://192.168.56.110   # → App 2
curl http://192.168.56.110                         # → App 3 (default backend)
```

**Concepts in play:** Kubernetes Deployment, Service (ClusterIP), ConfigMap volume mounts, Ingress host-based routing, Traefik Ingress controller, SSH tunnel as a NAT workaround, loopback interface aliasing.

---

### Part 3 — k3d + ArgoCD

<!-- SCHEMA: k3d cluster inside Docker, ArgoCD watching a Git repo, syncing to dev namespace -->
![p3 schema placeholder](.github/assets/p3-schema.png)

Kubernetes **inside Docker** — k3d creates a full k3s cluster as a set of containers. No VM needed. ArgoCD is deployed and configured to watch a Git repository; any push to the repo is automatically reflected in the `dev` namespace.

The `wil-playground` app ships in multiple versions. Changing the image tag in the manifest and pushing triggers ArgoCD to roll out the new version — **zero manual kubectl**.

**Concepts in play:** k3d cluster management, ArgoCD Application CRD, GitOps reconciliation loop, automated sync + self-heal + prune, rolling updates, namespaces, port-forwarding.

---

### Bonus — Full GitOps Pipeline (One Command)

<!-- SCREENSHOT: install.sh running end to end — cluster → GitLab → ArgoCD → app live -->
![bonus screenshot placeholder](.github/assets/bonus-run.png)

<!-- SCHEMA: full pipeline diagram: install.sh → k3d → GitLab CE → git push → ArgoCD → dev namespace → wil-playground -->
![bonus pipeline schema placeholder](.github/assets/bonus-pipeline.png)

The entire infrastructure — cluster, self-hosted Git server, GitOps controller, application — is provisioned and wired together by a **single orchestrator script**:

```
./install.sh
```

What it does:

```
[1/5]  k3d cluster
[2/5]  GitLab CE deployed (self-hosted, no SaaS)
[3/5]  Bootstrap: PAT created, GitLab project created via API
[4/5]  Manifests pushed to GitLab via git
[5/5]  ArgoCD deployed, secret patched, Application created
       → ArgoCD pulls from GitLab, deploys to dev namespace
       → wil-playground live at http://localhost:8888
```

Port-forwards for ArgoCD UI, GitLab, and the app are started and **detached** — they survive after the script exits and auto-reconnect if a pod restarts.

**Concepts in play:** k3d, GitLab CE self-hosting, GitLab REST API (session auth, CSRF, PAT creation), ArgoCD repository secrets, GitOps with automated sync, macOS Keychain bypass for git, self-healing port-forward loops, idempotent scripting.

---

## Skills Demonstrated

```
Infrastructure as Code    Vagrant + shell provisioners, fully reproducible environments
Kubernetes internals      Pods, Deployments, Services, ConfigMaps, Ingress, Namespaces
Cluster variants          k3s (lightweight, in-VM) and k3d (containerised, Docker-based)
Networking                SSH tunnels, NAT traversal, virtual hosting, ClusterIP/Traefik routing
GitOps                    ArgoCD Application, automated sync, self-heal, prune
Self-hosted tooling       GitLab CE deployed and bootstrapped entirely via API
Automation                End-to-end idempotent install scripts, zero manual steps
Debugging                 Race conditions, API readiness probes, platform-specific quirks (macOS/ARM)
```

---

## Running It

Each part is self-contained and independent.

```bash
# Part 1 — two-node k3s cluster
cd p1 && vagrant up

# Part 2 — ingress routing
cd p2 && vagrant up

# Part 3 — k3d + ArgoCD
cd p3/scripts && ./install.sh

# Bonus — full pipeline
cd bonus/scripts && ./install.sh
```

Cleanup scripts mirror each installer:
```bash
cd p3/scripts  && ./clean.sh
cd bonus/scripts && ./clean.sh
```

> **Requirements:** macOS (Apple Silicon), Docker Desktop, Vagrant, QEMU, Homebrew.  
> The bonus `install.sh` handles its own dependency checks and installs what is missing.

---

<!-- SCREENSHOT: ArgoCD UI showing wil-playground Synced + Healthy -->
![argocd ui placeholder](.github/assets/argocd-synced.png)
