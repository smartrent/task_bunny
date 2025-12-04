defmodule TaskBunny.JobRunner do
  # Handles job invocation concerns.
  #
  # This module is private to TaskBunny and should not be accessed directly.
  #
  # JobRunner wraps up job execution and provides you abilities:
  #
  # - invoking jobs concurrently (unblocking job execution)
  # - handling a job crashing
  # - handling timeout
  #
  # ## Signal
  #
  # Once the job has finished it sends a message with a tuple consisted with:
  #
  # - atom indicating message type: :job_finished
  # - result: :ok or {:error, details}
  # - meta: meta data for the job
  #
  # After sending the messsage, JobRunner shuts down all processes it started.
  #
  @moduledoc false

  require Logger
  alias TaskBunny.JobError
  alias TaskBunny.Message

  @doc ~S"""
  Invokes the given job with the given payload.

  The job is run in a seperate process, which is killed after the job.timeout if the job has not finished yet.
  A :error message is send to the :job_finished of the caller if the job times out.
  """
  @spec invoke(map(), {any, any}) :: {:ok | :error, any}
  def invoke(decoded, {_body, meta} = message) do
    caller = self()

    job = decoded["job"]
    payload = decoded["payload"]
    headers = Map.get(meta, :headers, [])

    meta =
      Map.merge(meta, %{
        failures: Message.failed_count(decoded),
        enqueued_at: Message.enqueued_at(headers)
      })

    timeout_error = {:error, JobError.handle_timeout(job, payload)}

    timeout = job.timeout()

    timer =
      Process.send_after(
        caller,
        {:job_finished, timeout_error, message},
        timeout
      )

    pid =
      spawn(fn ->
        send(caller, {:job_finished, run_job(job, payload, meta), message})
        Process.cancel_timer(timer)
      end)

    :timer.kill_after(timeout + 10, pid)
  end

  # Performs a job with the given payload.
  # Any raises or throws in the perform are caught and turned into an :error tuple.
  @spec run_job(atom, any, any) :: :ok | {:ok, any} | {:error, any}
  defp run_job(job, payload, meta) do
    case job.perform(payload, meta) do
      :ok -> :ok
      {:ok, something} -> {:ok, something}
      error -> {:error, JobError.handle_return_value(job, payload, error)}
    end
  rescue
    error ->
      Logger.debug("TaskBunny.JobRunner - Runner rescued #{inspect(error)}")
      {:error, JobError.handle_exception(job, payload, error, __STACKTRACE__)}
  catch
    _, reason ->
      Logger.debug("TaskBunny.JobRunner - Runner caught reason: #{inspect(reason)}")
      {:error, JobError.handle_exit(job, payload, reason, __STACKTRACE__)}
  end
end
