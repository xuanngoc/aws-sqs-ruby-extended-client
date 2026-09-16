# frozen_string_literal: true

require "securerandom"

module SqsExtendedClient
  # Puts, gets and deletes message bodies in S3.
  class PayloadStore
    def initialize(s3_client:, config:)
      @s3_client = s3_client
      @config = config
    end

    def put(payload)
      key = "#{@config.s3_key_prefix}#{SecureRandom.uuid}"
      @s3_client.put_object(
        **@config.s3_put_object_options,
        bucket: @config.bucket_name,
        key: key,
        body: payload
      )
      PayloadPointer.new(@config.bucket_name, key)
    end

    def get(pointer)
      @s3_client.get_object(bucket: pointer.bucket_name, key: pointer.key).body.read
    end

    def delete(pointer)
      @s3_client.delete_object(bucket: pointer.bucket_name, key: pointer.key)
    end
  end
end
