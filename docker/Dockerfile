FROM fluent/fluentd:v1.15.0-1.0

#USER root

COPY ./pkg/fluent-plugin-scalyr-*.gem /
RUN mv /fluent-plugin-scalyr-*.gem /fluent-plugin-scalyr.gem

gem install fluent-plugin-scalyr.gem \
 && gem sources --clear-all \
 && apk del .build-deps \
 && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

#USER fluent
