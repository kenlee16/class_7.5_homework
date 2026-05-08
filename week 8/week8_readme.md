# Week 8 Notes
### Instance Groups, Autoscaling, and Terraform
*Google Cloud Platform — Cloud Infrastructure*

---

## Q & A

### High availability vs. fault tolerance — which should you strive for?

High availability means your system is designed to recover quickly when something breaks — there might be a brief hiccup, but it comes back fast. Fault tolerance means it never goes down at all, even during a failure, because there is so much redundancy built in that nothing is ever noticeable to the user.

Fault tolerance sounds better but it is extremely expensive and complex to build. For almost every real application, high availability is the right target. Fault tolerance is really only worth pursuing when even a single second of downtime causes serious harm, like medical systems or financial infrastructure.

---

### Autoscaling vs. elasticity — vertical vs. horizontal — is one better? Are they feasible on-premises?

Elasticity is the concept of your infrastructure growing and shrinking based on demand. Autoscaling is the feature that actually makes that happen automatically by watching your usage and adding or removing machines without anyone having to do anything.

Vertical scaling means making the machine you already have bigger — more memory, more processing power. Horizontal scaling means adding more machines and splitting the work between them. Horizontal is generally preferred in cloud environments because there is no ceiling and it is more resilient — losing one of ten machines hurts much less than losing the only one.

On-premises, neither approach works well as true autoscaling. You would need physical hardware already purchased and sitting ready, and spinning it up takes days not seconds. Automatic scaling is really a cloud-native concept.

---

### Managed vs. unmanaged instance groups

An unmanaged instance group is just a container you manually fill with machines you created yourself. Nothing is automatic — if a machine dies, you replace it yourself.

A managed instance group creates machines from a template automatically and watches over them constantly. If a machine becomes unhealthy it gets replaced without anyone touching it, and the group scales up or down based on traffic. For any production environment, managed is what you want.

---

### Health checks for applications vs. load balancers — can they be the same? Should they be?

The health check attached to the instance group is used for autohealing — it decides whether a machine is broken enough to destroy and replace. This one is patient and slow to react because replacing a machine is a big deal.

The load balancer health check decides whether to send user traffic to a machine right now. It reacts faster because you do not want users hitting a broken server even briefly. It does not destroy the machine, it just stops routing traffic to it.

They can both point at the same port and path on your app, but they are configured separately in Google Cloud and should have different timeout and failure threshold settings because they trigger very different actions.

---

### Three-tier architecture and how it connects to what we are learning

Three-tier architecture splits an app into three layers: the front end that users interact with, the application layer where the logic runs, and the data layer where things get stored. Each layer can be scaled and managed independently.

Managed instance groups live in the application layer. The load balancer sits in front of them as the entry point. Understanding this model helps you see where everything we are building this week fits into a real production system.

---

## Runbook — Setting Up a Managed Instance Group in the Cloud Console

The goal is to create a managed instance group using the Google Cloud browser console. The finished group will automatically scale machines based on load, replace unhealthy machines on its own, and distribute those machines across multiple zones for resilience.

### Prerequisites

- Google Cloud project with billing enabled and Compute Engine turned on
- Compute Admin role on the project
- A network and subnet already configured in the target region
- Firewall rule allowing traffic from Google health check ranges into your instances: `130.211.0.0/22` and `35.191.0.0/16` — without this, autohealing silently fails
- An instance template ready to go, or plan to create one in Step 1

### Step 1 — Create an Instance Template

Skip this if you already have one.

1. Go to Compute Engine → Instance Templates → Create Instance Template
2. Set machine type, boot disk image, and startup script
3. Under Networking, select the correct network and subnet
4. Click Create and confirm it appears in the list

### Step 2 — Create the Instance Group

1. Go to Compute Engine → Instance Groups → Create Instance Group
2. Choose Managed instance group (stateless)
3. Name the group and select your instance template
4. Under Location, choose Multiple zones, select your region, and confirm multiple zones are checked
5. Set initial instance count — 2 is a reasonable minimum for anything that needs to stay up

