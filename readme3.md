# Inception of Things 🚀

> Built a full GitOps delivery pipeline from absolute zero — no cloud, no magic buttons, just code, containers, and a pathological refusal to click things manually.

---

<!--
  📸 SCREENSHOT — Terminal hero shot:
  Capture the bonus install.sh finishing inside a dark terminal (iTerm2 / Warp).
  Show the final ╔═══ ALL DONE ═══╗ ASCII box with GitLab URL, ArgoCD URL, PAT and App URL visible.
  Keep a few lines of the install steps above it for context. Tight crop, no desktop or dock.
  Green-on-black or your actual color scheme — just make it look sharp.
-->
![Full pipeline — ALL DONE](.github/assets/banner.png)

---

## What's going on here?

Production-grade DevOps infrastructure, built entirely on a MacBook — four progressive parts, each adding a new layer until a single `./install.sh` spins up a fully automated GitOps loop. Pushing a YAML file to Git is the only human action needed to deploy to Kubernetes.

No AWS. No GCP. No clicking. Everything is code, everything is reproducible.

---

## Tech Stack

| Layer | Tool | Why |
|---|---|---|
| Virtualisation | QEMU + Apple HVF | ARM64 VMs at near-native speed on M1/M2 |
| VM orchestration | Vagrant | Reproducible environments from a single `Vagrantfile` |
| Kubernetes in-VM | k3s | Full K8s in ~70 MB — Traefik + containerd included |
| Kubernetes in-Docker | k3d | Full cluster as Docker containers — instant spin-up |
| Self-hosted Git | GitLab CE | Because depending on GitHub for a GitOps demo is ironic |
| GitOps controller | ArgoCD | Watches Git, syncs cluster, heals itself — obsessively |
| Ingress / proxy | Traefik | Built into k3s, reads Ingress objects live |
| Container runtime | containerd | The actual thing running containers under the hood |

---

## Skills You're Actually Looking At

> The concepts that matter for real DevOps/Platform/SRE roles — earned by hitting every sharp edge of each tool.

<table>
<tr>
<td>

**☸️ Kubernetes**
Pods · Deployments · ReplicaSets · Services
ConfigMaps · Ingress · Namespaces
RBAC Secrets · ArgoCD Application CRD

</td>
<td>

**🌐 Networking**
SSH local port-forwarding · NAT traversal
Virtual host routing · ClusterIP
Loopback aliasing · Traefik reverse proxy

</td>
</tr>
<tr>
<td>

**🔄 GitOps**
Full ArgoCD pipeline: repo wiring
Automated sync · self-heal · prune
Rolling updates triggered by `git push`

</td>
<td>

**⚙️ Infrastructure as Code**
Vagrant multi-machine provisioning
Idempotent shell scripts
Fully reproducible environment from zero

</td>
</tr>
<tr>
<td>

**🏗️ Self-hosted Tooling**
GitLab CE: deployed, bootstrapped and
configured entirely via its own REST API
— zero UI interaction

</td>
<td>

**🐛 Real Debugging**
k3d container isolation · GitLab Rails warmup gap
ArgoCD secret label schema · macOS Keychain
git interception · CSRF session auth flows

</td>
</tr>
</table>

---

## The Parts

### Part 1 — Two-Node k3s Cluster

Two QEMU ARM64 VMs provisioned from a single `Vagrantfile`. The server installs k3s and generates a join token; a Vagrant trigger SSHes in, extracts it, and injects it into the worker automatically. An SSH port-forward (`host:6443 → VM:6443`) makes `kubectl` work from macOS without any static networking.

```bash
cd p1 && vagrant up
kubectl get nodes
# aatkiS    Ready    control-plane   2m
# aatkiSW   Ready    <none>          1m
```

