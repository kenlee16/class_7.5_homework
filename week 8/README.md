# Week 8 Homework — Managed Instance Groups & Terraform

## Resources Used

- [GCP Managed Instance Groups Docs](https://cloud.google.com/compute/docs/instance-groups/creating-groups-of-managed-instances) — Used to understand MIG configuration, autoscaling policies, and autohealing setup via ClickOps.
- [GCP Health Checks Docs](https://cloud.google.com/load-balancing/docs/health-checks) — Used to understand the distinction between application-level and load balancer health checks.
- [Terraform google_compute_instance resource reference](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) — Used to identify required arguments, optional arguments, outputs, and the `self_link` vs `id` distinction.
- [Terraform google provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs) — Used to pin provider version and configure the `terraform {}` block.
- [GCP image families reference](https://cloud.google.com/compute/docs/images/os-details) — Used to find the correct CentOS Stream 10 image family and project.
- [Terraform style guide](https://developer.hashicorp.com/terraform/language/style) — Used for naming conventions, formatting, and file organization.
- [GCP 3-tier architecture overview](https://cloud.google.com/architecture/three-tier-architecture-on-google-cloud) — Referenced for Q&A context.

---

## Q & A

### What is the difference between high availability and fault tolerance? Which is best to strive for?

**High availability (HA)** means a system is designed to minimize downtime — if something fails, the system recovers quickly, typically through redundancy and automatic failover. **Fault tolerance** is a stricter guarantee: the system continues operating *without any interruption* even when a component fails, because redundant components absorb the failure in real time with zero perceived impact. Fault tolerance is more expensive and complex to achieve (think redundant power supplies in hardware, or multi-region active-active deployments in cloud). For most applications, **high availability is the practical target** — it covers the vast majority of failure scenarios at a reasonable cost. True fault tolerance is reserved for systems where even seconds of downtime are unacceptable (financial clearing systems, aviation, etc.).

---

### Explain the difference between autoscaling and elasticity. What is vertical and horizontal autoscaling? Is one better? Are they feasible on prem?

**Elasticity** is the broader *property* of a system — its ability to scale resources up or down to match demand. **Autoscaling** is the *mechanism* that implements elasticity automatically, without manual intervention. Think of elasticity as the goal and autoscaling as the tooling.

**Horizontal autoscaling** (scaling *out/in*) adds or removes instances to a pool — e.g., going from 3 VMs to 10 VMs under load. **Vertical autoscaling** (scaling *up/down*) resizes a single instance — giving it more CPU or RAM. Horizontal is generally preferred in cloud because it's non-disruptive (you don't need to restart existing instances), distributes load better, and aligns with managed instance group mechanics. Vertical scaling typically requires a restart and has hard limits on how big a machine can get.

On-prem, **horizontal autoscaling is difficult** — you can't conjure physical servers on demand. **Vertical scaling on-prem** is possible but still requires physical intervention or at best a VM resize. This is one of the core value propositions of cloud: elasticity at scale without hardware procurement.

---

### Explain the difference between managed and unmanaged instance groups.

A **Managed Instance Group (MIG)** provisions and manages VMs from a single **instance template** — GCP controls the lifecycle, can autoscale, autoheals unhealthy instances, and distributes VMs across zones. All instances in a MIG are identical. An **Unmanaged Instance Group (UMIG)** is just a logical grouping of pre-existing VMs that you manage yourself — no instance template, no autoscaling, no autohealing. UMIGs are useful when you need to group heterogeneous VMs (different configs or sizes) for a load balancer backend, but you lose all the self-healing and scaling automation. In practice, use MIGs unless you have a specific reason not to.

---

### Explain the different use cases for health checks used by applications (in instance groups) and health checks used by load balancers. Can they be the same? Are they different API calls? Should they be the same?

**Autohealing health checks** (attached to the MIG) determine whether an instance itself is healthy enough to *keep running* — if an instance fails this check, GCP recreates it. **Load balancer health checks** determine whether an instance should *receive traffic* — if an instance fails this check, the LB stops sending requests to it but GCP does not necessarily recreate the VM.

They can reference the same `google_compute_health_check` resource, but they serve different purposes and should generally have **different thresholds**. The autohealing check should be more lenient (higher failure threshold, longer timeout) — you don't want VMs being recreated during a brief hiccup. The LB check can be more aggressive since it just routes traffic away rather than destroying an instance. They are configured via the same API (`compute.healthChecks`), but attached at different levels — one on the MIG, one on the backend service.

---

### Explain in a few sentences what the 3-tier architecture is and how it relates to what you are learning.

The **3-tier architecture** separates an application into three logical layers: the **presentation tier** (frontend, what users interact with), the **application/logic tier** (backend services processing business logic), and the **data tier** (databases or storage). Each tier can scale independently and communicate only with adjacent tiers. This maps directly to what we're learning: a load balancer sits in front of the presentation/app tier, managed instance groups run the app servers in the middle tier, and Cloud SQL or similar handles the data tier. MIGs and autoscaling make the app tier horizontally scalable, which is the key operational benefit of this pattern.

---

## Runbook

### Goal

Deploy a fully configured **regional Managed Instance Group (MIG)** in GCP via ClickOps (GCP Console). The MIG will use an instance template, span multiple zones, autoscale based on CPU, and autohealing via HTTP health check.

---

### Prerequisites

- GCP project with billing enabled
- `compute.admin` IAM role (or equivalent) on the project
- An existing **VPC network** and **subnet** to deploy into (default VPC is fine)
- A firewall rule allowing HTTP (TCP 80) ingress — the `default-allow-http` rule in the default VPC covers this if you tag instances with `http-server`
- An existing or ready-to-create **instance template** (covered below)
- Familiarity with GCP Console navigation

---

### Step 1 — Create an Instance Template

Navigate to **Compute Engine → Instance Templates → Create Instance Template**.

| Field | Value |
|---|---|
| Name | `hw8-template` (or your naming convention) |
| Machine type | e2-medium (or your choice) |
| Boot disk | CentOS Stream 10, 50GB (or as required) |
| Network tags | `http-server` |
| Startup script | Paste your RHEL startup script under **Management → Startup script** |
| Network | default VPC / appropriate subnet |

Click **Create**.

---

### Step 2 — Create the Managed Instance Group

Navigate to **Compute Engine → Instance Groups → Create Instance Group**.

Select **New managed instance group (stateless)**.

| Field | Value |
|---|---|
| Name | `hw8-mig` |
| Instance template | Select the template created in Step 1 |
| Location | **Multiple zones** → select your region (e.g., `us-central1`) |
| Zones | Leave as "Any" or select 2–3 specific zones |
| Min instances | 1 |
| Max instances | 3 (or per your requirement) |

---

### Step 3 — Enable Autoscaling

In the same creation form, scroll to **Autoscaling**:

- Set **Autoscaling mode** to `On: add and remove instances to the group`
- **Autoscaling metric**: CPU utilization
- **Target CPU utilization**: 60%
- **Minimum / Maximum instances**: set per your requirements
- **Cool-down period**: 60 seconds (default is fine)

---

### Step 4 — Enable Autohealing

Still in the creation form, scroll to **Autohealing**:

1. Click **Create a health check** (or select an existing one)
2. Configure the health check:

| Field | Value |
|---|---|
| Name | `hw8-autohealing-hc` |
| Protocol | HTTP |
| Port | 80 |
| Request path | `/` |
| Check interval | 10s |
| Timeout | 5s |
| Healthy threshold | 2 |
| Unhealthy threshold | 3 |

3. Set **Initial delay** to `300` seconds — this prevents autohealing from kicking in before the startup script finishes.

---

### Step 5 — Verify Multi-Zone Distribution

After the MIG is created and instances are running:

1. Navigate to the MIG detail page
2. Click the **Instances** tab
3. Verify that instances appear in **different zones** (e.g., `us-central1-a`, `us-central1-b`, `us-central1-c`)

Alternatively, run:
```bash
gcloud compute instance-groups managed list-instances hw8-mig --region=us-central1
```
Check the `ZONE` column — you should see multiple distinct zones.

---

### Step 6 — Verify Autoscaling

To force a scaling event and confirm autoscaling works, you can SSH into an instance and run a CPU stress test:
```bash
# Install stress (RHEL/CentOS)
sudo dnf install -y stress
stress --cpu 4 --timeout 120
```
Watch the MIG instances tab — after the cooldown period, you should see new instances provisioning.

---

### Critical Config Notes

- **Initial delay on autohealing** must be long enough for your startup script to complete. Too short = instances get killed before they're ready.
- **Regional MIGs** (multi-zone) are preferred over zonal MIGs for any production use — they survive a zone outage.
- The instance template is **immutable** — to change config, create a new template version and perform a rolling update on the MIG.
- Autoscaling **does not scale below min instances** — keep min ≥ 1 unless the MIG can be fully idle.

---

## Terraform

### Mandatory (Required) Arguments for a GCP VM (`google_compute_instance`)

The following arguments are **required** — Terraform will error without them:

| Argument | Purpose |
|---|---|
| `name` | The name of the VM instance — must be unique within the project/zone |
| `machine_type` | Defines the vCPU and memory allocation (e.g., `n2-standard-2`) |
| `zone` | The GCP zone to deploy the instance into |
| `boot_disk` | A block defining the root disk — requires a nested `initialize_params` block with at least an `image` |
| `network_interface` | Defines the VPC network attachment — requires at least `network` or `subnetwork` |

The `boot_disk.initialize_params.image` is technically inside `boot_disk` but is required in practice — without it Terraform doesn't know what OS to use.

---

### Outputting Internal and External IP Addresses

To output IPs, I referenced the [google_compute_instance resource docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) and looked at the **Attributes Reference** section (not the Arguments section — attributes are *computed* by GCP after provisioning).

The relevant computed attributes are:
- `network_interface[0].network_ip` — the internal/private IP
- `network_interface[0].access_config[0].nat_ip` — the external/public IP (only present if an `access_config {}` block exists in the network_interface)

```hcl
output "internal_ip" {
  value = google_compute_instance.vm.network_interface[0].network_ip
}

output "external_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}
```

---

### Two Non-Required Arguments (Explained)

**1. `metadata_startup_script`**

This argument lets you pass a shell script that runs automatically when the instance boots. GCP's guest agent picks it up from instance metadata and executes it as root. It's commonly used to install software, configure services, or prepare the instance at first boot — essentially the bootstrap step before your app is ready. This is the argument used instead of placing the script in `metadata = { startup-script = ... }`, which is the equivalent but less idiomatic for single-script use.

**2. `tags`**

Network tags are strings attached to a VM that GCP's firewall rules use for targeting. A firewall rule can say "apply to all instances with tag `http-server`" instead of targeting a specific IP. This means you don't hardcode IPs in firewall rules — you tag the instance and the rule finds it. In the default VPC, the pre-existing `default-allow-http` rule targets the `http-server` tag, so adding that tag to your instance is all you need to open port 80.

---

### Finding the CentOS Stream 10 Image

To find the correct image string, I used the GCP CLI to query available images:

```bash
gcloud compute images list --filter="family:centos-stream-10" --format="table(name,family,project)"
```

This returns output showing the image `family` and the `project` that owns it (for CentOS it's `centos-cloud`). In Terraform, you reference it as:

```hcl
initialize_params {
  image = "centos-cloud/centos-stream-10"
}
```

Using the **family** rather than a specific image name means Terraform always uses the latest published image in that family — you don't need to update your config every time Google publishes a new patch image. The format is `"<project>/<family-or-image-name>"`.

---

### `name` vs `id` vs `self_link`

| Attribute | What it is |
|---|---|
| `name` | A human-readable **argument you set** — e.g., `hw8-vm`. Unique within a zone but not globally. |
| `id` | A **computed attribute** GCP assigns after creation. For Compute instances it's typically the numeric instance ID or a composite string. Used for internal GCP tracking. |
| `self_link` | A **computed attribute** — the full REST API URL for the resource, e.g., `https://www.googleapis.com/compute/v1/projects/my-project/zones/us-central1-a/instances/hw8-vm`. Used when other resources need to reference this resource by its canonical API path (e.g., attaching an instance to a backend service). |

The key distinction: `name` is an *input you control*, while `id` and `self_link` are *outputs GCP generates* that you can reference in other resources or outputs after `apply`.

---
