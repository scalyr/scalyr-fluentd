## 0.8.18 - June 13, 2024
- Update fluentd docker image to `v1.17.0-1.0`

## 0.8.17 - June 21, 2022

- Update rake requirement from ~> 0.9 to ~> 13.0
- Update yajl-ruby from 1.4.1 to 1.4.3
- Update rexml from 3.2.4 to 3.2.5
- Update fluentd from 1.11.1 to 1.14.6
  - Update fluentd corresponding dependencies

## 0.8.16 - February 14th, 2022

- Include plugin gem name and version in the "User-Agent" header when uploading logs.

## 0.8.15 - February 2nd, 2022

- Improve handling of records cannot fit within the configured `max_request_buffer`.
  Single large records will now have the message field truncated to fit within a request if possible,
  and dropped otherwise.

## 0.8.14 - October 28th, 2021

- Updates to automated release deployment to have `latest` tag in dockerhub updated correctly.

## 0.8.13 - October 26th, 2021

- Add a new configuration option `parser` for setting a per-event "parser" field without
  having to use filters. This is intended to be used in cases where configuring a filter
  is more difficult, such as Fargate.

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
