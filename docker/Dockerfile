FROM fluent/fluentd:v1.15.0-1.0

#USER root

COPY ./pkg/fluent-plugin-scalyr-*.gem /

RUN gem install /fluent-plugin-scalyr-0.8.17.gem
# && gem sources --clear-all \
# && apk del .build-deps \
# && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

#USER fluent
