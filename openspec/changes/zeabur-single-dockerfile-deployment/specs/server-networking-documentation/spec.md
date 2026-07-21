## MODIFIED Requirements

### Requirement: Current-version UDP publishing guidance
The project documentation SHALL identify `16261/udp` and `16262/udp` as the current default Project Zomboid server port pair, provide a Docker run example that publishes both, and provide Zeabur instructions that configure UDP forwarding to both container ports.

#### Scenario: Deploy a current-version server
- **WHEN** an operator follows the current-version Docker or Zeabur deployment instructions
- **THEN** UDP traffic to container ports `16261` and `16262` is made available through the selected deployment environment
