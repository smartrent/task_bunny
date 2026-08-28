defmodule TaskBunny.QueueTest do
  use ExUnit.Case, async: false
  import TaskBunny.QueueTestHelper
  alias TaskBunny.Queue

  @queue "task_bunny.queue_test"

  setup do
    clean(Queue.queue_with_subqueues(@queue))
    :ok
  end

  describe "declare_with_subqueues/3" do
    test "declares classic queues (no x-queue-type argument) when queue_type is not given" do
      {work, retry, rejected, scheduled} = Queue.declare_with_subqueues(:default, @queue)

      for state <- [work, retry, rejected, scheduled] do
        refute Enum.any?(state.arguments || [], fn {key, _, _} -> key == "x-queue-type" end)
      end
    end

    test "declares quorum queues when queue_type: :quorum is given" do
      Queue.declare_with_subqueues(:default, @queue, queue_type: :quorum)

      {:ok, channel} = TaskBunny.QueueTestHelper.open_channel()

      for queue <- Queue.queue_with_subqueues(@queue) do
        {:ok, info} = AMQP.Queue.status(channel, queue)
        assert info.queue == queue
      end

      # AMQP.Queue.status/2 doesn't surface arguments back, so assert via
      # the management-free signal available to us: redeclaring with a
      # conflicting queue_type must be rejected by the broker (406
      # PRECONDITION_FAILED, surfaced as an :exit signal — the same failure
      # mode TaskBunny.Initializer/Worker catch/don't-catch in production),
      # proving the queue actually came up as quorum and not classic.
      result =
        try do
          Queue.declare_with_subqueues(:default, @queue, queue_type: :classic)
          :declared
        catch
          :exit, reason -> {:exit, reason}
        end

      assert {:exit, _reason} = result
    end
  end
end
