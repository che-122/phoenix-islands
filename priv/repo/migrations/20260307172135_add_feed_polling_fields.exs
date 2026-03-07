defmodule Dashboard.Repo.Migrations.AddFeedPollingFields do
  use Ecto.Migration

  def change do
    alter table(:feed) do
      add :canonical_url, :string
      add :content_hash, :string
      add :status, :string, default: "active", null: false
      add :suspension_reason, :string
      add :last_http_status, :integer
      add :last_fetched_at, :utc_datetime
      add :last_new_item_at, :utc_datetime
      add :miss_count, :integer, default: 0, null: false
      add :error_count, :integer, default: 0, null: false
      add :observed_interval, :integer
      add :ttl, :integer
    end

    create index(:feed, [:status])
    create index(:feed, [:next_fetch])
  end
end
