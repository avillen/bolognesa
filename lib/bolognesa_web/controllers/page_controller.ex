defmodule BolognesaWeb.PageController do
  use BolognesaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
