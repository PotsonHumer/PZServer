## ADDED Requirements

### Requirement: Configurable Java maximum heap
The image SHALL accept an optional `PZ_JAVA_XMX` environment variable at container startup. The value SHALL be a positive whole decimal number followed by `m` or `g`, case-insensitively. Before Project Zomboid starts, the entrypoint SHALL apply a valid value as the launcher JVM's sole `-Xmx` argument.

#### Scenario: Valid heap override is applied
- **WHEN** an operator starts the container with `PZ_JAVA_XMX=2g`
- **THEN** the Project Zomboid launcher starts with `-Xmx2g`

#### Scenario: Default heap is retained when no override is configured
- **WHEN** an operator starts the container without `PZ_JAVA_XMX`
- **THEN** the launcher uses the image's supplied `-Xmx` value

#### Scenario: Invalid heap override prevents startup
- **WHEN** an operator starts the container with `PZ_JAVA_XMX` set to a value outside the accepted grammar
- **THEN** the entrypoint exits with a non-zero status before starting Project Zomboid and identifies `PZ_JAVA_XMX` as invalid

### Requirement: Transient launcher configuration
The entrypoint SHALL restore the image's supplied launcher configuration before applying any optional Java heap override on every container start. The selected heap value SHALL NOT be written to the persistent Project Zomboid data directory.

#### Scenario: Restart applies the current container setting
- **WHEN** a container starts after a previous start used a different valid `PZ_JAVA_XMX` value
- **THEN** the active launcher configuration contains only the value configured for the current start

#### Scenario: Persistent server data remains independent of heap selection
- **WHEN** an operator starts the container with a valid `PZ_JAVA_XMX` value
- **THEN** no Java heap setting is created or changed under the persistent Project Zomboid data directory

### Requirement: Documented heap-memory scope
The project documentation SHALL show how to set `PZ_JAVA_XMX` for local testing and SHALL state that it limits Java heap rather than Docker's total memory use.

#### Scenario: Operator consults local memory guidance
- **WHEN** an operator reads the documented local run instructions
- **THEN** they can find a `PZ_JAVA_XMX` example and its memory-scope limitation
