# frozen_string_literal: true

module SqsExtendedClient
  # Deleting a message has to delete its S3 object too, but delete_message only
  # carries a receipt handle. The Java client solves this by prefixing the real
  # handle with the bucket and key between markers, and stripping them back off
  # before the call reaches SQS. The markers below are wire format: a message
  # received here may well be deleted by a Java or Python consumer.
  module ReceiptHandle
    BUCKET_MARKER = "-..s3BucketName..-"
    KEY_MARKER = "-..s3Key..-"

    module_function

    def embed(receipt_handle, pointer)
      "#{BUCKET_MARKER}#{pointer.bucket_name}#{BUCKET_MARKER}" \
        "#{KEY_MARKER}#{pointer.key}#{KEY_MARKER}#{receipt_handle}"
    end

    def embedded?(receipt_handle)
      receipt_handle.include?(BUCKET_MARKER) && receipt_handle.include?(KEY_MARKER)
    end

    # The original SQS receipt handle, i.e. everything after the closing key marker.
    def strip(receipt_handle)
      return receipt_handle unless embedded?(receipt_handle)

      closing = receipt_handle.index(KEY_MARKER, receipt_handle.index(KEY_MARKER) + KEY_MARKER.length)
      receipt_handle[(closing + KEY_MARKER.length)..]
    end

    def pointer(receipt_handle)
      PayloadPointer.new(between_markers(receipt_handle, BUCKET_MARKER), between_markers(receipt_handle, KEY_MARKER))
    end

    def between_markers(receipt_handle, marker)
      opening = receipt_handle.index(marker)
      closing = receipt_handle.index(marker, opening + marker.length)
      receipt_handle[(opening + marker.length)...closing]
    end
    private_class_method :between_markers
  end
end
