# Terraform Graph Run Task

This project implements a custom run task for Terraform Cloud that generates a visual graph of your Terraform configuration and performs pattern-based checks on your Terraform code. It uses the `terraform graph` command to create a DOT file, which is then converted to a PNG image using Graphviz. Additionally, it scans your Terraform files for specific patterns that might indicate security risks or configurations requiring additional attention.

## Features

- Generates a visual representation of your Terraform configuration
- Runs as a post-plan task in Terraform Cloud
- Performs pattern-based checks on Terraform code
- Secure communication using HMAC key authentication
- Packaged as a Docker container for easy deployment

## Pattern Recognition

The run task includes a pattern recognition feature that scans your Terraform configuration files for specific patterns. These patterns are used to identify potential security risks or configurations that may require additional attention.

### Patterns Checked

The run task checks for the following patterns in your Terraform code:

1. Use of `remote-exec` provisioners
   - Pattern: `provisioner "remote-exec" { ... }`
   - Rationale: `remote-exec` provisioners can pose security risks if not properly secured, and may indicate configuration management that could be better handled by other tools.

2. Use of `local-exec` provisioners
   - Pattern: `provisioner "local-exec" { ... }`
   - Rationale: `local-exec` provisioners can make Terraform runs less portable and may indicate actions that could be better handled outside of Terraform or through other means.

3. Use of `external` data sources
   - Pattern: `data "external" { ... }`
   - Rationale: External data sources can introduce unpredictability and potential security risks if not carefully managed. They may also indicate a dependency on external scripts that could be better implemented within Terraform.

4. Use of `http` data sources
   - Pattern: `data "http" { ... }`
   - Rationale: HTTP data sources can introduce external dependencies and potential security risks, especially if not using HTTPS or if fetching data from untrusted sources.

When these patterns are detected, the run task will trigger either a mandatory fail or an advisory warning, depending on how you've configured the enforcement level in Terraform Cloud.

## Usage

When the run task executes, it will:

1. Generate the Terraform graph visualization
2. Scan your Terraform files for the patterns listed above
3. Report any matches found, along with the count of matches for each pattern

The run task will fail (if set to "mandatory" enforcement) or provide a warning (if set to "advisory" enforcement) if any patterns are matched. The output will include information about which patterns were matched and how many times.

To view the results:

1. Go to the "Runs" page in your Terraform Cloud workspace
2. Click on a specific run
3. Scroll down to the "Run Tasks" section
4. Click on the "View output" link for the Terraform Graph task

The output will include both the graph visualization and the results of the pattern recognition scan.

### Interpreting the Results

- If any of the patterns are matched, it doesn't necessarily mean there's a problem, but it does indicate configurations that may require additional review:
  - `remote-exec` and `local-exec` provisioners: Consider if these actions could be handled by configuration management tools or moved outside of Terraform.
  - `external` data sources: Review the external scripts being called and consider if they could be replaced with native Terraform resources or data sources.
  - `http` data sources: Ensure that these are fetching data over HTTPS from trusted sources, and consider if the data could be managed more securely within your Terraform configuration.

- Use the generated graph visualization in conjunction with the pattern matches to understand the context and potential impact of the flagged configurations.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.