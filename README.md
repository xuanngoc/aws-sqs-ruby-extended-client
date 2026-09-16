# sqs_extended_client

Send and receive Amazon SQS messages larger than the 256 KB limit by storing the body in S3
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

```ruby
client = SqsExtendedClient::Client.new(bucket_name: "my-payload-bucket")

client.send_message(queue_url: queue_url, message_body: huge_json)

response = client.receive_message(queue_url: queue_url)
message = response.messages.first
message.body # the original payload, fetched back from S3

client.delete_message(queue_url: queue_url, receipt_handle: message.receipt_handle)
# deletes the S3 object too
```

Pass your own clients when you need to configure region, credentials or retries:

```ruby
client = SqsExtendedClient::Client.new(
  bucket_name: "my-payload-bucket",
  sqs_client: Aws::SQS::Client.new(region: "ap-southeast-1"),
  s3_client: Aws::S3::Client.new(region: "ap-southeast-1")
)
```

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `bucket_name` | required | S3 bucket the payloads are written to. |
| `payload_size_threshold` | `262_144` | Offload once body + attributes exceed this many bytes. |
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

- SQS allows 10 message attributes and the reserved one takes a slot, so an offloaded message
  may carry at most 9 of your own.
- Nothing here expires S3 objects on its own. Set a lifecycle rule on the bucket so payloads
  from messages that were never consumed do not accumulate.
- The consumer needs `s3:GetObject` and, for cleanup, `s3:DeleteObject` on the bucket.
- On a FIFO queue with content based deduplication, the hash is taken over the pointer, which
  is unique per send. Pass an explicit `message_deduplication_id` for offloaded messages.
- `receive_message` returns a freshly built `Aws::SQS::Types::ReceiveMessageResult`, so the
  Seahorse response context (`.context`, `#successful?`) is not carried through.

## License

Apache-2.0.
