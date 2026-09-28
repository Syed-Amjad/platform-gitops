# terraform — the box this platform runs on

One EC2 instance, one security group, one key pair. That is the whole stack, and
the restraint is deliberate.

Everything above this layer is declared in Kubernetes manifests and reconciled by
ArgoCD. This directory exists only to produce a machine for those manifests to
land on, and it stops there.

---

## Why this is here at all

The rest of the project is a GitOps argument: the cluster's state is in git, and
drift is corrected automatically. Provisioning the node by clicking through the
EC2 console would leave the one component nobody could reproduce sitting
underneath a platform whose entire premise is reproducibility.

There is also a blunter reason. A `t3.xlarge` bills at roughly **$0.166/hour**.
Left running across a month that is about **$120**. `terraform destroy` at the
end of a session is the control that stops a portfolio project becoming a
recurring charge, and it only exists if the box was created this way.

---

## Use

```bash
cd terraform
terraform init
terraform plan          # confirm allowed_ssh_cidr is YOUR address
terraform apply
```

Then read the outputs:

```bash
terraform output tunnel_command    # SSH with every UI forwarded
terraform output public_ip
```

Teardown, and the verification that it worked:

```bash
terraform destroy
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=gitops-observability-platform" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text
```

An empty result is the proof. `terraform destroy` reporting success and the
account actually being empty are two different claims, and only the second one
is the one that matters when the bill arrives.

---

## Decisions worth defending

| Decision | Reason |
|---|---|
| **Default VPC, but a declared subnet** | This needs one box, so no bespoke multi-AZ VPC. But the default VPC is reused, not trusted — see the defect below. |
| **Port 22 only, from a `/32`** | Every UI is tunnelled over SSH. ArgoCD with a bootstrap password and a dev-mode Vault holding a root token do not belong on a public port. |
| **Existing SSH key, not `tls_private_key`** | That resource writes the private key into `terraform.tfstate` in plaintext. State is the one file in an IaC repo you cannot afford to leak. |
| **IMDSv2 required** | The v1 endpoint is reachable from inside any pod, which turns an SSRF into a credential read. Costs nothing to enforce. |
| **No Elastic IP** | An EIP bills while *unattached* — precisely when you have forgotten it exists. The IP changing on stop/start is the smaller problem. |
| **`ignore_changes = [ami]`** | The AMI resolves to "most recent", so Ubuntu republishing would otherwise render as a plan that destroys a cluster you spent a day building. |
| **`encrypted = true`, `delete_on_termination = true`** | Free, and an orphaned 40 GB volume bills ~$3.20/month for nothing. |

---

## A defect found by running this, not by reading it

The first version of this stack looked up the default VPC's subnets with a data
source and placed the instance in the first one. That is the normal pattern and
it failed immediately:

```
Error: Invalid index
  on compute.tf line 13, in resource "aws_instance" "node":
  13:   subnet_id = data.aws_subnets.default.ids[0]
    │ data.aws_subnets.default.ids is empty list of string
```

The account's default VPC had been stripped at some point in the past:

| Component | State found |
|---|---|
| Default subnets (all six AZs) | deleted |
| Internet gateway | deleted |
| Main route table `0.0.0.0/0` | still present, pointing at the dead IGW, state **`blackhole`** |

**The blackhole route is the part worth dwelling on.** It is not an error
condition — AWS reports the route table as healthy and the route simply
discards traffic. Had this stack created a subnet and let it inherit the main
route table, `terraform apply` would have succeeded, the instance would have
booted, the SSH tunnel would have worked, and then `bootstrap-cluster.sh` would
have hung on `apt-get update` with no explanation. That failure presents as a
broken k3s install, and the gateway is the last place anyone looks.

The fix is `network.tf`: this stack now declares its own internet gateway,
subnet, route table and association. It costs four resources and buys two
things — no dependency on account state nobody is maintaining, and a
`terraform destroy` that removes every part of what was built.

The general lesson is the one this whole project is about: **"it applied
successfully" and "it works" are different claims.** A data source that returns
an empty list is a loud failure and was cheap. A route that silently discards
packets is a quiet one, and quiet failures are what cost evenings.

---

## Honest limitation

**State is local.** `terraform.tfstate` lives on the machine that ran `apply` and
is gitignored. For one operator and one rebuildable box that is genuinely
adequate, and an S3 backend with DynamoDB locking would be a paragraph of setup
protecting against a concurrency problem that cannot occur here.

It would *not* be adequate the moment a second person could run `apply`. That is
the condition to watch for, and it is worth stating plainly rather than
implying this is how a team would run it.
