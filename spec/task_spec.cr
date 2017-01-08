require "./spec_helper"

describe Task do
  describe "a completed task" do
    it "is completed" do
      Task.new(nil).status.should eq(AAStatus::COMPLETED)
    end
    it "has not nil value except Task(Nil)" do
      Task.new(1).value.should_not eq(nil)
    end
  end

  describe "a faulted task" do
    it "is faulted" do
      Task(Nil).from_exception(Exception.new).status.should eq(AAStatus::FAULTED)
    end

    it "has not nil exception" do
      Task(Nil).from_exception(Exception.new).exception.should_not eq(nil)
    end
  end

  describe "yield" do
    it "creates awaitable object for await" do
      Task.yield.should be_a(Awaitable)
    end

    it "would be completed in next check status" do
      a = Task.yield
      a.status.should eq(AAStatus::INCOMPLETE)
      a.status.should eq(AAStatus::COMPLETED)
    end
  end

  describe "delay" do
    it "creates Task object for await" do
      Task.delay(Time::Span.new(0, 0, 1)).should be_a(Task(Nil))
    end

    it "would be completed after timeout" do
      a = Task.delay(Time::Span.new(0, 0, 1))
      sleep Time::Span.new(0, 0, 1)
      a.status.should eq(AAStatus::COMPLETED)
    end
  end
end
