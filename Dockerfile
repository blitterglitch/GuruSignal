# Based on the Phoenix 1.8 release template. Build and run on Debian trixie.
# Tags verified against docker-library/official-images; pin digests before deployment.
ARG BUILDER_IMAGE=docker.io/library/elixir:1.20.5-otp-29-slim
ARG RUNNER_IMAGE=docker.io/library/debian:trixie-slim
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN elixir -e 'otp = File.read!(Path.join([:code.root_dir(), "releases", :erlang.system_info(:otp_release), "OTP_VERSION"])) |> String.trim(); unless System.version() == "1.20.5" and otp == "29.1.2", do: raise("Builder runtime differs from verified Elixir 1.20.5 / OTP 29.1.2; review the image pin")'
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod --check-locked
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile
RUN mix assets.setup
COPY priv priv
COPY lib lib
RUN mix compile --warnings-as-errors
COPY assets assets
RUN mix assets.deploy
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS runner
RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=C.UTF-8 MIX_ENV=prod PORT=8080 RELEASE_DISTRIBUTION=none
WORKDIR /app
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/guru_signal ./
USER nobody
EXPOSE 8080
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/server"]
