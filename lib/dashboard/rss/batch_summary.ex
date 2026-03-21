defmodule Dashboard.RSS.BatchSummary do
  @moduledoc """
  Pure helpers for summarizing feed update batch runs.
  """

  @type run :: %{feed: map(), result: term()}

  @type t :: %{
          due_count: non_neg_integer(),
          ok_count: non_neg_integer(),
          error_count: non_neg_integer(),
          exit_count: non_neg_integer(),
          error_samples: [map()]
        }

  @spec build([run()]) :: t()
  def build(runs) when is_list(runs) do
    counts =
      Enum.reduce(
        runs,
        %{due_count: length(runs), ok_count: 0, error_count: 0, exit_count: 0},
        fn %{result: result}, acc ->
          case result do
            {:ok, {:ok, _updated_feed}} ->
              %{acc | ok_count: acc.ok_count + 1}

            {:ok, {:error, _reason}} ->
              %{acc | error_count: acc.error_count + 1}

            {:exit, _reason} ->
              %{acc | exit_count: acc.exit_count + 1}

            _ ->
              %{acc | error_count: acc.error_count + 1}
          end
        end
      )

    Map.put(counts, :error_samples, error_samples(runs))
  end

  defp error_samples(runs) do
    runs
    |> Enum.flat_map(fn %{feed: feed, result: result} ->
      case result do
        {:ok, {:error, reason}} ->
          [%{feed_id: feed.id, title: feed.title, reason: inspect(reason)}]

        {:exit, reason} ->
          [%{feed_id: feed.id, title: feed.title, reason: "exit: #{inspect(reason)}"}]

        _ ->
          []
      end
    end)
    |> Enum.take(5)
  end
end