### Step 3 — Configure Autoscaling

1. Set mode to On (add and remove instances)
2. Set signal to CPU utilization, target around 60% — leaves headroom before things degrade
3. Set a minimum and maximum instance count — do not leave the max uncapped
4. Leave cool-down at the default 60 seconds unless you have a specific reason to change it

### Step 4 — Configure Autohealing

1. In the Autohealing section, click Add health check and create or select one
2. Set protocol to HTTP, port to whatever your app listens on, and path to your health endpoint (e.g. `/healthz`)
3. Set initial delay longer than your app's boot time — 120 to 300 seconds is common. Undersetting this causes machines to get destroyed during startup.
4. Healthy threshold: 2 successes. Unhealthy threshold: 3 failures.
5. Confirm the health check appears in the Autohealing section

### Step 5 — Verify Multi-Zone Distribution

1. Once machines are running, open the instance group detail page
2. Click the Instances tab and check the Zone column — machines should be spread across at least two zones
3. If everything is in one zone, confirm Multiple zones was selected and that the region actually has multiple zones

### Critical Notes

- Instance templates are immutable. Changes require a new template version and a rolling update.
- Missing the health check firewall rule is the most common reason autohealing silently fails. Check this first if health checks always show unhealthy.
- Set initial delay conservatively on first deploy — you can tighten it after measuring actual boot time.
- Use Update VMs → Automatic rolling update to push new configurations without downtime.

---

## Terraform — Creating a Virtual Machine

### Required arguments

There are five things you must always include when defining a virtual machine in Terraform or it will refuse to run.

- **name** — what you want to call the machine, must be unique within the project and zone
- **machine_type** — the size of machine to create, which determines processing power and memory (e.g. `e2-medium`)
- **zone** — the specific zone where the machine will live, not just the region (e.g. `us-central1-a`)
- **boot_disk** — defines the hard drive and operating system, requires an `initialize_params` block with an `image` field
- **network_interface** — which network to connect to. Adding an empty `access_config {}` block inside gives the machine a public IP address

```hcl
resource "google_compute_instance" "my_vm" {
  name         = "my-vm"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }
}
```

### Outputting internal and external IP addresses

After Terraform creates the machine, you can read the IP addresses back out using output blocks. To find the correct attribute names, go to `registry.terraform.io`, search `google_compute_instance`, and scroll to the Attributes Reference section. The IPs live inside `network_interface`, which is stored as a list, so `[0]` just means the first network card.

```hcl
output "internal_ip" {
  value = google_compute_instance.my_vm.network_interface[0].network_ip
}

output "external_ip" {
  value = google_compute_instance.my_vm.network_interface[0].access_config[0].nat_ip
}
```

Run `terraform apply`, then `terraform output` to see the values printed.

### Two optional arguments worth knowing

#### metadata_startup_script

A shell script that runs automatically the first time the machine boots. Useful for installing software or starting services without having to SSH in manually after creation. Output is logged to the serial console in the Google Cloud console.

```hcl
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl start nginx
  EOF
```

#### tags

Plain text labels you attach to a machine that firewall rules can use to target it specifically. They are different from resource labels — their only job is to connect machines to firewall rules. If a machine is tagged `web-server`, any firewall rule targeting that tag applies to it.

```hcl
  tags = ["web-server", "allow-health-check"]
```

### How to find the correct CentOS Stream 10 image name

Image names change with every release so hardcoding one you found in old documentation is risky. The better approach is to query Google directly for what is currently available.

```bash
gcloud compute images list \
  --project centos-cloud \
  --filter="name~'centos-stream-10'" \
  --no-standard-images
```

Even better is using the image family instead of a specific name. The family always resolves to the latest release automatically, so you do not have to update your code every time a new version comes out.

