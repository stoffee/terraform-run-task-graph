# Terraform Run Task Graph

This repository contains a custom run task for Terraform Cloud that generates a visual graph of your Terraform configuration and performs pattern-based checks on your Terraform code. It uses the `terraform graph` command to create a DOT file, which is then converted to a PNG image using Graphviz.

## Repository Structure

This repository contains two versions of the Terraform Run Task Graph:

1. **Main Version (Non-HMAC)**: The version in the `tf/app_server` directory does not use HMAC verification.
2. **Secure Version (HMAC-enabled)**: Located in the `tf/secure_app_server` folder, this version includes HMAC verification for enhanced security.

## Features

- Generates a visual representation of your Terraform configuration
- Runs as a post-plan task in Terraform Cloud
- Performs pattern-based checks on Terraform code
- Packaged as a Docker container for easy deployment
- Available in both non-HMAC and HMAC-secured versions

## Pattern Recognition

The run task includes a pattern recognition feature that scans your Terraform configuration files for specific patterns. These patterns are used to identify potential security risks or configurations that may require additional attention.

### Patterns Checked

The run task checks for the following patterns in your Terraform code:

1. Use of `remote-exec` provisioners
2. Use of `local-exec` provisioners
3. Use of `external` data sources
4. Use of `http` data sources

## Prerequisites

- A Terraform Cloud account
- AWS account (for deploying the run task server)
- Docker (for local testing and building the image)
- Doormat CLI (for AWS credentials management)

## Usage

### Non-Secure Version

1. Configure your tfc workspace to use the version control folder `tf/app_server`.
2. Add the following Terraform variables to your workspace:
   - `oauth_token_id` - TFC Github App OAuth Token ID
   - `tfe_organization` - Your Terraform Cloud organization name
3. Add an environment variable `TFE_TOKEN` with your Terraform Cloud API token.
4. Use Doormat to provide AWS credentials to your "app" workspace. For example:
   ```
   doormat login -f && doormat aws tf-push --organization $MY_TFC_ORG --workspace graph-terraform-run-task --role $(echo $(doormat aws list) | awk '{ print $3 }')
   ```
   Alternatively, if you have a project-level variable set:
   a. Create a project called "demo" with a variable set attached at the project level.
   b. Update your variable set with Doormat AWS credentials:
   ```
   doormat aws tf-push variable-set -a $AWS_SANDBOX_ACCOUNT_NAME --id your-varset-id
   ```
5. Run a plan and apply in your "app" workspace.
6. After the "app" workspace creates the new "demo-server-workspace", add this new workspace to your "demo" project to inherit the AWS credentials. Alternatively, use Doormat to provide AWS credentials directly to the new workspace:
   ```
   doormat aws tf-push -w demo-server-workspace
   ```
7. Start a plan in the "demo-server-workspace".
8. Go to the plan details page.
9. In the "Post-Plan" area, click "All" to see all run tasks.
10. In the row for your run task, click "View more details" to see the generated graph.

To test the pattern recognition:
- Update the Terraform code in `tf/demo_server` to include a `local-exec` provisioner or other checked patterns.
- This will cause the plan to fail or give a warning, depending on your enforcement level.

### Secure Version (HMAC-enabled)

1. Configure your workspace to use the version control folder `tf/secure_app_server`.
2. Add the following Terraform variables to your workspace:
   - `oauth_token_id` - TFC Github App OAuth Token ID
   - `tfe_organization` - Your Terraform Cloud organization name
   - `hmac_key` (populate with the output of `openssl rand -hex 32`)
3. Add an environment variable `TFE_TOKEN` with your Terraform Cloud API token.
4. Use Doormat to provide AWS credentials to your "app" workspace:
   ```
   doormat login -f && doormat aws tf-push --organization cdunlap --workspace graph-terraform-run-task --role $(echo $(doormat aws list) | awk '{ print $3 }')
   ```
   Alternatively, if you have a project-level variable set:
   a. Create a project called "demo" with a variable set attached at the project level.
   b. Update your variable set with Doormat AWS credentials:
   ```
   doormat aws tf-push variable-set -a $AWS_SANDBOX_ACCOUNT_NAME --id your-varset-id
   ```
5. Run a plan and apply in your "app" workspace.
6. After the "app" workspace creates the new "demo-server-workspace", add this new workspace to your "demo" project to inherit the AWS credentials. Alternatively, use Doormat to provide AWS credentials directly to the new workspace:
   ```
   doormat login -f && doormat aws tf-push --organization $MY_TFC_ORG --workspace graph-terraform-run-task --role $(echo $(doormat aws list) | awk '{ print $3 }')
   ```
7. Start a plan in the "demo-server-workspace".
8. Go to the plan details page.
9. In the "Post-Plan" area, click "All" to see all run tasks.
10. In the row for your run task, click "View more details" to see the generated graph.

To test the pattern recognition:
- Update the Terraform code in `tf/demo_server` to include a `local-exec` provisioner or other checked patterns.
- This will cause the plan to fail or give a warning, depending on your enforcement level.

## Viewing Results

After running a plan in your demo workspace:

1. Go to the plan details page.
2. In the "Post-Plan" section, click "All".
3. You should see a row for your run task, similar to this:

   | Run Task | Status | Details |
   |----------|--------|---------|
   | secure-graph-run-task | ✓ Passed | Configured patterns not found |

4. Click "View more details" to see the generated graph and any pattern matches.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.