defmodule Dashboard.RSS.IngestServiceTest do
  use Dashboard.DataCase

  alias Dashboard.RSS
  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.IngestService

  setup do
    previous_fetch_worker = Application.get_env(:dashboard, :rss_fetch_worker)
    previous_feed_parser = Application.get_env(:dashboard, :rss_feed_parser)

    Application.put_env(:dashboard, :rss_fetch_worker, __MODULE__.FakeFetchWorker)
    Application.put_env(:dashboard, :rss_feed_parser, __MODULE__.FakeParser)

    on_exit(fn ->
      restore_env(:rss_fetch_worker, previous_fetch_worker)
      restore_env(:rss_feed_parser, previous_feed_parser)
    end)

    :ok
  end

  test "update_pipeline/1 updates feed metadata on modified success" do
    feed = create_feed!("test://modified")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 200
    assert updated.title == "Parsed Feed"
    assert updated.description == "Parsed Description"
    assert updated.link == "https://parsed.example/feed"
    assert updated.ttl == 60
    assert updated.error_count == 0
    assert updated.miss_count == 0
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.last_new_item_at
    assert %DateTime{} = updated.next_fetch
    assert is_binary(updated.content_hash)
    assert String.length(updated.content_hash) == 64
  end

  test "update_pipeline/1 increments miss_count on not modified" do
    feed = create_feed!("test://not_modified", %{miss_count: 2, error_count: 4, etag: "etag-old"})

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 304
    assert updated.miss_count == 3
    assert updated.error_count == 0
    assert updated.status in [:active, :dormant]
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  test "update_pipeline/1 stores canonical_url for redirects" do
    feed = create_feed!("test://redirect")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 301
    assert updated.canonical_url == "https://redirected.example/feed"
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
    assert DateTime.diff(updated.next_fetch, updated.last_fetched_at, :second) in 0..1
  end

  test "update_pipeline/1 records normalized http errors" do
    feed = create_feed!("test://not_found")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 404
    assert updated.error_count == 1
    assert updated.status == :active
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  test "update_pipeline/1 records network errors" do
    feed = create_feed!("test://network")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.error_count == 1
    assert updated.status == :active
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  test "update_pipeline/1 handles parse failures as errors" do
    feed = create_feed!("test://parse_failure", %{title: "Original Title"})

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.error_count == 1
    assert updated.status == :active
    assert updated.title == "Original Title"
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  defp create_feed!(url, attrs \\ %{}) do
    defaults = %{
      title: "Seed Feed",
      url: url,
      status: :active,
      miss_count: 0,
      error_count: 0
    }

    {:ok, feed} =
      defaults
      |> Map.merge(attrs)
      |> RSS.create_feed()

    feed
  end

  defp restore_env(key, nil), do: Application.delete_env(:dashboard, key)
  defp restore_env(key, value), do: Application.put_env(:dashboard, key, value)

  defmodule FakeFetchWorker do
    alias Dashboard.RSS.Feed

    def fetch_feed(%Feed{url: "test://modified"} = feed) do
      response = %HTTPoison.Response{
        status_code: 200,
        headers: [{"etag", "etag-new"}, {"last-modified", "Tue, 03 Mar 2026 10:00:00 GMT"}],
        body: "<rss />"
      }

      {:ok, feed, response}
    end

    def fetch_feed(%Feed{url: "test://parse_failure"} = feed) do
      response = %HTTPoison.Response{status_code: 200, headers: [], body: "<bad />"}
      {:ok, feed, response}
    end

    def fetch_feed(%Feed{url: "test://not_modified"} = feed) do
      response = %HTTPoison.Response{status_code: 304, headers: []}
      {:not_modified, feed, response}
    end

    def fetch_feed(%Feed{url: "test://redirect"} = feed) do
      response = %HTTPoison.Response{
        status_code: 301,
        headers: [{"location", "https://redirected.example/feed"}]
      }

      {:redirect, feed, "https://redirected.example/feed", response}
    end

    def fetch_feed(%Feed{url: "test://not_found"} = feed) do
      response = %HTTPoison.Response{status_code: 404, headers: []}
      {:not_found, feed, response}
    end

    def fetch_feed(%Feed{url: "test://network"} = feed) do
      {:error, feed, :econnrefused}
    end
  end

  defmodule FakeParser do
    def parse_string("<rss />") do
      {:ok,
       %{
         feed: %{
           title: "Parsed Feed",
           description: "Parsed Description",
           link: "https://parsed.example/feed",
           ttl: "60"
         },
         entries: [
           %{pub_date: "Tue, 03 Mar 2026 10:00:00 GMT"},
           %{pub_date: "Mon, 02 Mar 2026 10:00:00 GMT"}
         ]
       }}
    end

    def parse_string("<bad />"), do: {:error, :invalid}
  end
end
