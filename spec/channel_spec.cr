require "./spec_helper"

describe AAChannel do
  it "send returns task" do
    ch = AAChannel(Int32).new(1)
    ch.send(1).should be_a(TaskInterface)
  end

  it "send with TaskCompletionSource returns nil" do
    ch = AAChannel(Int32).new(1)
    tcs = TaskCompletionSource(Int32).new
    ch.send(1, tcs).should be_nil
  end

  describe "send task" do
    it "completed when value has been put into buffer or received" do
      ch = AAChannel(Int32).new(1)
      task = ch.send(1)
      task.status.should eq(AAStatus::COMPLETED)
    end

    it "value is corresponding to the value send if completed" do
      ch = AAChannel(Int32).new(1)
      task = ch.send(123)
      task.value.should eq(123)
    end
  end

  it "receive returns task" do
    ch = AAChannel(Int32).new(1)
    ch.send(1)
    ch.receive.should be_a(TaskInterface)
  end

  it "receive with TaskCompletionSource returns nil" do
    ch = AAChannel(Int32).new(1)
    ch.send(1)
    tcs = TaskCompletionSource(Int32).new
    ch.receive(tcs).should be_nil
  end

  describe "receive task" do
    it "completed if received a value" do
      ch = AAChannel(Int32).new(1)
      ch.send(123)
      task = ch.receive
      task.status.should eq(AAStatus::COMPLETED)
      task.value.should eq(123)
    end
  end

  it "pings with csp" do
    ch = AAChannel(Int32).new
    spawn { ch.send_with_csp(ch.receive_with_csp) }
    ch.send_with_csp(123)
    ch.receive_with_csp.should eq(123)
  end

  it "pings with async/await" do
    foo = AATest.new
    async_spawn { foo.async_await_pings }
    foo.unbuffered_ch.send_with_csp(123)
    foo.unbuffered_ch.receive_with_csp.should eq(123)
  end

  it "can be closed" do
    ch = AAChannel(Int32).new
    ch.closed?.should be_false
    ch.close.should be_nil
    ch.closed?.should be_true
    expect_raises(Channel::ClosedError) { ch.receive_with_csp }
  end

  it "can be closed after sending" do
    ch = AAChannel(Int32).new
    spawn do
      ch.send_with_csp(123)
      ch.close
    end
    ch.receive_with_csp.should eq(123)
    expect_raises(Channel::ClosedError) { ch.receive_with_csp }
  end

  it "cannot send if closed" do
    ch = AAChannel(Int32).new
    ch.close
    expect_raises(Channel::ClosedError) { ch.send 123 }
  end

  it "can receive? when closed" do
    ch = AAChannel(Int32).new
    ch.close
    ch.receive_with_csp?.should be_nil
  end

  it "can receive? when not empty" do
    ch = AAChannel(Int32).new
    spawn { ch.send_with_csp 123 }
    ch.receive_with_csp?.should eq(123)
  end

  it "does receive_first" do
    ch = AAChannel(Int32).new(1)
    ch.send_with_csp(123)
    AAChannel.receive_first_with_csp(ch, AAChannel(Int32).new).should eq(123)
  end

  it "does send_first" do
    ch1 = AAChannel(Int32).new(1)
    ch2 = AAChannel(Int32).new(1)
    ch1.send_with_csp(1)
    AAChannel.send_first_with_csp(2, ch1, ch2)
    ch2.receive_with_csp.should eq 2
  end
end