```mermaid
flowchart LR
    subgraph macOS["🖥️  macOS Host"]
        style macOS fill:#1e1e2e,stroke:#89b4fa,color:#cdd6f4
        kubectl("kubectl"):::blue
        tunnel("SSH Tunnel\nlocalhost:6443 → VM:6443"):::blue
        token_file("/tmp/k3s_token_p1"):::slate
    end

    subgraph server["⚙️  QEMU VM — aatkiS (server)"]
        style server fill:#1e1e2e,stroke:#a6e3a1,color:#cdd6f4
        k3s_server("k3s server\nAPI :6443"):::green
        node_token("node-token"):::green
    end

    subgraph worker["🔧  QEMU VM — aatkiSW (worker)"]
        style worker fill:#1e1e2e,stroke:#fab387,color:#cdd6f4
        k3s_agent("k3s agent"):::orange
    end

    kubectl -->|HTTPS| tunnel
    tunnel -->|SSH channel| k3s_server
    k3s_server --> node_token
    node_token -->|Vagrant trigger extracts| token_file
    token_file -->|provisioner injects| k3s_agent
    k3s_agent -->|registers as node| k3s_server

    classDef blue fill:#313244,stroke:#89b4fa,color:#89b4fa
    classDef green fill:#313244,stroke:#a6e3a1,color:#a6e3a1
    classDef orange fill:#313244,stroke:#fab387,color:#fab387
    classDef slate fill:#313244,stroke:#6c7086,color:#6c7086
```

**Concepts:** k3s server/agent architecture · node join tokens · kubeconfig · SSH port-forwarding · Vagrant triggers · QEMU HVF

---

### Part 2 — Ingress Routing: One IP, Three Apps

One VM, one k3s cluster, three apps, one IP. Each app's HTML lives in a **ConfigMap** mounted into nginx — no custom images. Traefik reads the `Host:` header live and routes accordingly. QEMU NAT is bypassed via an SSH tunnel + loopback alias.

```bash
curl -H "Host: app1.com" http://192.168.56.110   # ✅ glassmorphism gradient
curl -H "Host: app2.com" http://192.168.56.110   # ✅ neon green terminal
curl http://192.168.56.110                         # ✅ default backend
```

<!--
  📸 SCREENSHOT — Three browser tabs (or three curl outputs in split panes) showing
  each app looking visually distinct: the purple gradient one, the neon green matrix one,
  and the dark red particles one. Use a browser extension like "ModHeader" to set the
  Host header in the browser for a cleaner visual. All pointing at 192.168.56.110.
-->
![Three apps — one IP, routed by Host header](.github/assets/p2-three-apps.png)

```mermaid
flowchart LR
    curl("curl\n-H 'Host: app1.com'"):::slate

    subgraph mac["🖥️  macOS Host"]
        style mac fill:#1e1e2e,stroke:#89b4fa,color:#cdd6f4
        lo0("lo0 alias\n192.168.56.110"):::blue
        sshtun("SSH Tunnel\n:80 → VM:80"):::blue
    end

    subgraph vm["⚙️  QEMU VM — ediabS"]
        style vm fill:#1e1e2e,stroke:#cba6f7,color:#cdd6f4
        traefik("Traefik :80"):::purple

        subgraph k3s["k3s cluster"]
            style k3s fill:#181825,stroke:#585b70,color:#cdd6f4
            ingress("Ingress rules"):::purple
            svc1("app1-service"):::green
            svc2("app2-service"):::yellow
            svc3("app3-service"):::red
            pod1("app1 Pod\nnginx + ConfigMap"):::green
            pod2("app2 Pod\nnginx + ConfigMap"):::yellow
            pod3("app3 Pod\nnginx + ConfigMap"):::red
        end
    end

    curl --> lo0 --> sshtun --> traefik --> ingress
    ingress -->|"Host: app1.com"| svc1 --> pod1
    ingress -->|"Host: app2.com"| svc2 --> pod2
    ingress -->|"no match → default"| svc3 --> pod3

    classDef blue   fill:#313244,stroke:#89b4fa,color:#89b4fa
    classDef purple fill:#313244,stroke:#cba6f7,color:#cba6f7
    classDef green  fill:#313244,stroke:#a6e3a1,color:#a6e3a1
    classDef yellow fill:#313244,stroke:#f9e2af,color:#f9e2af
    classDef red    fill:#313244,stroke:#f38ba8,color:#f38ba8
    classDef slate  fill:#313244,stroke:#6c7086,color:#6c7086
```

