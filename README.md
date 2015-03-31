Scalyr plugin for Fluentd
=========================

This is the scalar plugin for fluentd.

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

Usage
-----

In your fluent.conf file, set up a match for any tag you'd like to send to Scalyr e.g. 

```
<match apache.access>
  @type scalyr
  ...

</match>
```

Valid fields are:

*  api_write_token - string - Your Scalyr write token (see: https://www.scalyr.com/keys)
*  session_info - hash - A hash of { "key": "value" } pairs that will be sent in the sessionInfo section of a request to add events to Scalyr
*  Any field from BufferedOutput e.g.
   *  flush_interval - time value - the time interval to flush the buffer and send logs to Scalyr e.g. 5s, 10s etc.
   *   buffer_chunk_limit - size value - the maximum buffer chunk size before sending logs to Scalyr e.g. 64k, 1m etc.


Notes
-----
Each match block will have a unique Scalyr session id.  If you wish multiple logs to use the same session id then make sure to match all of those logs in the same block.

fluentd tag names will be used for Scalyr thread names.

If you want to sent raw logs, rather than parsed/formatted json, make sure to specify

```
  format none
```

in your log source.
