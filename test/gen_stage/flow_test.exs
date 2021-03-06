alias Experimental.GenStage

defmodule GenStage.FlowTest do
  use ExUnit.Case, async: true

  alias GenStage.Flow
  doctest Flow

  defmodule Counter do
    use GenStage

    def init(counter) do
      {:producer, counter}
    end

    def handle_demand(demand, counter) when demand > 0 do
      # If the counter is 3 and we ask for 2 items, we will
      # emit the items 3 and 4, and set the state to 5.
      events = Enum.to_list(counter..counter+demand-1)
      {:noreply, events, counter + demand}
    end
  end

  describe "enumerable-stream" do
    @flow Flow.new(stages: 2)
          |> Flow.from_enumerables([[1, 2, 3], [4, 5, 6]])

    test "only sources"  do
      assert @flow |> Enum.sort() == [1, 2, 3, 4, 5, 6]
    end

    test "each/2" do
      parent = self()
      assert @flow |> Flow.each(&send(parent, &1)) |> Enum.sort() ==
             [1, 2, 3, 4, 5, 6]
      assert_received 1
      assert_received 2
      assert_received 3
    end

    test "filter/2" do
      assert @flow |> Flow.filter(&rem(&1, 2) == 0) |> Enum.sort() ==
             [2, 4, 6]
    end

    test "filter_map/3" do
      assert @flow |> Flow.filter_map(&rem(&1, 2) == 0, & &1 * 2) |> Enum.sort() ==
             [4, 8, 12]
    end

    test "flat_map/2" do
      assert @flow |> Flow.flat_map(&[&1, &1]) |> Enum.sort() ==
             [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6]
    end

    test "map/2" do
      assert @flow |> Flow.map(& &1 * 2) |> Enum.sort() ==
             [2, 4, 6, 8, 10, 12]
    end

    test "reject/2" do
      assert @flow |> Flow.reject(&rem(&1, 2) == 0) |> Enum.sort() ==
             [1, 3, 5]
    end

    test "keeps ordering" do
      flow =
        @flow
        |> Flow.filter(&rem(&1, 2) == 0)
        |> Flow.map(fn(x) -> x + 1 end)
        |> Flow.map(fn(x) -> x * 2 end)
      assert Enum.sort(flow) == [6, 10, 14]
    end
  end

  describe "enumerable-unpartioned-stream" do
    @flow Flow.new(stages: 4)
          |> Flow.from_enumerables([[1, 2, 3], [4, 5, 6]])

    test "only sources"  do
      assert @flow |> Enum.sort() == [1, 2, 3, 4, 5, 6]
    end

    test "each/2" do
      parent = self()
      assert @flow |> Flow.each(&send(parent, &1)) |> Enum.sort() ==
             [1, 2, 3, 4, 5, 6]
      assert_received 1
      assert_received 2
      assert_received 3
    end

    test "filter/2" do
      assert @flow |> Flow.filter(&rem(&1, 2) == 0) |> Enum.sort() ==
             [2, 4, 6]
    end

    test "filter_map/3" do
      assert @flow |> Flow.filter_map(&rem(&1, 2) == 0, & &1 * 2) |> Enum.sort() ==
             [4, 8, 12]
    end

    test "flat_map/2" do
      assert @flow |> Flow.flat_map(&[&1, &1]) |> Enum.sort() ==
             [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6]
    end

    test "map/2" do
      assert @flow |> Flow.map(& &1 * 2) |> Enum.sort() ==
             [2, 4, 6, 8, 10, 12]
    end

    test "reject/2" do
      assert @flow |> Flow.reject(&rem(&1, 2) == 0) |> Enum.sort() ==
             [1, 3, 5]
    end

    test "reduce/3" do
      assert @flow |> Flow.reduce(fn -> 0 end, &+/2) |> Flow.map_state(&[&1]) |> Enum.sum() ==
             21
    end

    test "keeps ordering" do
      flow =
        @flow
        |> Flow.filter(&rem(&1, 2) == 0)
        |> Flow.map(fn(x) -> x + 1 end)
        |> Flow.map(fn(x) -> x * 2 end)
      assert Enum.sort(flow) == [6, 10, 14]
    end
  end

  describe "enumerable-partitioned-stream" do
    @flow Flow.new(stages: 4)
          |> Flow.from_enumerables([[1, 2, 3], [4, 5, 6], 7..10])
          |> Flow.partition(stages: 4)

    test "each/2" do
      parent = self()
      assert @flow |> Flow.each(&send(parent, &1)) |> Enum.sort() ==
             [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      assert_received 1
      assert_received 2
      assert_received 3
    end

    test "filter/2" do
      assert @flow |> Flow.filter(&rem(&1, 2) == 0) |> Enum.sort() ==
             [2, 4, 6, 8, 10]
    end

    test "filter_map/3" do
      assert @flow |> Flow.filter_map(&rem(&1, 2) == 0, & &1 * 2) |> Enum.sort() ==
             [4, 8, 12, 16, 20]
    end

    test "flat_map/2" do
      assert @flow |> Flow.flat_map(&[&1, &1]) |> Enum.sort() ==
             [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10]
    end

    test "map/2" do
      assert @flow |> Flow.map(& &1 * 2) |> Enum.sort() ==
             [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    end

    test "reject/2" do
      assert @flow |> Flow.reject(&rem(&1, 2) == 0) |> Enum.sort() ==
             [1, 3, 5, 7, 9]
    end

    test "reduce/3" do
      assert @flow |> Flow.reduce(fn -> 0 end, &+/2) |> Flow.map_state(&[&1]) |> Enum.sort() ==
             [7, 10, 16, 22]

      assert @flow |> Flow.reject(&rem(&1, 2) == 0) |> Flow.reduce(fn -> 0 end, &+/2) |> Flow.map_state(&[&1]) |> Enum.sort() ==
             [0, 0, 3, 22]
    end

    test "keeps ordering" do
      flow =
        @flow
        |> Flow.filter(&rem(&1, 2) == 0)
        |> Flow.map(fn(x) -> x + 1 end)
        |> Flow.map(fn(x) -> x * 2 end)
      assert Enum.sort(flow) == [6, 10, 14, 18, 22]
    end

    test "keeps ordering after reduce" do
      flow =
        @flow
        |> Flow.reduce(fn -> [] end, &[&1 | &2])
        |> Flow.filter(&rem(&1, 2) == 0)
        |> Flow.map(fn(x) -> x + 1 end)
        |> Flow.map(fn(x) -> x * 2 end)
      assert Enum.sort(flow) == [6, 10, 14, 18, 22]
    end

    test "keeps ordering after reduce + map_state" do
      flow =
        @flow
        |> Flow.reduce(fn -> [] end, &[&1 | &2])
        |> Flow.filter(&rem(&1, 2) == 0)
        |> Flow.map(fn(x) -> x + 1 end)
        |> Flow.map(fn(x) -> x * 2 end)
        |> Flow.map_state(&{&2, Enum.sort(&1)})
        |> Flow.map_state(&[&1])
      assert Enum.sort(flow) == [{{0, 4}, [6, 14, 18]},
                                 {{1, 4}, [22]},
                                 {{2, 4}, []},
                                 {{3, 4}, [10]}]
    end
  end

  describe "stages-unpartioned-stream" do
    @flow Flow.new(stages: 1)
    @tag report: [:counter]

    setup do
      {:ok, pid} = GenStage.start_link(Counter, 0)
      {:ok, counter: pid}
    end

    test "only sources", %{counter: pid} do
      assert @flow |> Flow.from_stage(pid) |> Enum.take(5) |> Enum.sort() == [0, 1, 2, 3, 4]
    end

    test "each/2", %{counter: pid} do
      parent = self()
      assert @flow |> Flow.from_stage(pid) |> Flow.each(&send(parent, &1)) |> Enum.take(5) |> Enum.sort() ==
             [0, 1, 2, 3, 4]
      assert_received 1
      assert_received 2
      assert_received 3
    end

    test "filter/2", %{counter: pid} do
      assert @flow |> Flow.from_stage(pid) |> Flow.filter(&rem(&1, 2) == 0) |> Enum.take(5) |> Enum.sort() ==
             [0, 2, 4, 6, 8]
    end

    test "filter_map/3", %{counter: pid} do
      assert @flow |> Flow.from_stage(pid) |> Flow.filter_map(&rem(&1, 2) == 0, & &1 * 2) |> Enum.take(5) |> Enum.sort() ==
             [0, 4, 8, 12, 16]
    end

    test "flat_map/2", %{counter: pid} do
      assert @flow |> Flow.from_stage(pid) |> Flow.flat_map(&[&1, &1]) |> Enum.take(5) |> Enum.sort() ==
             [0, 0, 1, 1, 2]
    end

    test "map/2", %{counter: pid} do
      assert @flow |> Flow.from_stage(pid) |> Flow.map(& &1 * 2) |> Enum.take(5) |> Enum.sort() ==
             [0, 2, 4, 6, 8]
    end

    test "reject/2", %{counter: pid} do
      assert @flow |> Flow.from_stage(pid) |> Flow.reject(&rem(&1, 2) == 0) |> Enum.take(5) |> Enum.sort() ==
             [1, 3, 5, 7, 9]
    end

    test "keeps ordering", %{counter: pid} do
      flow =
        @flow
        |> Flow.from_stage(pid)
        |> Flow.filter(&rem(&1, 2) == 0)
        |> Flow.map(fn(x) -> x + 1 end)
        |> Flow.map(fn(x) -> x * 2 end)
      assert flow |> Enum.take(5) |> Enum.sort() == [2, 6, 10, 14, 18]
    end
  end

  describe "partition/2" do
    test "allows emititing events or the whole state" do
      assert Flow.new(stages: 4)
             |> Flow.from_enumerables([[1, 2, 3], [4, 5, 6], 7..10])
             |> Flow.partition(emit: :state, stages: 4)
             |> Flow.reduce(fn -> [] end, &[&1 | &2])
             |> Flow.map_state(&Enum.sort(&1))
             |> Enum.sort() == [[1, 5, 7, 9], [2, 6, 8], [3, 4], [10]]

      assert Flow.new(stages: 4)
             |> Flow.from_enumerables([[1, 2, 3], [4, 5, 6], 7..10])
             |> Flow.partition(emit: :events, stages: 4)
             |> Flow.reduce(fn -> [] end, &[&1 | &2])
             |> Flow.map_state(&Enum.sort(&1))
             |> Enum.sort() == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    end

    test "allows custom partitioning" do
      assert Flow.from_enumerables([[1, 2, 3], [4, 5, 6], 7..10])
             |> Flow.partition(hash: fn _, _ -> 0 end, stages: 4)
             |> Flow.reduce(fn -> [] end, &[&1 | &2])
             |> Flow.map_state(&[Enum.sort(&1)])
             |> Enum.filter(& &1 != []) == [[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]]
    end

    test "allows element based partitioning" do
      assert Flow.from_enumerables([[{1, 1}, {2, 2}, {3, 3}], [{1, 4}, {2, 5}, {3, 6}]])
             |> Flow.partition(hash: {:elem, 0}, stages: 2)
             |> Flow.reduce(fn -> [] end, &[&1 | &2])
             |> Flow.map_state(fn acc -> [acc |> Enum.map(&elem(&1, 1)) |> Enum.sort()] end)
             |> Enum.sort() == [[1, 2, 4, 5], [3, 6]]
    end

    test "allows key based partitioning" do
      assert Flow.from_enumerables([[%{key: 1, value: 1}, %{key: 2, value: 2}, %{key: 3, value: 3}],
                                    [%{key: 1, value: 4}, %{key: 2, value: 5}, %{key: 3, value: 6}]])
             |> Flow.partition(hash: {:key, :key}, stages: 2)
             |> Flow.reduce(fn -> [] end, &[&1 | &2])
             |> Flow.map_state(fn acc -> [acc |> Enum.map(& &1.value) |> Enum.sort()] end)
             |> Enum.sort() == [[1, 2, 4, 5], [3, 6]]
    end
  end
end
