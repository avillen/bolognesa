import Config

config :bolognesa, :tmdb_read_token, System.get_env("TMDB_READ_TOKEN")

default_library_roots =
  if config_env() == :prod,
    do: "/media/movies",
    else: Path.join(System.tmp_dir!(), "bolognesa-library-dev")

library_roots =
  System.get_env("BOLOGNESA_LIBRARY_ROOTS", default_library_roots)
  |> String.split(":", trim: true)

if config_env() != :test do
  config :bolognesa, :library_roots, library_roots
end

if config_env() != :test do
  config :bolognesa,
         :transcode_root,
         System.get_env(
           "BOLOGNESA_TRANSCODE_ROOT",
           if(config_env() == :prod,
             do: "/transcode",
             else: Path.join(System.tmp_dir!(), "bolognesa-transcode")
           )
         )
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/bolognesa start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :bolognesa, BolognesaWeb.Endpoint, server: true
end

config :bolognesa, BolognesaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :bolognesa, BolognesaWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/bolognesa_web/router\.ex$"E,
        ~r"lib/bolognesa_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :bolognesa, Bolognesa.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  lan_http? = System.get_env("BOLOGNESA_LAN_HTTP") == "true"
  check_origin = BolognesaWeb.EndpointOriginPolicy.from_env(System.get_env("PHX_CHECK_ORIGIN"))
  public_scheme = if lan_http?, do: "http", else: "https"

  public_port =
    String.to_integer(System.get_env("PUBLIC_PORT") || if(lan_http?, do: "4000", else: "443"))

  http_options =
    if lan_http? do
      bind_ip =
        case :inet.parse_ipv4_address(String.to_charlist(System.get_env("BIND_IP", "0.0.0.0"))) do
          {:ok, address} -> address
          {:error, reason} -> raise "invalid BIND_IP: #{inspect(reason)}"
        end

      [port: String.to_integer(System.get_env("PORT", "4000")), ip: bind_ip]
    else
      [
        port: String.to_integer(System.get_env("PORT", "4000")),
        ip: {0, 0, 0, 0, 0, 0, 0, 0}
      ]
    end

  config :bolognesa, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :bolognesa, BolognesaWeb.Endpoint,
    url: [host: host, port: public_port, scheme: public_scheme],
    http: http_options,
    secret_key_base: secret_key_base,
    check_origin: check_origin

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :bolognesa, BolognesaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :bolognesa, BolognesaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :bolognesa, Bolognesa.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
