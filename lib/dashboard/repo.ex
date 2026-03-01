defmodule Dashboard.Repo do
  use Ecto.Repo,
    otp_app: :dashboard,
    adapter: Ecto.Adapters.SQLite3
end
