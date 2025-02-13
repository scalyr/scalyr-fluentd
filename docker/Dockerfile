FROM fluent/fluentd:v1.17.1-debian-1.2

USER root

COPY ./pkg/fluent-plugin-scalyr-*.gem /
RUN mv /fluent-plugin-scalyr-*.gem /fluent-plugin-scalyr.gem

RUN --mount=type=cache,target=/var/cache/apt/,sharing=locked --mount=type=cache,target=/var/lib/apt/lists/,sharing=locked \
    apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
		ruby-dev \
        zlib1g-dev \
 && gem install fluent-plugin-scalyr.gem \
 && gem sources --clear-all \
 && apt-get autoremove -y \
 && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

USER fluent
