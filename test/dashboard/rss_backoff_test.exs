defmodule Dashboard.RSS.BackoffTest do
  use ExUnit.Case, async: true

  alias Dashboard.RSS.Backoff
  alias Dashboard.RSS.Feed

  describe "calculate_next/3" do
    setup do
      previous_config = Application.get_env(:dashboard, Backoff)
      Application.put_env(:dashboard, Backoff, jitter_percent: 0)

      on_exit(fn ->
        if is_nil(previous_config) do
          Application.delete_env(:dashboard, Backoff)
        else
          Application.put_env(:dashboard, Backoff, previous_config)
        end
      end)

      :ok
    end

    test "uses observed cadence for modified feeds" do
      feed = %Feed{observed_interval: 3600, ttl: nil}

      before = DateTime.utc_now()
      next_fetch = Backoff.calculate_next(feed, nil, :modified)

      assert_interval_close(next_fetch, before, 1800)
    end

    test "honors cache-control max-age floor for modified feeds" do
      feed = %Feed{observed_interval: 3600, ttl: nil}

      response = %HTTPoison.Response{
        headers: [{"cache-control", "public, max-age=4000"}],
        status_code: 200
      }

      before = DateTime.utc_now()
      next_fetch = Backoff.calculate_next(feed, response, :modified)

      assert_interval_close(next_fetch, before, 4000)
    end

    test "backs off not-modified feeds from current interval" do
      now = DateTime.utc_now()
      last_fetched_at = DateTime.add(now, -3600, :second)

      feed = %Feed{
        status: :active,
        ttl: nil,
        last_fetched_at: last_fetched_at,
        next_fetch: now
      }

      before = DateTime.utc_now()
      next_fetch = Backoff.calculate_next(feed, nil, :not_modified)

      assert_interval_close(next_fetch, before, 5400)
    end

    test "rate-limited errors use retry-after with min clamp" do
      feed = %Feed{error_count: 2}
      response = %HTTPoison.Response{headers: [{"retry-after", "120"}], status_code: 429}

      before = DateTime.utc_now()
      next_fetch = Backoff.calculate_next(feed, response, {:error, %{reason: :rate_limited}})

      assert_interval_close(next_fetch, before, 300)
    end

    test "gone errors follow reprobe schedule" do
      feed = %Feed{error_count: 0}

      before = DateTime.utc_now()
      next_fetch = Backoff.calculate_next(feed, nil, {:error, %{reason: :gone}})

      assert_interval_close(next_fetch, before, 7 * 24 * 60 * 60)
    end
  end

  describe "calculate_redirect_next/2" do
    test "returns immediate datetime" do
      feed = %Feed{}
      response = %HTTPoison.Response{status_code: 301, headers: []}

      before = DateTime.utc_now()
      next_fetch = Backoff.calculate_redirect_next(feed, response)

      assert DateTime.diff(next_fetch, before, :second) in 0..1
    end
  end

  describe "evaluate_health/1" do
    test "suspends feed immediately on 410" do
      feed = %Feed{last_http_status: 410}
      assert Backoff.evaluate_health(feed) == :suspended
    end

    test "suspends feed on repeated 404 after threshold" do
      last_new_item_at = DateTime.add(DateTime.utc_now(), -8 * 24 * 60 * 60, :second)
      feed = %Feed{last_http_status: 404, error_count: 10, last_new_item_at: last_new_item_at}

      assert Backoff.evaluate_health(feed) == :suspended
    end

    test "marks feed dormant after long inactivity" do
      last_new_item_at = DateTime.add(DateTime.utc_now(), -31 * 24 * 60 * 60, :second)
      feed = %Feed{status: :active, error_count: 0, last_new_item_at: last_new_item_at}

      assert Backoff.evaluate_health(feed) == :dormant
    end

    test "keeps healthy feed active" do
      last_new_item_at = DateTime.add(DateTime.utc_now(), -1 * 24 * 60 * 60, :second)
      feed = %Feed{status: :active, error_count: 0, last_new_item_at: last_new_item_at}

      assert Backoff.evaluate_health(feed) == :active
    end
  end

  defp assert_interval_close(next_fetch, before, expected_seconds) do
    actual_seconds = DateTime.diff(next_fetch, before, :second)
    assert abs(actual_seconds - expected_seconds) <= 1
  end
end
