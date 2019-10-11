Scalyr output plugin for Fluentd
=========================

**Note:** Fluentd introduced breaking changes to their plugin API between
version 0.12 and 0.14.

The current master branch of the scalyr-fluentd plugin is compatible with
Fluentd version 0.14 and above, including fluentd v1.0.0.

If you wish to use the scalyr-fluentd plugin with Fluentd version 0.12 or
earlier, please use the [fluentd-0.12
branch](https://github.com/scalyr/scalyr-fluentd/tree/cbd8c2aac3d11472121345c7cad6587a7f68c115).

Overview
--------

The **Scalyr** output plugin buffers events from fluent and posts them to [Scalyr](http://www.scalyr.com).

Events are uploaded either periodically (e.g. every 5 seconds) or once the buffer reaches a certain size (e.g. 64k).

Fluentd may format log messages into json or some other format.  If you want to send raw logs to Scalyr then in your configuration &lt;source&gt; be sure to specify

```
  format none
```

The Scalyr output plugin assigns a unique Scalyr session id for each Fluentd &lt;match&gt; block.  It is recommended that a single machine doesn't create too many simultaneous Scalyr sessions, so if possible you should try to have a single match for all logs you wish to send to Scalyr.

This can be done by specifying tags such as scalyr.apache, scalyr.maillog etc and matching on scalyr.\*

Fluentd tag names will be used for the logfile name in Scalyr.

Scalyr Parsers and Custom Fields
--------------------------------

You may also need to specify a Scalyr parser for your log message or add custom fields to each log event. This can be done using Fluentd's filter mechanism, in particular the [record_transformer filter](https://docs.fluentd.org/filter/record_transformer).

For example, if you want to use Scalyr's ```accessLog``` parser for all events with the ```scalyr.access``` tag you would add the following to your fluent.conf file:

```
<filter scalyr.access>
  @type record_transformer
  <record>
    parser accessLog
  </record>
</filter>
```

Plugin Configuration
-------------

The Scalyr output plugin has a number of sensible defaults so the minimum configuration only requires your Scalyr 'write logs' token.

```
<match scalyr.*>
  @type scalyr
  api_write_token YOUR_SCALYR_WRITE_LOGS_TOKEN
</match>
```

The following configuration options are also supported:

```
<match scalyr.*>
  @type scalyr

  #scalyr specific options
  api_write_token YOUR_SCALYR_WRITE_TOKEN
  compression_type bz2
  use_hostname_for_serverhost true
  server_attributes {
    "serverHost": "front-1",
    "serverType": "frontend",
    "region":     "us-east-1"
  }

  scalyr_server https://agent.scalyr.com/
  ssl_ca_bundle_path /etc/ssl/certs/ca-bundle.crt
  ssl_verify_peer true
  ssl_verify_depth 5
  message_field message

  max_request_buffer 3000000

  force_message_encoding nil
  replace_invalid_utf8 false

  #buffered output options
  <buffer>
    retry_max_times 40
    retry_wait 5s
    retry_max_interval 30s
    flush_interval 5s
    flush_thread_count 1
    chunk_limit_size 2.5m
    queue_limit_length 1024
  </buffer>

</match>
```

### Scalyr specific options

***compression_type*** - compress Scalyr traffic to reduce network traffic. Options are `bz2` and `deflate`. See [here](https://www.scalyr.com/help/scalyr-agent#compressing) for more details.  This feature is optional.

***api_write_token*** - your Scalyr write logs token. See [here](http://www.scalyr.com/keys) for more details.  This value **must** be specified.

***server_attributes*** - a JSON hash containing custom server attributes you want to include with each log request.  This value is optional and defaults to *nil*.

***use_hostname_for_serverhost*** - if `true` then if `server_attributes` is nil or it does *not* include a field called `serverHost` then the plugin will add the `serverHost` field with the value set to the hostname that fluentd is running on.  Defaults to `true`.

***scalyr_server*** - the Scalyr server to send API requests to. This value is optional and defaults to https://agent.scalyr.com/

***ssl_ca_bundle_path*** - a path on your server pointing to a valid certificate bundle.  This value is optional and defaults to */etc/ssl/certs/ca-bundle.crt*.

**Note:** if the certificate bundle does not contain a certificate chain that verifies the Scalyr SSL certificate then all requests to Scalyr will fail unless ***ssl_verify_peer*** is set to false.  If you suspect logging to Scalyr is failing due to an invalid certificate chain, you can grep through the Fluentd output for warnings that contain the message 'certificate verification failed'.  The full text of such warnings will look something like this:

>2015-04-01 08:47:05 -0400 [warn]: plugin/out_scalyr.rb:85:rescue in write: SSL certificate verification failed.  Please make sure your certificate bundle is configured correctly and points to a valid file. You can configure this with the ssl_ca_bundle_path configuration option. The current value of ssl_ca_bundle_path is '/etc/ssl/certs/ca-bundle.crt'

>2015-04-01 08:47:05 -0400 [warn]: plugin/out_scalyr.rb:87:rescue in write: SSL_connect returned=1 errno=0 state=SSLv3 read server certificate B: certificate verify failed

>2015-04-01 08:47:05 -0400 [warn]: plugin/out_scalyr.rb:88:rescue in write: Discarding buffer chunk without retrying or logging to &lt;secondary&gt;

The cURL project maintains CA certificate bundles automatically converted from mozilla.org [here](http://curl.haxx.se/docs/caextract.html).

***ssl_verify_peer*** - verify SSL certificates when sending requests to Scalyr.  This value is optional, and defaults to *true*.

***ssl_verify_depth*** - the depth to use when verifying certificates.  This value is optional, and defaults to *5*.

***message_field*** - Scalyr expects all log events to have a 'message' field containing the contents of a log message.  If your event has the log message stored in another field, you can specify the field name here, and the plugin will rename that field to 'message' before sending the data to Scalyr.  **Note:** this will override any existing 'message' field if the log record contains both a 'message' field and the field specified by this config option.

***max_request_buffer*** - The maximum size in bytes of each request to send to Scalyr.  Defaults to 3,000,000 (3MB).  Fluentd chunks that generate JSON requests larger than the max_request_buffer will be split in to multiple separate requests.  **Note:** The maximum size the Scalyr servers accept for this value is 6MB and requests containing data larger than this will be rejected.

***force_message_encoding*** - Set a specific encoding for all your log messages (defaults to nil).  If your log messages are not in UTF-8, this can cause problems when converting the message to JSON in order to send to the Scalyr server.  You can avoid these problems by setting an encoding for your log messages so they can be correctly converted.

***replace_invalid_utf8*** - If this value is true and ***force_message_encoding*** is set to 'UTF-8' then all invalid UTF-8 sequences in log messages will be replaced with <?>.  Defaults to false.  This flag has no effect if ***force_message_encoding*** is not set to 'UTF-8'.

### Buffer options

***retry_max_times*** - the maximum number of times to retry a failed post request before giving up.  Defaults to *40*.

***retry_wait*** - the initial time to wait before retrying a failed request.  Defaults to *5 seconds*.  Wait times will increase up to a maximum of ***retry_max_interval***

***retry_max_interval*** - the maximum time to wait between retrying failed requests.  Defaults to *30 seconds*.  **Note:** This is not the total maximum time of all retry waits, but rather the maximum time to wait for a single retry.

***flush_interval*** - how often to upload logs to Scalyr.  Defaults to *5 seconds*.

***flush_thread_count*** - the number of threads to use to upload logs.  This is currently fixed to 1 will cause fluentd to fail with a ConfigError if set to anything greater.

***chunk_limit_size*** - the maximum amount of log data to send to Scalyr in a single request.  Defaults to *2.5MB*.  **Note:** if you set this value too large, then Scalyr may reject your requests.  Requests smaller than 6 MB will typically be accepted by Scalyr, but note that the 6 MB limit also includes the entire request body and all associated JSON keys and punctuation, which may be considerably larger than the raw log data.  This value should be set lower than the `max_request_buffer` option.

***queue_limit_length*** - the maximum number of chunks to buffer before dropping new log requests.  Defaults to *1024*.  Combines with ***chunk_limit_size*** to give you the total amount of buffer to use in the event of request failures before dropping requests.

Secondary Logging
-----------------

Fluentd also supports &lt;secondary&gt; logging for all buffered output for when the primary output fails (see the Fluentd [documentation](http://docs.fluentd.org/articles/output-plugin-overview#secondary-output) for more details).  This is also supported by the Scalyr output plugin.

**Note:** There are certain conditions that may cause the Scalyr plugin to discard a buffer without logging it to secondary output.  This will currently happen if:
*  SSL certificate verification fails when sending a request
*  An errant configuration is flooding the Scalyr servers with requests, and the servers respond by dropping/ignoring the logs.

Installation
------------

Run

```
rake build

```

Which builds the gem and puts it in the pkg directory, then install the Gem using fluent's gem manager

```
fluent-gem install pkg/fluent-plugin-scalyr-<VERSION>.gem
```
