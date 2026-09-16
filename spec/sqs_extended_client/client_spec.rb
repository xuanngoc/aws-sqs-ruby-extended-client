# frozen_string_literal: true

RSpec.describe SqsExtendedClient::Client do
  let(:sqs) { stub_sqs }
  let(:s3) { stub_s3 }

  def requests(client, operation)
    client.api_requests.select { |request| request[:operation_name] == operation }
  end

  describe "#send_message" do
    it "leaves a small message alone" do
      extended_client(sqs: sqs, s3: s3).send_message(queue_url: StubClients::QUEUE_URL, message_body: "small")

      expect(requests(s3, :put_object)).to be_empty
      expect(requests(sqs, :send_message).first[:params][:message_body]).to eq("small")
    end

    it "offloads a body over the threshold and sends a pointer" do
      extended_client(sqs: sqs, s3: s3, payload_size_threshold: 10)
        .send_message(queue_url: StubClients::QUEUE_URL, message_body: "a" * 20)

      put = requests(s3, :put_object).first[:params]
      expect(put[:bucket]).to eq(StubClients::BUCKET)
      expect(put[:body]).to eq("a" * 20)

      sent = requests(sqs, :send_message).first[:params]
      pointer = SqsExtendedClient::PayloadPointer.from_json(sent[:message_body])
      expect(pointer.key).to eq(put[:key])
      expect(sent[:message_attributes]["ExtendedPayloadSize"])
        .to eq(data_type: "Number", string_value: "20")
    end

    it "counts message attributes towards the threshold" do
      # body 20 + name 5 + data_type 6 + value 10 = 41, one byte over the threshold
      extended_client(sqs: sqs, s3: s3, payload_size_threshold: 40).send_message(
        queue_url: StubClients::QUEUE_URL,
        message_body: "a" * 20,
        message_attributes: { "trace" => { data_type: "String", string_value: "b" * 10 } }
      )

      expect(requests(s3, :put_object).size).to eq(1)
    end

    it "offloads everything when always_through_s3 is set" do
      extended_client(sqs: sqs, s3: s3, always_through_s3: true)
        .send_message(queue_url: StubClients::QUEUE_URL, message_body: "small")

      expect(requests(s3, :put_object).size).to eq(1)
    end

    it "writes the legacy attribute name when asked" do
      extended_client(sqs: sqs, s3: s3, always_through_s3: true, use_legacy_reserved_attribute_name: true)
        .send_message(queue_url: StubClients::QUEUE_URL, message_body: "small")

      expect(requests(sqs, :send_message).first[:params][:message_attributes]).to have_key("SQSLargePayloadSize")
    end

    it "prefixes the S3 key" do
      extended_client(sqs: sqs, s3: s3, always_through_s3: true, s3_key_prefix: "payloads/")
        .send_message(queue_url: StubClients::QUEUE_URL, message_body: "small")

      expect(requests(s3, :put_object).first[:params][:key]).to start_with("payloads/")
    end

    it "refuses a message that uses the reserved attribute name" do
      expect do
        extended_client(sqs: sqs, s3: s3).send_message(
          queue_url: StubClients::QUEUE_URL,
          message_body: "small",
          message_attributes: { "ExtendedPayloadSize" => { data_type: "Number", string_value: "5" } }
        )
      end.to raise_error(SqsExtendedClient::MessageAttributeError, /reserved/)
    end

    it "refuses more than nine message attributes" do
      attributes = (1..10).to_h { |i| ["attr#{i}", { data_type: "String", string_value: "v" }] }

      expect do
        extended_client(sqs: sqs, s3: s3)
          .send_message(queue_url: StubClients::QUEUE_URL, message_body: "small", message_attributes: attributes)
      end.to raise_error(SqsExtendedClient::MessageAttributeError, /maximum/)
    end
  end

  describe "#receive_message" do
    def stub_pointer_message(attribute_name: "ExtendedPayloadSize", body: nil)
      pointer = SqsExtendedClient::PayloadPointer.new(StubClients::BUCKET, "the-key")
      sqs.stub_responses(:receive_message, messages: [{
                           body: body || pointer.to_json,
                           receipt_handle: "real-handle",
                           message_attributes: {
                             attribute_name => { data_type: "Number", string_value: "20" },
                             "trace" => { data_type: "String", string_value: "abc" }
                           }
                         }])
      pointer
    end

    it "passes a plain message through" do
      sqs.stub_responses(:receive_message, messages: [{ body: "small", receipt_handle: "real-handle" }])

      message = extended_client(sqs: sqs, s3: s3).receive_message(queue_url: StubClients::QUEUE_URL).messages.first

      expect(message.body).to eq("small")
      expect(message.receipt_handle).to eq("real-handle")
    end

    it "asks for the reserved attributes alongside the caller's" do
      client = extended_client(sqs: sqs, s3: s3)
      client.receive_message(queue_url: StubClients::QUEUE_URL, message_attribute_names: %w[trace])

      expect(requests(sqs, :receive_message).first[:params][:message_attribute_names])
        .to eq(%w[trace ExtendedPayloadSize SQSLargePayloadSize])
    end

    it "restores the body, hides the reserved attribute and embeds the pointer" do
      stub_pointer_message
      s3.stub_responses(:get_object, body: "the original payload")

      message = extended_client(sqs: sqs, s3: s3).receive_message(queue_url: StubClients::QUEUE_URL).messages.first

      expect(message.body).to eq("the original payload")
      expect(message.message_attributes.keys).to eq(%w[trace])
      expect(SqsExtendedClient::ReceiptHandle.strip(message.receipt_handle)).to eq("real-handle")
      expect(SqsExtendedClient::ReceiptHandle.pointer(message.receipt_handle).key).to eq("the-key")
    end

    it "recognizes the legacy attribute name" do
      stub_pointer_message(attribute_name: "SQSLargePayloadSize")
      s3.stub_responses(:get_object, body: "the original payload")

      message = extended_client(sqs: sqs, s3: s3).receive_message(queue_url: StubClients::QUEUE_URL).messages.first

      expect(message.body).to eq("the original payload")
    end

    it "reads a pointer written by the legacy Java client" do
      stub_pointer_message(
        body: '["com.amazon.sqs.javamessaging.MessageS3Pointer",{"s3BucketName":"test-bucket","s3Key":"the-key"}]'
      )
      s3.stub_responses(:get_object, body: "the original payload")

      message = extended_client(sqs: sqs, s3: s3).receive_message(queue_url: StubClients::QUEUE_URL).messages.first

      expect(message.body).to eq("the original payload")
    end

    it "raises when the payload is gone" do
      stub_pointer_message
      s3.stub_responses(:get_object, "NoSuchKey")

      expect { extended_client(sqs: sqs, s3: s3).receive_message(queue_url: StubClients::QUEUE_URL) }
        .to raise_error(Aws::S3::Errors::NoSuchKey)
    end

    it "drops the message when the payload is gone and ignore_payload_not_found is set" do
      stub_pointer_message
      s3.stub_responses(:get_object, "NoSuchKey")

      client = extended_client(sqs: sqs, s3: s3, ignore_payload_not_found: true)
      result = client.receive_message(queue_url: StubClients::QUEUE_URL)

      expect(result.messages).to be_empty
      expect(requests(sqs, :delete_message).first[:params][:receipt_handle]).to eq("real-handle")
    end
  end

  describe "#delete_message" do
    let(:embedded_handle) do
      SqsExtendedClient::ReceiptHandle.embed(
        "real-handle", SqsExtendedClient::PayloadPointer.new(StubClients::BUCKET, "the-key")
      )
    end

    it "deletes the S3 object and sends the original handle" do
      extended_client(sqs: sqs, s3: s3)
        .delete_message(queue_url: StubClients::QUEUE_URL, receipt_handle: embedded_handle)

      expect(requests(s3, :delete_object).first[:params]).to include(bucket: StubClients::BUCKET, key: "the-key")
      expect(requests(sqs, :delete_message).first[:params][:receipt_handle]).to eq("real-handle")
    end

    it "keeps the S3 object when cleanup is disabled" do
      extended_client(sqs: sqs, s3: s3, cleanup_s3_payload: false)
        .delete_message(queue_url: StubClients::QUEUE_URL, receipt_handle: embedded_handle)

      expect(requests(s3, :delete_object)).to be_empty
      expect(requests(sqs, :delete_message).first[:params][:receipt_handle]).to eq("real-handle")
    end
  end

  describe "#change_message_visibility" do
    it "strips the pointer out of the handle" do
      handle = SqsExtendedClient::ReceiptHandle.embed(
        "real-handle", SqsExtendedClient::PayloadPointer.new(StubClients::BUCKET, "the-key")
      )

      extended_client(sqs: sqs, s3: s3)
        .change_message_visibility(queue_url: StubClients::QUEUE_URL, receipt_handle: handle, visibility_timeout: 30)

      expect(requests(sqs, :change_message_visibility).first[:params][:receipt_handle]).to eq("real-handle")
    end
  end

  describe "delegation" do
    it "forwards unknown operations to the SQS client" do
      client = extended_client(sqs: sqs, s3: s3)

      expect(client).to respond_to(:get_queue_url)
      client.get_queue_url(queue_name: "test-queue")
      expect(requests(sqs, :get_queue_url).size).to eq(1)
    end
  end
end