**Concepts:** Deployment · Service · ConfigMap volume mounts · Ingress host routing · Traefik · SSH NAT traversal · loopback aliasing

---

### Part 3 — k3d + ArgoCD: GitOps Enters the Chat

Kubernetes inside Docker, controlled by Git. k3d spins up a full cluster as containers. ArgoCD watches a repo and is personally offended by any drift between Git and the cluster — it corrects it immediately, automatically, without asking.

Change the image tag in `deployment.yaml`, push → ArgoCD detects the diff → rolls out the new version → `Synced ✅ Healthy ✅`. Zero `kubectl apply`.

<!--
  📸 SCREENSHOT — ArgoCD UI at http://localhost:8080 (dark theme).
  Show the wil-playground Application card with Synced ✅ Healthy ✅ status.
  Expand the resource tree: Application → Deployment → ReplicaSet → Pod.
  Ideally capture it mid-sync (yellow "Syncing" → green) for drama.
-->
![ArgoCD UI — wil-playground Synced and Healthy](.github/assets/p3-argocd-ui.png)

```mermaid
flowchart TD
    dev("👨‍💻 git push\nimage tag v1 → v2"):::slate

    subgraph repo["📦  Git Repository"]
        style repo fill:#1e1e2e,stroke:#f9e2af,color:#cdd6f4
        manifest("deployment.yaml"):::yellow
    end

    subgraph docker["🐳  Docker — k3d cluster (iotcluster)"]
        style docker fill:#1e1e2e,stroke:#89b4fa,color:#cdd6f4

        subgraph argocd["argocd namespace"]
            style argocd fill:#181825,stroke:#cba6f7,color:#cdd6f4
            ctrl("ArgoCD Controller\nreconcile every 3 min"):::purple
        end

        subgraph devns["dev namespace"]
            style devns fill:#181825,stroke:#a6e3a1,color:#cdd6f4
            deploy("Deployment\nwil-playground"):::green
            pod_old("Pod v1 💀"):::red
            pod_new("Pod v2 ✅"):::green
        end
    end

    dev -->|push| manifest
    ctrl -->|polls repo| manifest
    manifest -->|diff → apply| deploy
    deploy --> pod_old & pod_new
    pod_old -.->|terminated| pod_new

    classDef purple fill:#313244,stroke:#cba6f7,color:#cba6f7
    classDef green  fill:#313244,stroke:#a6e3a1,color:#a6e3a1
    classDef yellow fill:#313244,stroke:#f9e2af,color:#f9e2af
    classDef red    fill:#313244,stroke:#f38ba8,color:#f38ba8
    classDef slate  fill:#313244,stroke:#6c7086,color:#6c7086
```

**Concepts:** k3d lifecycle · ArgoCD Application CRD · GitOps reconciliation · automated sync + self-heal + prune · rolling updates · namespace isolation

---

### Bonus — One Command to Rule Them All

The entire infrastructure — cluster, self-hosted Git server, GitOps controller, deployed app — from a single script.

```bash
cd bonus/scripts && ./install.sh
```

```
[1/5] k3d cluster
[2/5] GitLab CE deployed (self-hosted, inside the cluster)
[3/5] GitLab bootstrapped: CSRF login → PAT → project via REST API
[4/5] Manifests pushed to GitLab (macOS Keychain bypassed)
[5/5] ArgoCD deployed + wired to GitLab → app live at :8888
```

The non-obvious problems this solves: GitLab's `/-/health` returns 200 before the Rails API actually works (retry loop). PAT creation requires a full web session CSRF flow (GitLab 16+ removed the simple API). ArgoCD silently ignores repo secrets without a specific label + `type: git` field. macOS Keychain hijacks git credentials unless you zero out every config layer. Port-forwards die after the script exits unless you `disown` them.

