require "./spec_helper"

describe AAChannel do
  it "send returns task" do
    ch = AAChannel(Int32).new(1)
    ch.send(1).should be_a(TaskInterface)
  end

  it "send with TaskCompletionSource returns nil" do
    ch = AAChannel(Int32).new(1)
    tcs = TaskCompletionSource(Nil).new
    ch.send(1, tcs).should be_nil
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

  it "pings" do
    ch = AAChannel(Int32).new
    spawn { ch.send_with_csp(ch.receive_with_csp) }
    ch.send_with_csp(123)
    ch.receive_with_csp.should eq(123)
  end
end
