## 0.8.1 - July 24th, 2020

- Add support for fluentd multiple process workers feature which allows users to configure
  fluentd to launch multiple fluentd workers to utilize multiple CPUs. This comes handy
  under heavy traffic scenarios where you want to split the load across multiple worker
  processes. (#14)
- Remove the monotonically increasing timestamp requirement which is not required by the server
  anymore. This allowed us to get rid of cross-thread synchronization which should simplify
  things. (#15)
