defmodule BolognesaWeb.Router do
  use BolognesaWeb, :router
  import BolognesaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BolognesaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  pipeline :media do
    plug :fetch_session
    plug :put_secure_browser_headers
    plug :fetch_current_scope
    plug :require_authenticated_media
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BolognesaWeb do
    pipe_through :browser

    post "/login", SessionController, :create

    live_session :public_access do
      live "/setup", Setup.Live, :new
      live "/login", Login.Live, :new
    end
  end

  scope "/", BolognesaWeb do
    pipe_through [:browser, :authenticated]

    delete "/logout", SessionController, :delete

    live_session :authenticated, on_mount: [{BolognesaWeb.UserAuth, :require_authenticated}] do
      live "/", Home.Live, :index
      live "/libraries", Library.Index.Live, :index
      live "/movies", Movie.Index.Live, :index
      live "/movies/review", Movie.Review.Live, :index
      live "/series", Series.Index.Live, :index
      live "/series/review", Series.Review.Live, :index
      live "/series/seasons/:id", Series.Season.Live, :show
      live "/series/:id", Series.Show.Live, :show
      live "/episodes/:id", Episode.Show.Live, :show
      live "/movies/:id", Movie.Show.Live, :show
      live "/about", About.Live, :index
    end
  end

  scope "/", BolognesaWeb do
    pipe_through :media

    get "/episodes/:episode_id/media/:file_id", MediaController, :episode

    get "/episodes/:episode_id/media/:file_id/hls/:session_id/index.m3u8",
        TranscodeController,
        :manifest

    get "/episodes/:episode_id/media/:file_id/hls/:session_id/:segment",
        TranscodeController,
        :segment

    get "/movies/:movie_id/media/:file_id", MediaController, :show

    get "/movies/:movie_id/media/:file_id/hls/:session_id/index.m3u8",
        TranscodeController,
        :manifest

    get "/movies/:movie_id/media/:file_id/hls/:session_id/:segment", TranscodeController, :segment
  end

  # Other scopes may use custom stacks.
  # scope "/api", BolognesaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bolognesa, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BolognesaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
