# frozen_string_literal: true

module SqsExtendedClient
  class Configuration
    # SQS caps a message at 256 KiB; anything larger goes to S3.
    DEFAULT_PAYLOAD_SIZE_THRESHOLD = 262_144

    # SQS allows 10 message attributes and the reserved one takes a slot.
    MAX_ALLOWED_ATTRIBUTES = 9

    MAX_S3_KEY_LENGTH = 1024
    UUID_LENGTH = 36
    MAX_S3_KEY_PREFIX_LENGTH = MAX_S3_KEY_LENGTH - UUID_LENGTH
    INVALID_S3_KEY_PREFIX_CHARACTERS = %r{[^a-zA-Z0-9./_-]}

    attr_reader :bucket_name, :s3_key_prefix, :payload_size_threshold, :s3_put_object_options, :always_through_s3,
                :cleanup_s3_payload, :ignore_payload_not_found, :use_legacy_reserved_attribute_name

    alias always_through_s3? always_through_s3
    alias cleanup_s3_payload? cleanup_s3_payload
    alias ignore_payload_not_found? ignore_payload_not_found
    alias use_legacy_reserved_attribute_name? use_legacy_reserved_attribute_name

    def initialize(
      bucket_name:,
      s3_key_prefix: "",
      payload_size_threshold: DEFAULT_PAYLOAD_SIZE_THRESHOLD,
      always_through_s3: false,
      cleanup_s3_payload: true,
      ignore_payload_not_found: false,
      use_legacy_reserved_attribute_name: false,
      s3_put_object_options: {}
    )
      raise ConfigurationError, "bucket_name is required" if bucket_name.nil? || bucket_name.to_s.empty?

      @bucket_name = bucket_name
      @s3_key_prefix = validate_key_prefix(s3_key_prefix)
      @payload_size_threshold = Integer(payload_size_threshold)
      @always_through_s3 = always_through_s3
      @cleanup_s3_payload = cleanup_s3_payload
      @ignore_payload_not_found = ignore_payload_not_found
      @use_legacy_reserved_attribute_name = use_legacy_reserved_attribute_name
      @s3_put_object_options = s3_put_object_options
      freeze
    end

    private

    def validate_key_prefix(prefix)
      trimmed = prefix.to_s.strip
      return trimmed if trimmed.empty?

      if trimmed.length > MAX_S3_KEY_PREFIX_LENGTH
        raise ConfigurationError, "s3_key_prefix must be at most #{MAX_S3_KEY_PREFIX_LENGTH} characters"
      end
      raise ConfigurationError, "s3_key_prefix must not start with '.' or '/'" if trimmed.start_with?(".", "/")
      raise ConfigurationError, "s3_key_prefix must not contain '..'" if trimmed.include?("..")
      if INVALID_S3_KEY_PREFIX_CHARACTERS.match?(trimmed)
        raise ConfigurationError,
              "s3_key_prefix may only contain letters, digits, '/', '_', '-' and '.'"
      end

      trimmed
    end
  end
end
