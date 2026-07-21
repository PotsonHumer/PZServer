## Purpose

Define non-interactive, secret-safe Project Zomboid administrator initialization for managed platforms.

## Requirements

### Requirement: Environment-based non-interactive administrator initialization
The image SHALL accept an optional `PZ_ADMIN_PASSWORD` runtime environment variable and, when it is non-empty, provide that value through an ephemeral private standard-input channel only after detecting each Project Zomboid first-run administrator-password prompt. The image SHALL not print the password, place it in command-line arguments, or provide it as a server console command after initialization. The image SHALL not embed an administrator password in the Dockerfile or image filesystem.

#### Scenario: Managed first start with an administrator password
- **WHEN** a managed platform starts the image with a non-empty `PZ_ADMIN_PASSWORD`
- **THEN** the server receives the configured password for both initial prompts, starts without operator interaction, and creates the administrator password without logging it

#### Scenario: Start without managed administrator configuration
- **WHEN** a platform starts the image without `PZ_ADMIN_PASSWORD`
- **THEN** the server uses its normal startup path without an injected administrator-password option
