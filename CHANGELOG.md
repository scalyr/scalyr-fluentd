## 0.8.12 - October 6th, 2020

- Update the plugin so we ignore any unicode deserialization related errors which may arise
  serializing events to JSON in case event attribute string value contains bad or partial
  unicode escape sequence.

  Previously, in cases like that, the plugin would throw an exception and such event would not be
  processed.

  Now in cases like this, we recursively sanitize the event values and strip out any bad or partial
  unicode escape sequences.

## 0.8.11 - August 19th, 2020

- Change default value of `ssl_ca_bundle_path` to `nil`, causing the plugin to default to system certs.
- Publish a Docker image of fluentd with this plugin installed to the tag `scalyr/fluentd`.

## 0.8.1 - July 24th, 2020

- Add support for fluentd multiple process workers feature which allows users to configure
  fluentd to launch multiple fluentd workers to utilize multiple CPUs. This comes handy
  under heavy traffic scenarios where you want to split the load across multiple worker
  processes. (#14)
- Remove the monotonically increasing timestamp requirement which is not required by the server
  anymore. This allowed us to get rid of cross-thread synchronization which should simplify
  things. (#15)
