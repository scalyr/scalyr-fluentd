FROM fluent/fluentd:v1.18.0-debian AS build

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ruby-dev zlib1g-dev

COPY ./pkg/fluent-plugin-scalyr-*.gem /
RUN mv /fluent-plugin-scalyr-*.gem /fluent-plugin-scalyr.gem
RUN gem install --install-dir /bundle fluent-plugin-scalyr.gem \
    && (cd /bundle; tar czf /bundle.tar.gz .)

FROM fluent/fluentd:v1.18.0-debian

USER root

COPY --from=build /bundle.tar.gz /
RUN tar xzf /bundle.tar.gz -C /usr/local/bundle && rm /bundle.tar.gz

USER fluent
