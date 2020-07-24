## 0.8.1 - July 24th, 2020

- Add support for fluentd multiple process workers feature which allows users to configure
  fluentd to launch multiple fluentd workers to utilize multiple CPUs.
- Remove the monotonically increasing timestamp requirement which is not required by the server
  anymore. (#15)
