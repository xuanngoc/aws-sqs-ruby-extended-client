# sqs_extended_client

Send and receive Amazon SQS messages larger than the 1 MiB limit by storing the body in S3
and putting a small pointer on the queue instead. It is a wrapper around `Aws::SQS::Client`,
so anything it does not need to touch is delegated straight through.

The wire format matches the AWS
[Java](https://github.com/awslabs/amazon-sqs-java-extended-client-lib) and
[Python](https://github.com/awslabs/amazon-sqs-python-extended-client-lib) extended clients:
a Ruby producer can publish to a queue a Java consumer drains, and the other way round.

## Installation

```ruby
gem "sqs_extended_client"
```

Requires Ruby 3.1 or newer, and is tested on Ruby 4.

## Usage

Build the client once and hold onto it. Pass your own SQS and S3 clients when you need to set
region, credentials or retries; every other keyword is an option from the table below.

```ruby
client = SqsExtendedClient::Client.new(
  bucket_name: "my-payload-bucket",
  sqs_client: Aws::SQS::Client.new(region: "ap-southeast-1"),
  s3_client: Aws::S3::Client.new(region: "ap-southeast-1")
)
```

### Sending

Send as you would with the plain SQS client. Bodies under the threshold go straight to the
queue; anything larger is written to S3 first and the queue gets a pointer.

```ruby
client.send_message(
  queue_url: queue_url,
  message_body: JSON.generate(order),  # any size
  message_attributes: {
    "event_type" => { data_type: "String", string_value: "order.created" }
  }
)
```

Batches work the same way, each entry is offloaded on its own:

```ruby
client.send_message_batch(
  queue_url: queue_url,
  entries: orders.each_with_index.map do |order, index|
    { id: index.to_s, message_body: JSON.generate(order) }
  end
)
```

Mind the batch cap: SQS limits a `SendMessageBatch` to 1 MiB **in total**, the same number as
the per-message limit. The threshold here is per message, so ten 500 KiB bodies are each under
it, none are offloaded, and the batch is rejected with `BatchRequestTooLong`. When you batch
large payloads, set `payload_size_threshold` to roughly the batch cap divided by the number of
entries so they offload to pointers first.

### Polling

A worker loop. `receive_message` fetches the body back from S3 before you see it, and
`delete_message` removes the S3 object along with the message:

```ruby
loop do
  response = client.receive_message(
    queue_url: queue_url,
    max_number_of_messages: 10,
    wait_time_seconds: 20,   # long polling, keeps the loop from spinning
    visibility_timeout: 60   # must comfortably exceed your processing time
  )

  response.messages.each do |message|
    process(JSON.parse(message.body))

    client.delete_message(queue_url: queue_url, receipt_handle: message.receipt_handle)
  rescue StandardError => e
    # Leave the message alone and let SQS redeliver it after the visibility timeout.
    logger.error("failed to process #{message.message_id}: #{e.message}")
  end
end
```

Delete only after the work succeeded. Deleting first would drop the S3 object too, so a
redelivery would arrive pointing at an object that is no longer there.

To delete in batches, pass the receipt handles through unchanged — the pointer travels inside
them, and each entry is cleaned up from S3 individually:

```ruby
client.delete_message_batch(
  queue_url: queue_url,
  entries: processed.each_with_index.map do |message, index|
    { id: index.to_s, receipt_handle: message.receipt_handle }
  end
)
```

If processing runs long, extend the lease with `change_message_visibility`; it accepts the
receipt handle you were given and strips the pointer out before the call reaches SQS:

```ruby
client.change_message_visibility(
  queue_url: queue_url,
  receipt_handle: message.receipt_handle,
  visibility_timeout: 300
)
```

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `bucket_name` | required | S3 bucket the payloads are written to. |
| `payload_size_threshold` | `1_048_576` | Offload once body + attributes exceed this many bytes. |
| `always_through_s3` | `false` | Offload every message regardless of size. |
| `cleanup_s3_payload` | `true` | Delete the S3 object when the message is deleted. |
| `ignore_payload_not_found` | `false` | On a missing S3 object, delete the SQS message and skip it instead of raising. |
| `use_legacy_reserved_attribute_name` | `false` | Flag messages with `SQSLargePayloadSize` instead of `ExtendedPayloadSize`. |
| `s3_key_prefix` | `""` | Prefix for generated keys, e.g. `"payloads/"`. |
| `s3_put_object_options` | `{}` | Merged into `put_object`, e.g. `{ server_side_encryption: "aws:kms" }`. |

## How it works

An offloaded message carries a `Number` attribute named `ExtendedPayloadSize` holding the
original body size, and its body is replaced by

```json
["software.amazon.payloadoffloading.PayloadS3Pointer",{"s3BucketName":"...","s3Key":"..."}]
```

The first element is the Java class name the original implementation serialized with. This
gem always writes the current name and ignores whatever it reads, so messages from the legacy
v1 Java client — which used `com.amazon.sqs.javamessaging.MessageS3Pointer` and the
`SQSLargePayloadSize` attribute — are read without any extra configuration.

`delete_message` only receives a receipt handle, so on receive the bucket and key are spliced
into the handle between markers:

```
-..s3BucketName..-{bucket}-..s3BucketName..--..s3Key..-{key}-..s3Key..-{real handle}
```

`delete_message`, `delete_message_batch` and `change_message_visibility` strip that back off
before the call reaches SQS. Because a message received here may be deleted by a Java or
Python consumer (and vice versa), those markers are part of the wire contract.

Only the operations that need it are overridden: `send_message`, `send_message_batch`,
`receive_message`, `delete_message`, `delete_message_batch`, `change_message_visibility` and
`change_message_visibility_batch`. Every other SQS call is forwarded unchanged.

## Caveats

- The default threshold follows the current SQS limit of 1 MiB, which AWS raised from 256 KiB
  in August 2025. The AWS Java and Python extended clients still default to 262_144, so the
  same payload may offload there and go inline here. That is a local cost decision, not a
  compatibility one: both sides read whatever they are given. Set
  `payload_size_threshold: 262_144` to match them, and do the same against an SQS-compatible
  endpoint such as LocalStack or ElasticMQ that has not adopted the larger limit.
- SQS allows 10 message attributes and the reserved one takes a slot, so an offloaded message
  may carry at most 9 of your own.
- Nothing here expires S3 objects on its own. Set a lifecycle rule on the bucket so payloads
  from messages that were never consumed do not accumulate.
- The consumer needs `s3:GetObject` and, for cleanup, `s3:DeleteObject` on the bucket.
- On a FIFO queue with content based deduplication, the hash is taken over the pointer, which
  is unique per send. Pass an explicit `message_deduplication_id` for offloaded messages.
- `receive_message` returns a freshly built `Aws::SQS::Types::ReceiveMessageResult`, so the
  Seahorse response context (`.context`, `#successful?`) is not carried through.

## Credits

The design is not original to this gem. The approach, and every byte of the wire format it
speaks, come from the [Amazon SQS Extended Client Library for Java](https://github.com/awslabs/amazon-sqs-java-extended-client-lib)
and its supporting [payload offloading library](https://github.com/awslabs/payload-offloading-java-common-lib-for-aws),
both Apache-2.0 licensed and copyright Amazon.com, Inc. or its affiliates. AWS also publishes
an [official Python implementation](https://github.com/awslabs/amazon-sqs-python-extended-client-lib).

This is an independent reimplementation in Ruby. No source code from those projects is
included here, and the project is not affiliated with, endorsed by, or sponsored by Amazon
Web Services.

## License

Apache-2.0, matching the library this one follows. See [LICENSE.txt](LICENSE.txt) and
[NOTICE](NOTICE).
