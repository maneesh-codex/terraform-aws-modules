# Contributing

Thanks for taking the time to contribute.

## Getting set up

You will need:

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [pre-commit](https://pre-commit.com/)
- [tflint](https://github.com/terraform-linters/tflint)
- [terraform-docs](https://terraform-docs.io/)

```bash
brew install terraform pre-commit tflint terraform-docs
git clone https://github.com/maneesh-m/terraform-aws-modules.git
cd terraform-aws-modules
pre-commit install
tflint --init
```

## Before you open a pull request

Run the same checks CI runs:

```bash
# Formatting
terraform fmt -check -recursive -diff

# Validation across every module and example
for dir in modules/*/ examples/*/; do
  terraform -chdir="$dir" init -backend=false -input=false
  terraform -chdir="$dir" validate
done

# Lint
tflint --recursive

# Regenerate the docs blocks in module READMEs
terraform-docs markdown table --output-file README.md --output-mode inject modules/vpc
```

Or just let pre-commit do it:

```bash
pre-commit run --all-files
```

## Conventions

These follow the [terraform-aws-modules](https://github.com/terraform-aws-modules)
community layout. Please stick to them.

### File layout

Every module has exactly these files:

```
modules/<name>/
├── main.tf       # resources
├── variables.tf  # inputs
├── outputs.tf    # outputs
├── versions.tf   # terraform + provider constraints
└── README.md     # docs, with a terraform-docs block
```

### Variables

- Every variable has a `description` and an explicit `type`.
- Defaults should be safe and production-shaped. When in doubt, default to the
  secure option and make the insecure one opt-in.
- Add a `validation` block wherever a bad value would otherwise fail at apply
  time. Failing at plan time is much cheaper for the user.
- Complex inputs use `object({...})` with `optional(...)` defaults rather than
  `any`, so users get type checking and editor completion.

### Outputs

- Every output has a `description`.
- Mark credentials and anything derived from them `sensitive = true`.
- Export what a caller needs to wire this module to another one — IDs, ARNs,
  endpoints, security group IDs.

### Tagging

Every module takes a `tags` variable and merges it into every taggable resource:

```hcl
locals {
  tags = merge(var.tags, { "terraform-module" = "<name>" })
}

resource "aws_something" "this" {
  tags = merge(local.tags, { Name = var.name })
}
```

Never assign `var.tags` directly to a resource — always merge, so per-resource
`Name` tags survive.

### Naming

- Resources use `this` when a module creates exactly one of a kind.
- Use `name_prefix` over `name` where AWS supports it, so replacements do not
  collide with the resource being destroyed.
- Locals, variables and outputs are `snake_case`.

### Comments

Comment the non-obvious. A comment explaining *why* a `lifecycle` block or an
explicit `depends_on` is needed is valuable; a comment restating what
`resource "aws_s3_bucket"` does is noise.

## Adding a module

1. Create `modules/<name>/` with all five files.
2. Wire it into at least one example under `examples/`.
3. Add it to the module table in the root `README.md`.
4. Add its directory to the `validate` matrix in `.github/workflows/ci.yml` and
   to the `working-dir` list in the `docs` job.

## Testing

CI runs `fmt`, `validate` and `tflint`. It does **not** run `plan` or `apply`,
since that needs credentials — so please apply your changes against a real
account before submitting anything non-trivial, and say so in the PR
description.

If you add a module that creates something expensive (NAT gateways, RDS
instances, EKS clusters), note the approximate running cost in its README.

## Commit messages

Conventional commits, with the module as the scope:

```
feat(rds-postgres): support IAM database authentication
fix(vpc): correct route table association for single NAT gateway
docs(eks): clarify private endpoint access
```

## Releases

Tagged `vMAJOR.MINOR.PATCH`. Breaking changes to a module's input or output
surface require a major version bump — consumers pin with `?ref=v1.0.0`, so a
silent break is a real outage for them.
