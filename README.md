# Terraform Run Task Graph

This repository contains a custom run task for Terraform Cloud that generates a visual graph of your Terraform configuration and performs pattern-based checks on your Terraform code. It uses the `terraform graph` command to create a DOT file, which is then converted to a PNG image using Graphviz.

## Repository Structure

This repository contains two versions of the Terraform Run Task Graph:

1. **Main Version (Non-HMAC)**: The version in the root directory does not use HMAC verification.
2. **Secure Version (HMAC-enabled)**: Located in the `/secure` folder, this version includes HMAC verification for enhanced security.

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

## Usage

When the run task executes, it will:

1. Generate the Terraform graph visualization
2. Scan your Terraform files for the patterns listed above
3. Report any matches found, along with the count of matches for each pattern

The run task will fail (if set to "mandatory" enforcement) or provide a warning (if set to "advisory" enforcement) if any patterns are matched.

## Secure Version

For enhanced security, we recommend using the HMAC-enabled version located in the `/secure` folder. This version includes HMAC verification to ensure the integrity and authenticity of incoming requests.

[View the Secure Version README](./secure/)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.