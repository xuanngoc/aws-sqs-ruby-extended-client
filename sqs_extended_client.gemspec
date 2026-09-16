# frozen_string_literal: true

require_relative "lib/sqs_extended_client/version"

Gem::Specification.new do |spec|
  spec.name = "sqs_extended_client"
  spec.version = SqsExtendedClient::VERSION
  spec.authors = ["Ngoc Bui"]
  spec.email = ["ngocbui.se@gmail.com"]

  spec.summary = "Send and receive SQS messages larger than 256 KB by offloading the payload to S3."
  spec.description = "A wrapper around Aws::SQS::Client that stores large message bodies in S3 and " \
                     "sends a pointer through the queue instead, wire compatible with the AWS SQS " \
                     "extended client libraries for Java and Python."
  spec.homepage = "https://github.com/xuanngoc/aws-sqs-ruby-extended-client"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt", "NOTICE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-s3", "~> 1.0"
  spec.add_dependency "aws-sdk-sqs", "~> 1.0"
end