<!--
  📸 SCREENSHOT — The ╔══ ALL DONE ══╗ terminal banner from the end of install.sh.
  Show all 5 URLs + PAT printed inside the box. Keep 10–15 lines of install output
  above it visible. Dark terminal. This is the money shot.
-->
![Bonus — ALL DONE banner](.github/assets/bonus-done.png)

```mermaid
flowchart TD
    script("🖥️ ./install.sh"):::slate

    subgraph docker["🐳  Docker — k3d cluster (13-cluster)"]
        style docker fill:#1e1e2e,stroke:#89b4fa,color:#cdd6f4

        subgraph gl["gitlab namespace"]
            style gl fill:#181825,stroke:#f38ba8,color:#cdd6f4
            gitlab("GitLab CE\nRails + Puma"):::red
        end

        subgraph ar["argocd namespace"]
            style ar fill:#181825,stroke:#cba6f7,color:#cdd6f4
            argocd("ArgoCD Controller"):::purple
            secret("Secret: gitlab-creds\ntype:git + PAT label"):::purple
        end

        subgraph dv["dev namespace"]
            style dv fill:#181825,stroke:#a6e3a1,color:#cdd6f4
            wil("wil-playground\n:8888 ✅"):::green
        end
    end

    pf1("port-forward\n:30090 → GitLab"):::blue
    pf2("port-forward\n:8080 → ArgoCD"):::blue
    pf3("self-healing loop\n:8888 → wil-playground"):::blue

    script -->|"① k3d create"| docker
    script -->|"② kubectl apply"| gitlab
    script -->|"③ CSRF→PAT→project"| gitlab
    script -->|"④ git push manifests"| gitlab
    script -->|"⑤ ArgoCD + patch secret"| secret
    secret --> argocd
    argocd -->|"pulls & syncs"| wil
    gitlab <-->|"internal DNS"| argocd
    script --> pf1 & pf2 & pf3
    pf3 -->|"auto-reconnect"| wil

    classDef red    fill:#313244,stroke:#f38ba8,color:#f38ba8
    classDef purple fill:#313244,stroke:#cba6f7,color:#cba6f7
    classDef green  fill:#313244,stroke:#a6e3a1,color:#a6e3a1
    classDef blue   fill:#313244,stroke:#89b4fa,color:#89b4fa
    classDef slate  fill:#313244,stroke:#6c7086,color:#6c7086
```

**Concepts:** k3d · GitLab CE self-hosting · GitLab REST API (CSRF + session auth) · ArgoCD repo secrets · GitOps E2E · macOS Keychain bypass · idempotent scripting · self-healing port-forwards

---

## Project Structure

```
.
├── p1/                   # Two-node k3s cluster (Vagrant + QEMU)
│   ├── Vagrantfile
│   └── scripts/          server.sh · worker.sh
│
├── p2/                   # Ingress routing (Vagrant + k3s + Traefik)
│   ├── Vagrantfile
│   ├── confs/            app1.yaml · app2.yaml · app3.yaml · ingress.yaml
│   └── scripts/          setup_server.sh
│
├── p3/                   # k3d + ArgoCD GitOps
│   └── scripts/          install.sh · clean.sh
│
└── bonus/                # Full self-hosted pipeline (one command)
    ├── confs/            GitLab deployment manifests
    ├── manifests/        App manifests → pushed to GitLab → synced by ArgoCD
    └── scripts/          install.sh · clean.sh · install_k3d.sh · install-gitlap.sh · install_bonus.sh
```

---

## Running It

> **Requirements:** macOS Apple Silicon · Docker Desktop · Homebrew. The bonus script handles everything else.

```bash
cd p1             && vagrant up                            # Part 1
cd p2             && vagrant up                            # Part 2
cd p3/scripts     && ./install.sh                         # Part 3
cd bonus/scripts  && ./install.sh                         # Bonus — full pipeline
```

```bash
# Cleanup — non-destructive (keeps GitLab alive for fast re-runs)
bonus/scripts/clean.sh
# Full re-run in ~2 min instead of ~8 min
bonus/scripts/clean.sh && bonus/scripts/install.sh
```
