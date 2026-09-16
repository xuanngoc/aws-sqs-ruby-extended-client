# frozen_string_literal: true

module SqsExtendedClient
  class Error < StandardError; end

  # Raised when the client is built with options it cannot work with.
  class ConfigurationError < Error; end

  # Raised when a message body is flagged as offloaded but is not a valid pointer.
  class InvalidPointerError < Error; end

  # Raised when outgoing message attributes violate the extended client's limits.
  class MessageAttributeError < Error; end
end
