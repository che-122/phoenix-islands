defmodule Dashboard.Repo do
  use Ecto.Repo,
    otp_app: :dashboard_test,
    adapter: Ecto.Adapters.SQLite3
end
