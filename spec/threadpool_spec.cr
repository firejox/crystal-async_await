require "./spec_helper"

describe AAThreadPool do
  it "can queue proc literal for excuted" do
    ch = AAChannel(Int32).new
    6.times do |i|
      AAThreadPool.queue ->do
        ch.send i
        nil
      end
    end
    (0...6).map { ch.receive.value }.sort.should eq ([0, 1, 2, 3, 4, 5])
  end
end
