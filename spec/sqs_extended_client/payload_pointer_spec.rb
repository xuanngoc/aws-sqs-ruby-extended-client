# frozen_string_literal: true

RSpec.describe SqsExtendedClient::PayloadPointer do
  it "serializes as the two element array the Java client expects" do
    json = described_class.new("my-bucket", "my-key").to_json

    expect(JSON.parse(json)).to eq(
      ["software.amazon.payloadoffloading.PayloadS3Pointer", { "s3BucketName" => "my-bucket", "s3Key" => "my-key" }]
    )
  end

  it "reads pointers written by the current client" do
    json = '["software.amazon.payloadoffloading.PayloadS3Pointer",{"s3BucketName":"b","s3Key":"k"}]'

    expect(described_class.from_json(json)).to eq(described_class.new("b", "k"))
  end

  it "reads pointers written by the legacy v1 Java client" do
    json = '["com.amazon.sqs.javamessaging.MessageS3Pointer",{"s3BucketName":"b","s3Key":"k"}]'

    expect(described_class.from_json(json)).to eq(described_class.new("b", "k"))
  end

  it "rejects a body that is not a pointer" do
    expect { described_class.from_json('{"hello":"world"}') }
      .to raise_error(SqsExtendedClient::InvalidPointerError)
  end

  it "rejects a body that is not JSON at all" do
    expect { described_class.from_json("plain text") }
      .to raise_error(SqsExtendedClient::InvalidPointerError)
  end
end
