# frozen_string_literal: true

RSpec.describe SqsExtendedClient::Configuration do
  it "defaults the threshold to the SQS message size limit of 1 MiB" do
    expect(described_class::DEFAULT_PAYLOAD_SIZE_THRESHOLD).to eq(1_048_576)
    expect(described_class.new(bucket_name: "b").payload_size_threshold).to eq(1_048_576)
  end

  it "sends a body at exactly the limit inline and one byte over through S3" do
    [[1_048_576, 0], [1_048_577, 1]].each do |size, expected_puts|
      sqs = stub_sqs
      s3 = stub_s3
      extended_client(sqs: sqs, s3: s3).send_message(queue_url: StubClients::QUEUE_URL, message_body: "a" * size)

      expect(s3.api_requests.count { |r| r[:operation_name] == :put_object }).to eq(expected_puts)
    end
  end
end
