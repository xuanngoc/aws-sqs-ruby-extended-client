# frozen_string_literal: true

require "aws-sdk-s3"
require "aws-sdk-sqs"

require_relative "sqs_extended_client/version"
require_relative "sqs_extended_client/errors"
require_relative "sqs_extended_client/configuration"
require_relative "sqs_extended_client/payload_pointer"
require_relative "sqs_extended_client/receipt_handle"
require_relative "sqs_extended_client/payload_store"
require_relative "sqs_extended_client/client"

module SqsExtendedClient
  def self.new(...)
    Client.new(...)
  end
end
