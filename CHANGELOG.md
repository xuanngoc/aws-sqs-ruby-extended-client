# Changelog

## [0.2.0] - 2026-09-18

### Changed

- `payload_size_threshold` now defaults to `1_048_576` rather than `262_144`. AWS raised the
  maximum SQS message size from 256 KiB to 1 MiB in August 2025, so the old default sent
  payloads to S3 that the queue accepts directly. Bodies between 256 KiB and 1 MiB now go
  inline. Pass `payload_size_threshold: 262_144` to keep the previous behaviour, which is
  also what the AWS Java and Python clients still default to.

### Fixed

- Corrected the 256 KB message size limit quoted throughout the README and the gem summary.
- Documented that `SendMessageBatch` is capped at 1 MiB in total rather than per entry, so a
  batch of bodies that are each under the threshold can still be rejected.

## [0.1.0] - 2026-09-18

### Added

- Initial release: `SqsExtendedClient::Client`, an `Aws::SQS::Client` wrapper that offloads
  large message bodies to S3 and restores them on receive, wire compatible with the AWS SQS
  extended client libraries for Java and Python.
