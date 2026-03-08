defmodule DashboardWeb.PageControllerTest do
  use DashboardWeb.ConnCase

  import Dashboard.RSSFixtures

  alias Dashboard.Repo
  alias Dashboard.RSS.FeedEntry
  alias Dashboard.RSS.FeedEntryEnclosure

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET /list", %{conn: conn} do
    feed = feed_fixture(%{title: "Phoenix Feed", url: "https://example.com/phoenix.xml"})

    conn = get(conn, ~p"/list")

    assert html_response(conn, 200) =~ "Feeds"
    assert html_response(conn, 200) =~ feed.title
    assert html_response(conn, 200) =~ ~p"/list/#{feed.id}/entries"
  end

  test "GET /list/:feed_id/entries", %{conn: conn} do
    feed = feed_fixture(%{title: "Phoenix Feed", url: "https://example.com/phoenix.xml"})

    {:ok, entry} =
      %FeedEntry{}
      |> FeedEntry.changeset(%{
        feed_id: feed.id,
        identity_source: "guid",
        identity_key: "entry-1",
        identity_hash: "hash-1",
        title: "Episode 1",
        link: "https://example.com/episode-1",
        published_at: ~U[2026-03-08 12:00:00Z],
        first_seen_at: DateTime.utc_now(),
        last_seen_at: DateTime.utc_now()
      })
      |> Repo.insert()

    conn = get(conn, ~p"/list/#{feed.id}/entries")
    body = html_response(conn, 200)

    assert body =~ feed.title
    assert body =~ "Episode 1"
    assert body =~ "https://example.com/episode-1"
    assert body =~ ~p"/list/#{feed.id}/entries/#{entry.id}"
  end

  test "GET /list/:feed_id/entries/:entry_id", %{conn: conn} do
    feed = feed_fixture(%{title: "Phoenix Feed", url: "https://example.com/phoenix.xml"})

    {:ok, entry} =
      %FeedEntry{}
      |> FeedEntry.changeset(%{
        feed_id: feed.id,
        identity_source: "guid",
        identity_key: "entry-2",
        identity_hash: "hash-2",
        title: "Episode detail",
        summary: "A short summary",
        published_at: ~U[2026-03-08 16:00:00Z],
        first_seen_at: DateTime.utc_now(),
        last_seen_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, _enclosure} =
      %FeedEntryEnclosure{}
      |> FeedEntryEnclosure.changeset(%{
        feed_entry_id: entry.id,
        url: "https://cdn.example.com/episode-detail.mp3",
        media_type: "audio/mpeg"
      })
      |> Repo.insert()

    conn = get(conn, ~p"/list/#{feed.id}/entries/#{entry.id}")
    body = html_response(conn, 200)

    assert body =~ "Article"
    assert body =~ "Episode detail"
    assert body =~ "A short summary"
    assert body =~ "<audio"
    assert body =~ "https://cdn.example.com/episode-detail.mp3"
  end
end
