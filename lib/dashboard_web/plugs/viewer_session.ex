defmodule DashboardWeb.Plugs.ViewerSession do
  @moduledoc """
  Assigns viewer session for browser-rendered HTML pages.
  """
  require Logger

  import Plug.Conn

  # 400 days
  @max_age 34_560_000

  def init(opts), do: opts

  def call(conn, _opts) do
    if Phoenix.Controller.get_format(conn) == "html" do
      conn = fetch_cookies(conn, signed: ~w(viewer_session))

      case conn.cookies["viewer_session"] do
        nil ->
          uuid = Ecto.UUID.generate()
          conn |> refresh_session(uuid)

        {:ok, cookie} ->
          decoded = Jason.decode!(cookie)

          %{"uuid" => uuid, "refreshed_at" => refreshed_at} =
            Map.take(decoded, ["uuid", "refreshed_at"])

          with {:ok, parsed, _offset} <- DateTime.from_iso8601(refreshed_at),
               plus_seven <- DateTime.add(parsed, 7, :day),
               true <- DateTime.diff(DateTime.utc_now(), plus_seven, :day) > 7 do
            conn |> refresh_session(uuid)
          else
            _ -> conn
          end
      end
    end
  end

  defp refresh_session(conn, uuid) do
    payload = %{uuid: uuid, refreshed_at: DateTime.utc_now()}

    conn
    |> put_resp_cookie(
      "viewer_session",
      Jason.encode(payload),
      sign: true,
      http_only: true,
      max_age: @max_age,
      same_site: "Lax"
    )
    |> assign(:viewer_session, payload)
  end
end