```hcl
  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-stream-10"
    }
  }
```

### name vs. id vs. self_link

**name** is what you typed in your Terraform file — a readable label like `my-vm` that shows up in the console and in command line tools. You set this yourself.

**id** is a number Google assigns internally after the machine is created. You cannot predict or set it. It uniquely identifies the machine inside Google's systems but you rarely use it directly in Terraform.

**self_link** is the machine's full address in Google's system — a long URL containing the project, zone, and name. When other Terraform resources need to reference this machine, like a load balancer or instance group, they use `self_link` because it gives Google everything it needs to find the exact resource.

> **Quick summary:** `name` is for humans to read. `self_link` is for other resources to reference this one. `id` is internal and rarely needed in your configs.

---

## Documentation and Resources

### Google Cloud Documentation

**Instance groups overview**
`cloud.google.com/compute/docs/instance-groups`
Used to understand the difference between managed and unmanaged instance groups — specifically the section on how managed groups use instance templates and what the group controller does when a machine fails.

**Creating managed instance groups**
`cloud.google.com/compute/docs/instance-groups/creating-groups-of-managed-instances`
The primary reference for the runbook. Used to confirm the exact steps in the console for setting location to multiple zones, and for the specific fields under autoscaling and autohealing. The initial delay explanation came from this page.

**Autoscaling groups of instances**
`cloud.google.com/compute/docs/autoscaler`
Used for the autoscaling section of the runbook and the Q&A answer on elasticity vs autoscaling. This page explains the cool-down period, CPU utilization as a signal, and why you should set a maximum.

**Setting up health checks**
`cloud.google.com/compute/docs/health-checks`
Used to answer the Q&A question about the difference between application health checks and load balancer health checks. This page explicitly distinguishes between health checks used for autohealing vs those used by backend services. The threshold values in the runbook come from the recommended defaults on this page.

**Health check firewall rules**
`cloud.google.com/load-balancing/docs/health-checks#fw-rule`
Used to get the exact IP ranges that Google uses to probe health checks: `130.211.0.0/22` and `35.191.0.0/16`. These are in the runbook prerequisites because missing this firewall rule is the most common reason autohealing breaks silently.

**Compute Engine images**
`cloud.google.com/compute/docs/images`
Used for the Terraform section on finding the correct CentOS Stream 10 image. This page explains image families and why using a family name is safer than pinning to a specific image.

### Terraform Registry

**google_compute_instance resource reference**
`registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance`
The main reference for the entire Terraform section. Used to identify the five required arguments by looking at which fields are marked required vs optional. The Attributes Reference section at the bottom is where the `network_interface[0].network_ip` and `network_interface[0].access_config[0].nat_ip` attribute paths come from. Also used to understand the difference between `name`, `id`, and `self_link`.

**google_compute_health_check resource reference**
`registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check`
Referenced when writing the autohealing section of the runbook to confirm which fields are required when configuring a health check resource.

### Google Cloud Command Line Tool (gcloud)

**gcloud compute images list**
`cloud.google.com/sdk/gcloud/reference/compute/images/list`
Used to write the command for finding available CentOS Stream 10 images. Specifically used the `--project`, `--filter`, and `--no-standard-images` flags. The filter syntax comes from the gcloud filter expression reference linked from this page.

### Conceptual References

**Google Cloud — Application availability guide**
`cloud.google.com/architecture/framework/reliability/design-for-high-availability`
Used for the Q&A question on high availability vs fault tolerance. This page defines both terms and explains that most workloads target high availability rather than full fault tolerance.

**Google Cloud — Patterns for scalable and resilient apps**
`cloud.google.com/solutions/scalable-and-resilient-apps`
Used for the autoscaling and three-tier architecture questions. This page explains horizontal vs vertical scaling in the context of Google Cloud and describes the three-tier model in terms of how Compute Engine, load balancers, and databases map to each layer.
