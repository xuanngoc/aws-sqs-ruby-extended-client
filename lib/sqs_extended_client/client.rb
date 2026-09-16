# frozen_string_literal: true

module SqsExtendedClient
  # A drop-in wrapper around Aws::SQS::Client that offloads large message bodies
  # to S3 and puts them back on the way out, wire compatible with the AWS Java
  # and Python extended clients. Anything it does not override is delegated
  # untouched to the underlying SQS client.
  class Client
    RESERVED_ATTRIBUTE_NAME = "ExtendedPayloadSize"
    LEGACY_RESERVED_ATTRIBUTE_NAME = "SQSLargePayloadSize"
    RESERVED_ATTRIBUTE_NAMES = [RESERVED_ATTRIBUTE_NAME, LEGACY_RESERVED_ATTRIBUTE_NAME].freeze

    attr_reader :sqs_client, :s3_client, :config

    def initialize(bucket_name:, sqs_client: nil, s3_client: nil, **options)
      @config = Configuration.new(bucket_name: bucket_name, **options)
      @sqs_client = sqs_client || Aws::SQS::Client.new
      @s3_client = s3_client || Aws::S3::Client.new
      @payload_store = PayloadStore.new(s3_client: @s3_client, config: @config)
    end

    def send_message(params = {})
      sqs_client.send_message(**offload(params))
    end

    def send_message_batch(params = {})
      sqs_client.send_message_batch(**params, entries: params.fetch(:entries).map { |entry| offload(entry) })
    end

    def receive_message(params = {})
      params = params.merge(message_attribute_names: requested_attribute_names(params[:message_attribute_names]))
      response = sqs_client.receive_message(**params)
      messages = response.messages.filter_map { |message| restore(message, params.fetch(:queue_url)) }
      Aws::SQS::Types::ReceiveMessageResult.new(messages: messages)
    end

    def delete_message(params = {})
      receipt_handle = params.fetch(:receipt_handle)
      cleanup_payload(receipt_handle)
      sqs_client.delete_message(**params, receipt_handle: ReceiptHandle.strip(receipt_handle))
    end

    def delete_message_batch(params = {})
      entries = params.fetch(:entries).map do |entry|
        receipt_handle = entry.fetch(:receipt_handle)
        cleanup_payload(receipt_handle)
        entry.merge(receipt_handle: ReceiptHandle.strip(receipt_handle))
      end
      sqs_client.delete_message_batch(**params, entries: entries)
    end

    def change_message_visibility(params = {})
      sqs_client.change_message_visibility(**params, receipt_handle: ReceiptHandle.strip(params.fetch(:receipt_handle)))
    end

    def change_message_visibility_batch(params = {})
      entries = params.fetch(:entries).map do |entry|
        entry.merge(receipt_handle: ReceiptHandle.strip(entry.fetch(:receipt_handle)))
      end
      sqs_client.change_message_visibility_batch(**params, entries: entries)
    end

    def respond_to_missing?(name, include_private = false)
      sqs_client.respond_to?(name, include_private) || super
    end

    def method_missing(name, ...)
      return super unless sqs_client.respond_to?(name)

      sqs_client.public_send(name, ...)
    end

    private

    # Send path: swap the body for a pointer and flag the message.
    def offload(params)
      attributes = params[:message_attributes] || {}
      validate_attributes!(attributes)

      body = params.fetch(:message_body)
      return params unless config.always_through_s3? || large?(body, attributes)

      pointer = @payload_store.put(body)
      params.merge(
        message_body: pointer.to_json,
        message_attributes: attributes.merge(
          reserved_attribute_name => { data_type: "Number", string_value: body.bytesize.to_s }
        )
      )
    end

    # Receive path: pull the body back out of S3 and hide our bookkeeping.
    # Returns nil for a message that was dropped, see ignore_payload_not_found.
    def restore(message, queue_url)
      attributes = message.message_attributes || {}
      return message unless RESERVED_ATTRIBUTE_NAMES.any? { |name| attributes.key?(name) }

      pointer = PayloadPointer.from_json(message.body)
      begin
        body = @payload_store.get(pointer)
      rescue Aws::S3::Errors::NoSuchKey
        raise unless config.ignore_payload_not_found?

        sqs_client.delete_message(queue_url: queue_url, receipt_handle: message.receipt_handle)
        return nil
      end

      rebuild(
        message,
        body: body,
        message_attributes: attributes.except(*RESERVED_ATTRIBUTE_NAMES),
        receipt_handle: ReceiptHandle.embed(message.receipt_handle, pointer)
      )
    end

    def cleanup_payload(receipt_handle)
      return unless config.cleanup_s3_payload? && ReceiptHandle.embedded?(receipt_handle)

      @payload_store.delete(ReceiptHandle.pointer(receipt_handle))
    end

    # Ask for the reserved attributes on top of whatever the caller wanted, so a
    # receive that names specific attributes still tells us the body is a pointer.
    def requested_attribute_names(names)
      ((names || []) - RESERVED_ATTRIBUTE_NAMES) + RESERVED_ATTRIBUTE_NAMES
    end

    def reserved_attribute_name
      config.use_legacy_reserved_attribute_name? ? LEGACY_RESERVED_ATTRIBUTE_NAME : RESERVED_ATTRIBUTE_NAME
    end

    def large?(body, attributes)
      body.bytesize + attributes_size(attributes) > config.payload_size_threshold
    end

    def validate_attributes!(attributes)
      size = attributes_size(attributes)
      if size > config.payload_size_threshold
        raise MessageAttributeError,
              "message attributes total #{size} bytes, over the #{config.payload_size_threshold} byte threshold; " \
              "put the payload in the message body instead"
      end

      if attributes.size > Configuration::MAX_ALLOWED_ATTRIBUTES
        raise MessageAttributeError,
              "#{attributes.size} message attributes exceeds the maximum of " \
              "#{Configuration::MAX_ALLOWED_ATTRIBUTES} for large payload messages"
      end

      reserved = RESERVED_ATTRIBUTE_NAMES.find { |name| attributes.key?(name) }
      return if reserved.nil?

      raise MessageAttributeError, "message attribute #{reserved} is reserved by the extended client"
    end

    def attributes_size(attributes)
      attributes.sum do |name, value|
        size = name.to_s.bytesize
        size += attribute_field(value, :data_type).to_s.bytesize
        size += attribute_field(value, :string_value).to_s.bytesize
        size + attribute_field(value, :binary_value).to_s.bytesize
      end
    end

    # Attribute values arrive as hashes on the way out and as SDK structs on the
    # way in; read either.
    def attribute_field(value, name)
      return value.public_send(name) unless value.is_a?(Hash)

      value[name] || value[name.to_s]
    end

    # SDK response structs are rebuilt rather than mutated so nested members survive.
    def rebuild(message, **overrides)
      members = message.members.to_h { |member| [member, message[member]] }
      Aws::SQS::Types::Message.new(**members, **overrides)
    end
  end
end
