require 'unimidi'

module PM

# Implements a DSL for describing a PatchMaster setup.
class DSL

  include PM

  def initialize(no_midi=false)
    @no_midi = no_midi
    @pm = PatchMaster.instance
  end

  def load(file)
    contents = IO.read(file)
    @inputs = {}
    @outputs = {}
    @triggers = []
    @filters = []
    @songs = {}                 # key = name, value = song
    instance_eval(contents)
    read_triggers(contents)
    read_filters(contents)
  end

  def input(port_num, sym, name=nil)
    raise "input: two inputs can not have the same symbol (:#{sym})" if @inputs[sym]

    input = InputInstrument.new(sym, name, port_num, @no_midi)
    @inputs[sym] = input
    @pm.inputs << input
  rescue => ex
    raise "input: error creating input instrument \"#{name}\" on input port #{port_num}: #{ex}"
  end
  alias_method :in, :input

  def output(port_num, sym, name=nil)
    raise "output: two outputs can not have the same symbol (:#{sym})" if @outputs[sym]

    output = OutputInstrument.new(sym, name, port_num, @no_midi)
    @outputs[sym] = output
    @pm.outputs << output
  rescue => ex
    raise "output: error creating output instrument \"#{name}\" on output port #{port_num}: #{ex}"
  end
  alias_method :out, :output

  def message(name, bytes)
    @pm.messages[name.downcase] = bytes
  end

  def message_key(name, key_or_sym)
    if !@pm.no_gui              # TODO get rid of double negative
      PM::Main.instance.bind_message(name, key_or_sym)
    end
  end

  def trigger(instrument_sym, bytes, &block)
    instrument = @inputs[instrument_sym]
    raise "trigger: error finding instrument #{instrument_sym}" unless instrument
    t = Trigger.new(bytes, block)
    instrument.triggers << t
    @triggers << t
  end

  def song(name)
    @song = Song.new(name)      # ctor saves into @pm.all_songs
    @songs[name] = @song
    yield @song if block_given?
  end

  def patch(name)
    @patch = Patch.new(name)
    @song << @patch
    yield @patch if block_given?
  end

  def start_bytes(bytes)
    @patch.start_bytes = bytes
  end

  def stop_bytes(bytes)
    @patch.stop_bytes = bytes
  end

  def connection(in_sym, in_chan, out_sym, out_chan)
    input = @inputs[in_sym]
    in_chan = nil if in_chan == :all || in_chan == :any
    raise "can't find input instrument #{in_sym}" unless input
    output = @outputs[out_sym]
    raise "can't find outputput instrument #{out_sym}" unless output

    @conn = Connection.new(input, in_chan, output, out_chan)
    @patch << @conn
    yield @conn if block_given?
  end
  alias_method :conn, :connection
  alias_method :c, :connection

  # If only +bank_or_prog+ is specified, then it's a program change. If
  # both, then it's bank number.
  def prog_chg(bank_or_prog, prog=nil)
    if prog
      @conn.bank = bank_or_prog
      @conn.pc_prog = prog
    else
      @conn.pc_prog = bank_or_prog
    end
  end
  alias_method :pc, :prog_chg

  # If +start_or_range+ is a Range, use that. Else either or both params may
  # be nil.
  def zone(start_or_range=nil, stop=nil)
    @conn.zone = if start_or_range.kind_of? Range
                         start_or_range
                       elsif start_or_range == nil && stop == nil
                         nil
                       else
                         ((start_or_range || 0) .. (stop || 127))
                       end
  end
  alias_method :z, :zone

  def transpose(xpose)
    @conn.xpose = xpose
  end
  alias_method :xpose, :transpose
  alias_method :x, :transpose

  def filter(&block)
    @conn.filter = Filter.new(block)
    @filters << @conn.filter
  end
  alias_method :f, :filter

  def song_list(name, song_names)
    sl = SongList.new(name)
    @pm.song_lists << sl
    song_names.each do |sn|
      song = @songs[sn]
      raise "song \"#{sn}\" not found (song list \"#{name}\")" unless song
      sl << song
    end
  end

  # ****************************************************************

  def save(file)
    File.open(file, 'w') { |f|
      save_instruments(f)
      save_triggers(f)
      save_songs(f)
      save_song_lists(f)
    }
  end

  def save_instruments(f)
    @pm.inputs.each do |instr|
      f.puts "input #{instr.port_num}, :#{instr.sym}, #{quoted(instr.name)}"
    end
    @pm.outputs.each do |instr|
      f.puts "output #{instr.port_num}, :#{instr.sym}, #{quoted(instr.name)}"
    end
    f.puts
  end

  def save_triggers(f)
    @pm.inputs.each do |instrument|
      instrument.triggers.each do |trigger|
        str = "trigger :#{instrument.sym}, #{trigger.bytes.inspect} #{trigger.text}"
        f.puts str
      end
    end
    f.puts
  end

  def save_songs(f)
    @pm.all_songs.songs.each do |song|
      f.puts "song #{quoted(song.name)} do"
      song.patches.each { |patch| save_patch(f, patch) }
      f.puts "end"
      f.puts
    end
  end

  def save_patch(f, patch)
    f.puts "  patch #{quoted(patch.name)} do"
    f.puts "    start_bytes #{patch.start_bytes.inspect}" if patch.start_bytes
    patch.connections.each { |conn| save_connection(f, conn) }
    f.puts "  end"
  end

  def save_connection(f, conn)
    in_chan = conn.input_chan ? conn.input_chan + 1 : 'nil'
    out_chan = conn.output_chan + 1
    f.puts "    conn :#{conn.input.sym}, #{in_chan}, :#{conn.output.sym}, #{out_chan} do"
    f.puts "      prog_chg #{conn.pc_prog}" if conn.pc?
    f.puts "      zone #{conn.note_num_to_name(conn.zone.begin)}, #{conn.note_num_to_name(conn.zone.end)}" if conn.zone
    f.puts "      xpose #{conn.xpose}" if conn.xpose
    f.puts "      filter #{conn.filter.text}" if conn.filter
    f.puts "    end"
  end

  def save_song_lists(f)
    @pm.song_lists.each do |sl|
      next if sl == @pm.all_songs
      f.puts "song_list #{quoted(sl.name)}, ["
      @pm.all_songs.songs.each do |song|
        f.puts "  #{quoted(song.name)},"
      end
      f.puts "]"
    end
  end

  def quoted(str)
    "\"#{str.gsub('"', "\\\"")}\"" # ' <= un-confuse Emacs font-lock
  end

  # ****************************************************************

  private

  def read_triggers(contents)
    read_block_text('trigger', @triggers, contents)
  end

  def read_filters(contents)
    read_block_text('filter', @filters, contents)
  end

  # Extremely simple block text reader. Relies on indentation to detect end
  # of code block.
  def read_block_text(name, containers, contents)
    i = -1
    in_block = false
    block_indentation = nil
    block_end_token = nil
    contents.each_line do |line|
      if line =~ /^(\s*)#{name}\s*.*?(({|do|->\s*{|lambda\s*{)(.*))/
        block_indentation, text = $1, $2
        i += 1
        containers[i].text = text + "\n"
        in_block = true
        block_end_token = case text
                             when /^{/
                               "}"
                             when /^do\b/
                               "end"
                             when /^(->|lambda)\s*({|do)/
                               $2 == "{" ? "}" : "end"
                             else
                               "}|end" # regex
                             end
      elsif in_block
        line =~ /^(\s*)(.*)/
        indentation, text = $1, $2
        if indentation.length <= block_indentation.length
          if text =~ /^#{block_end_token}/
            containers[i].text << line
          end
          in_block = false
        else
          containers[i].text << line
        end
      end
    end
    containers.each { |thing| thing.text.strip! if thing.text }
  end

end
end
