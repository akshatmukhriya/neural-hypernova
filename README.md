# 🌌 Neural Hypernova: The JIT GPU Supercomputing Forge

![Status](https://img.shields.io/badge/Status-Industrial_Grade-ff0000?style=for-the-badge)
![Infrastructure](https://img.shields.io/badge/AWS-EKS_1.31-FF9900?style=for-the-badge)
![Networking](https://img.shields.io/badge/Cilium-eBPF-blue?style=for-the-badge)
![Orchestration](https://img.shields.io/badge/Ray-Distributed_AI-028CF0?style=for-the-badge)

**Neural Hypernova** is not a standard Kubernetes cluster. It is a sovereign, self-healing, **Just-In-Time (JIT) AI Forge**. It is designed to sit at **$0.00 cost** when idle and explode into a massive GPU supercomputer the millisecond a Python script demands it.

It bypasses traditional DevOps bottlenecks (Ingress deadlocks, ARP caches, `kube-proxy` latency) by talking directly to the metal.

---

## 💀 The Problem Statement: Why Traditional Infra Fails

Building AI Infrastructure on AWS usually leads to one of four catastrophic failures:

1.  **The "Idle Tax" Bankruptcy:** You spin up `p4d.24xlarge` nodes. Your data scientist goes to lunch. You burn **$32/hour** for nothing.
2.  **The "Webhook" Deadlock:** You try to install an Ingress Controller on a private cluster. The API server cannot reach the webhook because the CNI isn't ready. The cluster hangs forever.
3.  **The "Cold Start" Coma:** You submit a job. The Autoscaler takes 10 minutes to notice. The node boots, but the GPU driver fails. The job times out.
4.  **The "Networking" Bottleneck:** Standard `iptables` (kube-proxy) crumbles under the high-throughput UDP traffic required for distributed training (NCCL/Gloo).

---

## ⚡ The Solution: The Hypernova Protocol

We replaced the "standard" stack with a surgical, high-performance architecture:

### 1. The "Scale-to-Zero" Paradox
Instead of running GPU nodes constantly, we run a single **t3.large "Brain" (Head Node)**.
*   **Idle State:** 1 CPU Node. Cost: ~$0.06/hr.
*   **Active State:** The Ray Brain detects a resource request (`num_gpus=1`) and signals **Karpenter**.
*   **Result:** Karpenter bypasses the scheduler and talks directly to the EC2 Fleet API, launching Spot Instances in **<45 seconds**.

### 2. Network Sovereignty (Cilium eBPF)
We deleted `kube-proxy`.
*   **Technology:** Cilium running in **Direct Routing** mode.
*   **Benefit:** Zero-overhead switching. Ray workers talk to each other via eBPF maps, bypassing the Linux network stack's connection tracking tables. This eliminates the "DNS Blackout" seen in high-load clusters.

### 3. The "Spectator" Protocol (Hardware Bypass)
Kubernetes Ingress Controllers are slow and prone to webhook failures.
*   **The Hack:** We use a custom **Jockey Script** to bypass Kubernetes Ingress entirely.
*   **Mechanism:** The script uses the AWS CLI to physically map the EC2 Instance ID of the Head Node to a **Network Load Balancer (NLB)** Target Group on Port 30265.
*   **Result:** Instant, unblockable access to the Ray Dashboard, immune to K8s webhook failures.

---

## 🏗️ Architecture

```text
    [ Data Scientist ]
           |
           | (1. Submits Job)
           v
+--------------------------+                         +-------------------------+
|    The Brain (Head)      | <==== (Direct TCP) ===> | Hardware NLB (Bypass) |
|   (t3.large / CPU)       |                         +-------------------------+
+--------------------------+                                      ^
           |                                                      |
           | (2. Signals Demand)                         (User Dashboard)
           v
+--------------------------+
|   Karpenter Controller   |
+--------------------------+
           |
           | (3. EC2 Fleet API)
           v
+--------------------------+
|     AWS Spot Market      |
+--------------------------+
           |
           | (4. Provisions Metal)
           v
+--------------------------+           +--------------------------+
|  GPU Node (g5.2xlarge)   | <=======> | GPU Node (p4d.24xlarge)  |
+--------------------------+   eBPF    +--------------------------+
       (Worker 1)          (Cilium)           (Worker 2)
```

---
## 🏆 Why This Is The "Best & Unique"

| Feature | Standard EKS | Neural Hypernova |
| :--- | :--- | :--- |
| **Network** | kube-proxy (iptables) | **Cilium eBPF** (Kernel bypass) |
| **Scaling** | Cluster Autoscaler (3-5 mins) | **Karpenter** (Just-In-Time, <60s) |
| **Cost** | Fixed Capacity (Expensive) | **Spot-Prioritized** (Scale-to-Zero) |
| **Dashboard** | Complex Ingress/ALB Setup | **Spectator Protocol** (Hardware Hack) |
| **State** | Local/Fragile | **S3 Sovereign State** (Dynamically Injected) |
| **Deployment** | Multi-folder Modules | **Atomic Monolith** (Single `main.tf`) |

---

## 📂 Repository Structure

```text
neural-hypernova/
├── hypernova                # The Jockey Script (Orchestrator)
├── infra/
│   └── terraform/
│       └── main.tf          # The Atomic V54.0.0 Blueprint
├── k8s/
│   ├── core/
│   │   └── karpenter-gpu-pool.yaml  # The Supply Chain definitions
│   └── ai-forge/
│       └── ray-cluster.yaml         # The Artificial Intelligence Brain
└── patch_network.sh         # Emergency Surgical Tool for Tag Injection
```
---

## 🚀 Usage Cases

### 1. LLM Fine-Tuning (The "Spike")

- Cluster sits idle all night ($0).
- 8:00 AM: User submits Llama-3-70b fine-tuning job.
- 8:01 AM: 4x g5.48xlarge nodes appear, execute training.
- 10:00 AM: Job finishes. Nodes terminate. Cost returns to $0.

### 2. Flash Demos

- Need to show a VC a working supercomputer? Run `./hypernova ignite`.
- Show the demo.
- Run `./hypernova nuke`. Total cost: ~$0.15.

### 3. High-Frequency Retraining

- RL (Reinforcement Learning) pipelines that need massive parallel simulation for 10 minutes every hour.

---

## 🎮 The Jockey Script: Instructions

The system is controlled by a single bash executable: `hypernova`.

### 1. Ignite (Deployment)

Builds the VPC, EKS Control Plane, and installs Cilium/Karpenter.

```bash
./hypernova ignite
```

- **Auto-heals:** Automatically cleans ghost Elastic IPs and conflicting Log Groups.
- **Injects:** Dynamic S3 backend to prevent state-locking collisions.

---

## 2. Demo (The Spectator)

Deploys the "Hardware Bypass" to expose the Ray Dashboard.

```bash
./hypernova demo
```

Output :
```bash
🚀 DASHBOARD LIVE: http://hyp-lb-xxxx.elb.amazonaws.com:8265
```

---

## 3. Nuke (Erasure)

Destroys everything to stop billing.

```bash
./hypernova nuke
```

- Safety: Aggressively hunts down orphaned Load Balancers and NAT Gateways that Terraform often misses.

---

## ⚔️ War Stories (Known Failures & Fixes)

This architecture was born from the ashes of 50 failed deployments.

### The Identity Paradox:
- **Issue:** EKS 1.31 Access Entries collide if you map the creator user twice.
- **Fix:** We rely on `enable_cluster_creator_admin_permissions = true` and strictly ban manual IAM mappings for the runner role.

### The Zombie Log Group:
- **Issue:** Terraform crashes because CloudWatch Log Groups usually survive cluster deletion.
- **Fix:** V54.0.0 explicitly sets `create_cloudwatch_log_group = false`. We don't need logs; we need speed.

### The Silent Network Rejection:
- **Issue:** Karpenter fails to launch nodes because Subnets lack discovery tags.
- **Fix:** The `patch_network.sh` script bypasses Terraform state to hot-patch `karpenter.sh/discovery` tags directly onto the AWS resources.

### The DNS Blackout:
- **Issue:** Cilium vs. AWS Kube-Proxy conflict causes CoreDNS to drop UDP packets.
- **Fix:** We nuke the kube-proxy daemonset immediately after ignition.

---

## 📜 License

The Unlicense (Public Domain).  
Architecture is free. Execution is priceless.


