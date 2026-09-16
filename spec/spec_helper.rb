# frozen_string_literal: true

require "sqs_extended_client"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end

module StubClients
  QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue"
  BUCKET = "test-bucket"

  def stub_sqs
    Aws::SQS::Client.new(stub_responses: true, region: "us-east-1")
  end

  def stub_s3
    Aws::S3::Client.new(stub_responses: true, region: "us-east-1")
  end

  def extended_client(sqs: stub_sqs, s3: stub_s3, **options)
    SqsExtendedClient::Client.new(bucket_name: BUCKET, sqs_client: sqs, s3_client: s3, **options)
  end
end

RSpec.configure { |config| config.include StubClients }
