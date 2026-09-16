# frozen_string_literal: true

require "json"

module SqsExtendedClient
  # The reference that takes the place of an offloaded message body.
  #
  # On the wire it is a two element JSON array whose first element is the Java
  # class name the original implementation serialized with. We always write the
  # current name and ignore whatever we read, which is how messages from the
  # legacy v1 Java client stay readable.
  class PayloadPointer
    CLASS_NAME = "software.amazon.payloadoffloading.PayloadS3Pointer"
    LEGACY_CLASS_NAME = "com.amazon.sqs.javamessaging.MessageS3Pointer"

    attr_reader :bucket_name, :key

    def initialize(bucket_name, key)
      @bucket_name = bucket_name
      @key = key
    end

    def self.from_json(json)
      parsed = JSON.parse(json)
      unless parsed.is_a?(Array) && parsed.size == 2 && parsed[1].is_a?(Hash)
        raise InvalidPointerError, "expected a [class_name, pointer] pair, got: #{json.inspect}"
      end

      body = parsed[1]
      bucket_name = body["s3BucketName"]
      key = body["s3Key"]
      if bucket_name.nil? || key.nil?
        raise InvalidPointerError,
              "pointer is missing s3BucketName or s3Key: #{json.inspect}"
      end

      new(bucket_name, key)
    rescue JSON::ParserError => e
      raise InvalidPointerError, "message body is not valid JSON: #{e.message}"
    end

    def to_json(*_args)
      JSON.generate([CLASS_NAME, { "s3BucketName" => bucket_name, "s3Key" => key }])
    end

    def ==(other)
      other.is_a?(PayloadPointer) && other.bucket_name == bucket_name && other.key == key
    end
    alias eql? ==

    def hash
      [bucket_name, key].hash
    end

    def to_s
      "s3://#{bucket_name}/#{key}"
    end
  end
end
