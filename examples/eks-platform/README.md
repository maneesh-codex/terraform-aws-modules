# Example: EKS platform

A complete container platform built from the `vpc`, `eks`, `iam-irsa-role` and
`s3-bucket` modules.

## What it builds

- A three-AZ VPC with public, private and intra subnet tiers, flow logs, and
  the subnet tags the AWS Load Balancer Controller needs for auto-discovery.
- An EKS cluster with a **private-only** API endpoint, secret envelope
  encryption, and two managed node groups:
  - `general` — on-demand `m6i.large`, 3–6 nodes
  - `spot` — mixed spot instance types, 0–10 nodes, tainted `workload=batch`
- Managed addons: CoreDNS, kube-proxy, VPC CNI, and the EBS CSI driver wired to
  its own IRSA role.
- IRSA roles for the EBS CSI driver, AWS Load Balancer Controller, cluster
  autoscaler, and an application workload — each with a least-privilege policy.
- A KMS-encrypted artifacts bucket with tiered lifecycle rules, writable only by
  the application's IRSA role.

## Usage

```bash
terraform init
terraform plan -var 'environment=dev' -var 'project=platform'
terraform apply
```

Then configure kubectl (from inside the VPC — the endpoint is private):

```bash
$(terraform output -raw kubeconfig_command)
```

## Environment-driven defaults

`environment` is more than a tag here. Anything other than `prod` gets
cost-saving and convenience defaults:

| Setting | `prod` | everything else |
| --- | --- | --- |
| NAT gateways | One per AZ | Single shared gateway |
| Artifacts bucket `force_destroy` | `false` | `true` |

This keeps dev environments cheap and destroyable while production stays
properly redundant.

## Inputs worth setting

| Name | Description | Default |
| --- | --- | --- |
| `region` | AWS region | `eu-west-1` |
| `project` | Name prefix for all resources | `platform` |
| `environment` | Drives the defaults above | `dev` |
| `vpc_cidr` | VPC CIDR; must be a `/16` for the subnet math | `10.20.0.0/16` |
| `cluster_version` | Kubernetes version | `1.31` |
| `app_namespace` | Namespace for the app service account | `applications` |
| `app_service_account` | Name of the app service account | `app` |

## After apply

The IRSA roles exist but the controllers do not — this example provisions AWS
infrastructure, not Kubernetes workloads. Install the controllers with Helm and
point their service accounts at the role ARNs from the `irsa_role_arns` output:

```bash
terraform output -json irsa_role_arns
```

## Cost

Roughly $250–400/month in `prod` shape (3 NAT gateways, 3 on-demand `m6i.large`,
EKS control plane at $73/month), and well under half that in `dev` shape.
Destroy it when you are done experimenting.

## Cleanup

```bash
terraform destroy
```

In `prod` shape the artifacts bucket has `force_destroy = false`, so empty it
first or the destroy will fail — which is the intended behaviour.
