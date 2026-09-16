# frozen_string_literal: true

RSpec.describe SqsExtendedClient::ReceiptHandle do
  let(:pointer) { SqsExtendedClient::PayloadPointer.new("my-bucket", "prefix/my-key") }

  it "wraps the handle in the markers the Java client parses" do
    expect(described_class.embed("real-handle", pointer))
      .to eq("-..s3BucketName..-my-bucket-..s3BucketName..--..s3Key..-prefix/my-key-..s3Key..-real-handle")
  end

  it "round trips the original handle and the pointer" do
    embedded = described_class.embed("real-handle", pointer)

    expect(described_class).to be_embedded(embedded)
    expect(described_class.strip(embedded)).to eq("real-handle")
    expect(described_class.pointer(embedded)).to eq(pointer)
  end

  it "leaves a plain handle alone" do
    expect(described_class).not_to be_embedded("real-handle")
    expect(described_class.strip("real-handle")).to eq("real-handle")
  end
end
