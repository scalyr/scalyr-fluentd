FROM fluent/fluentd:v1.15.0-1.0

# Use root account to use apk
USER root

COPY ./pkg/fluent-plugin-scalyr-*.gem /
RUN mv /fluent-plugin-scalyr-*.gem /fluent-plugin-scalyr.gem

RUN apk add --no-cache --update --virtual .build-deps \
        sudo build-base ruby-dev \
 && sudo gem install fluent-plugin-scalyr.gem \
 && sudo gem sources --clear-all \
 && apk del .build-deps \
 && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

USER fluent
