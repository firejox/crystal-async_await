require "./spec_helper"

describe TaskCompletionSource do
  describe "new" do
    it "create a incomplete task" do
      tcs = TaskCompletionSource(Nil).new
      tcs.task.status.should eq(AAStatus::INCOMPLETE)
    end
  end

  describe "task" do
    it "is completed after set value" do
      tcs = TaskCompletionSource(Nil).new
      tcs.value = nil
      tcs.task.status.should eq(AAStatus::COMPLETED)
    end

    it "is faulted after set exception" do
      tcs = TaskCompletionSource(Nil).new
      tcs.exception = Exception.new
      tcs.task.status.should eq(AAStatus::FAULTED)
    end
  end

  describe "try_set_value?" do
    it "return true if set value on incomplete task, otherwise false" do
      tcs = TaskCompletionSource(Int32).new
      tcs.try_set_value?(1).should be_true
      tcs.task.status.should eq(AAStatus::COMPLETED)
      tcs.try_set_value?(1).should be_false
    end
  end

  describe "try_set_exception?" do
    it "return true if set exception on incomplete task, otherwise false" do
      tcs = TaskCompletionSource(Int32).new
      tcs.try_set_exception?(Exception.new).should be_true
      tcs.task.status.should eq(AAStatus::FAULTED)
      tcs.try_set_exception?(Exception.new).should be_false
    end
  end

  it "cannot set both value and exception" do
    tcs = TaskCompletionSource(Nil).new
    tcs.value = nil
    expect_raises(TaskCompletionSource::InvalidOperation) do
      tcs.exception = Exception.new
    end
  end
end
