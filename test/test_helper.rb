require 'test/unit'
require 'patchmaster'
require 'midi-eye'

# For all tests, make sure mock I/O MIDI ports are used.
PM::PatchMaster.instance.no_midi!

module PM

# To help with testing, we replace MockInputPort#gets and
# MockOutputPort#puts with versions that send what we want and save what is
# received.
class MockInputPort

  attr_accessor :data_to_send
    
  # For MIDIEye::Listener
  def self.is_compatible?(input)
    true
  end

  def initialize(_=nil)
    @t0 = (Time.now.to_f * 1000).to_i
  end

  def gets
    retval = @data_to_send || []
    @data_to_send = []
    [{:data => retval, :timestamp => (Time.now.to_f * 1000).to_i - @t0}]
  end
    
  def poll
    yield gets
  end

  # add this class to the Listener class' known input types
  MIDIEye::Listener.input_types << self 
end

class MockOutputPort

  attr_accessor :buffer

  def initialize
    @buffer = []
  end

  def puts(bytes)
    @buffer += bytes
  end
end
end

# A TestConnection records all bytes received and passes them straight
# through.
class TestConnection < PM::Connection

  attr_accessor :bytes_received

  def midi_in(bytes)
    @bytes_received ||= []
    @bytes_received += bytes
    midi_out(bytes)
  end

end
