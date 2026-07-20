## ADDED Requirements

### Requirement: Current-version UDP publishing guidance
The project documentation SHALL identify `16261/udp` and `16262/udp` as the current default Project Zomboid server port pair and provide a Docker run example that publishes both.

#### Scenario: Deploy a current-version server
- **WHEN** an operator follows the current-version run example
- **THEN** Docker publishes UDP ports `16261` and `16262` from the host to the container

### Requirement: Legacy UDP publishing guidance
The project documentation SHALL identify `16261/udp`, `8766/udp`, and `8767/udp` as the legacy pre-41.77 ports and provide a separate Docker run example that publishes them.

#### Scenario: Deploy a pre-41.77 server
- **WHEN** an operator follows the legacy-version run example
- **THEN** Docker publishes UDP ports `16261`, `8766`, and `8767` from the host to the container

### Requirement: Configuration-to-publication alignment
The project documentation SHALL state that the game-server port values in its server configuration MUST match the UDP ports published by Docker and opened through the host network path.

#### Scenario: Operator changes the game-server port
- **WHEN** an operator changes a UDP port in the Project Zomboid server configuration
- **THEN** the documentation directs the operator to change the corresponding Docker publication and host network rule
