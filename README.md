Scalyr output plugin for Fluentd
=========================

Overview
--------

The **Scalyr** output plugin buffers events from fluent and posts them to [Scalyr](http://www.scalyr.com).

Events are uploaded either periodly (e.g. every 5 seconds) or once the buffer reaches a certain size (e.g. 64k).

Fluentd may format log messages into json or some other format.  If you want to send raw logs to Scalyr then in your configuration &lt;source&gt; be sure to specify

```
  format none
```

The Scalyr output plugin assigns a unique Scalyr session id for each Fluentd &lt;match&gt; block.  It is recommended that a single machine doesn't create too many simultaneous Scalyr sessions, so if possible you should try to have a single match for all logs you wish to send to Scalyr.

This can be done by specifying tags such as scalyr.apache, scalyr.maillog etc and matching on scalyr.\*

Fluentd tag names will be used for Scalyr thread names.

Configuration
-------------

The Scalyr output plugin has a number of sensible defaults so the minimum configuration only requires your Scalyr 'write logs' token.

```
<match scalyr.*>
  type @scalyr
  api_write_token YOUR_SCALYR_WRITE_LOGS_TOKEN
</match>
```

The following configuration options are also supported:

```
<match scalyr.*>
  type @scalyr

  #scalyr specific options
  api_write_token YOUR_SCALYR_WRITE_TOKEN
  session_info { "host":"some-host",
                 "custom":"your custom session info"
               }

  add_events https://www.scalyr.com/addEvents
  ssl_ca_bundle_path /etc/ssl/certs/ca-bundle.crt
  ssl_verify_peer true
  ssl_verify_depth 5

  #buffered output options
  retry_limit 40
  retry_wait 5s
  max_retry_wait 30s
  flush_interval 5s
  buffer_chunk_limit 100k
  buffer_queue_limit 1024
  num_threads 1

</match>
```

####Scalyr specific options

***api_write_token*** - your Scalyr write logs token. See [here](http://www.scalyr.com/keys) for more details.  This value **must** be specified.

***session_info*** - a JSON hash containing custom session info you want to include with each log request.  This value is optional and defaults to *nil*.

***add_events*** - the URL endpoint for adding events to Scalyr. This value is optional and defaults to https://www.scalyr.com/addEvents

***ssl_ca_bundle_path*** - a path on your server pointing to a valid certificate bundle.  This value is optional and defaults to */etc/ssl/certs/ca-bundle.crt*.

**Note:** if the certificate bundle does not contain a certificate chain that verifies the Scalyr SSL certificate then all requests to Scalyr will fail unless ***ssl_verify_peer*** is set to false.  If you suspect logging to Scalyr is failing due to an invalid certificate chain, you can grep through the Fluentd stderr for warnings that contain the message 'certificate verify failed'.  The full text of such warnings will look something like this:
>2015-03-31 11:16:39 -0400 [warn]: fluent/output.rb:354:rescue in try_flush: temporarily failed to flush the buffer. next_retry=2015-03-31 11:16:43 -0400 error_class="OpenSSL::SSL::SSLError" error="SSL_connect returned=1 errno=0 state=SSLv3 read server certificate B: certificate verify failed" plugin_id=“object:bd1154"

The cURL project maintains CA certificate bundles automatically converted from mozilla.org [here](http://curl.haxx.se/docs/caextract.html).

***ssl_verify_peer*** - verify SSL certificates when sending requests to Scalyr.  This value is optional, and defaults to *true*.

***ssl_verify_depth*** - the depth to use when verifying certificates.  This value is optional, and defaults to *5*.


####BufferedOutput options (inherited from Fluent::BufferedOutput)

***retry_limit*** - the maximum number of times to retry a failed post request before giving up.  Defaults to *40*.

***retry_wait*** - the initial time to wait before retrying a failed request.  Defaults to *5 seconds*.  Wait times will increase up to a maximum of ***max_retry_wait***

***max_retry_wait*** - the maximum time to wait between retrying failed requests.  Defaults to *30 seconds*.  **Note:** This is not the total maximum time of all retry waits, but rather the maximum time to wait for a single retry.

***flush_interval*** - how often to upload logs to Scalyr.  Defaults to *5 seconds*.

***buffer_chunk_limit*** - the maximum amount of log data to send to Scalyr in a single request.  Defaults to *100KB*.  **Note:** if you set this value too large, then Scalyr may reject your requests.  Requests smaller than 1MB will typically be accepted by Scalyr, but note that the 1MB limit also includes the entire request body and all associated JSON keys and punctuation, which may be considerably larger than the raw log data.

***buffer_queue_limit*** - the maximum number of chunks to buffer before dropping new log requests.  Defaults to *1024*.  Combines with ***buffer_chunk_limit*** to give you the total amount of buffer to use in the event of request failures before dropping requests.

***num_threads*** - the number of threads to use to upload logs.  Defaults to *1*.  In the event where there are multiple unsent buffer chunks in the queue, set this option to &gt; 1 to use multiple threads to send the data.  **Note:** be careful about setting this value too high because if too many requests come in over too short a timespan, Scalyr may start rejecting requests.

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
