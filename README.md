Test case for https://github.com/hashicorp/terraform/issues/32146
=================================================================

Issue:
------

Trying to import a value into the state, the following  error appears:
````
╷
│ Error: Invalid for_each argument
│ 
│   on managementhost/main.tf line 34, in data "aws_subnet" "private_subnets":
│   34:   for_each = var.private_subnets
│     ├────────────────
│     │ var.private_subnets is a map of dynamic, known only after apply
│ 
│ The "for_each" map includes keys derived from resource attributes that cannot be determined until apply, and so Terraform cannot determine the full set of keys that will identify the instances of this resource.
│ 
│ When working with unknown values in for_each, it's better to define the map keys statically in your configuration and place apply-time results only in the map values.
│ 
│ Alternatively, you could use the -target planning option to first apply only the resources that the for_each value depends on, and then apply a second time to fully converge.
╵
````

Test Environment
----------------

The stack intends to provide a bare-minimum boilerplate AWS environment with VPC, networking and a management host (jump host, bastion host) for tests, which can easily be deleted and created at will.
Alongside, an AWS-managed DNS zone ("Route 53 zone") is managed, with DNS entries e.g. for the management host. As this "zone" resource is very cheap to keep, but needs some effort to configure on the domain above, it is kept beyond the lifecycle of that terrafrom stack.

So before running `terraform apply`, the ID of that zone is imported into the state, and before `terraform destroy`, it is removed from the stack.

Environment
-----------
Required is access to an AWS account, configured on the local machine for AWS CLI. Also we need the AWS CLI, terraform (1.3.0+) and `jq`.

Terraform is wrapped in the wrapper script `./terraform`, which provides TF variables via environment variables.

Run `prepare.sh` first. It creates an AWS SSH keypair for the management host and stores it locally. It also creates the AWS S3 bucket for the terraform state. Finally, it creates said Route 53 zone outside of terraform, so it is already here for the import test.

Then, run `import-test.sh`, which tries to import the Route 53 zone ressource into the state, triggering the error message.

To clean up, run `cleanup.sh` to remove the keypair from AWS EC2, and local terraform state/provider files. The AWS Route53 zone must be removed manually.