defmodule NSQ.ProducerTest do
  use ExUnit.Case, async: false
  doctest NSQ.Producer


  @test_topic "__nsq_producer_test_topic__"
  @test_channel1 "__nsq_producer_test_channel1__"


  setup do
    Logger.configure(level: :warn)
    HTTPotion.post("http://127.0.0.1:6751/topic/delete?topic=#{@test_topic}")
    HTTPotion.post("http://127.0.0.1:6761/topic/delete?topic=#{@test_topic}")
    :ok
  end


  test "#start_link starts a new producer, discoverable via nsqlookupd" do
    configured_nsqds = [{"127.0.0.1", 6750}, {"127.0.0.1", 6760}]
    {:ok, producer} = NSQ.Producer.start_link(
      configured_nsqds,
      "__nsq_producer_test_topic__",
      %NSQ.Config{nsqds: configured_nsqds}
    )

    # Produce a ton of messages so we're "guaranteed" both our nsqds have
    # messages and are therefore discoverable.
    Enum.map 0..100, fn(_i) -> NSQ.Producer.pub(producer, "test 1") end

    lookupds = [{"127.0.0.1", 6771}, {"127.0.0.1", 6781}]
    discovered_nsqds = NSQ.Connection.nsqds_from_lookupds(lookupds, "__nsq_producer_test_topic__")

    # Sort the arrays so we can compare them.
    configured_nsqds = Enum.sort_by(configured_nsqds, &inspect(&1))
    discovered_nsqds = Enum.sort_by(discovered_nsqds, &inspect(&1))

    assert configured_nsqds == discovered_nsqds
  end


  test "messages added via pub are handled by a consumer" do
    configured_nsqds = [{"127.0.0.1", 6750}, {"127.0.0.1", 6760}]
    {:ok, producer} = NSQ.Producer.start_link(
      configured_nsqds,
      "__nsq_producer_test_topic__",
      %NSQ.Config{nsqds: configured_nsqds}
    )

    test_pid = self
    NSQ.Consumer.start_link(@test_topic, @test_channel1, %NSQ.Config{
      nsqds: configured_nsqds,
      message_handler: fn(body, msg) ->
        assert body == "test abc"
        assert msg.attempts == 1
        send(test_pid, :handled)
        {:ok}
      end
    })

    NSQ.Producer.pub(producer, "test abc")
    assert_receive(:handled, 2000)
  end
end