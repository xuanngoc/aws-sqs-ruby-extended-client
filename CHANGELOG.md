# Changelog

## [Unreleased]

### Added

- Initial release: `SqsExtendedClient::Client`, an `Aws::SQS::Client` wrapper that offloads
  message bodies larger than 256 KB to S3 and restores them on receive.
